import SwiftUI
import UIKit

enum NesticAppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    static let storageKey = "nestic.appearance.v1"

    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

// The interface deliberately uses an adaptive paper palette, including a dark appearance.
enum NesticTheme {
    static let forest = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.74, green: 0.85, blue: 0.65, alpha: 1) : UIColor(red: 0.14, green: 0.30, blue: 0.24, alpha: 1) })
    static let ink = Color.primary
    static let paper = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.08, green: 0.11, blue: 0.09, alpha: 1) : UIColor(red: 0.97, green: 0.96, blue: 0.93, alpha: 1) })
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
    static let lime = Color(red: 0.84, green: 0.93, blue: 0.60)
    static let deepForest = Color(red: 0.14, green: 0.30, blue: 0.24)
    static let muted = Color.secondary
}

struct NestMark: View {
    var color: Color = NesticTheme.forest
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                ForEach(0..<3) { i in
                    Ellipse().fill(color)
                        .frame(width: w * 0.15, height: h * 0.23)
                        .rotationEffect(.degrees(Double(i - 1) * 16))
                        .position(x: w * (0.30 + Double(i) * 0.20), y: h * (i == 1 ? 0.31 : 0.36))
                }
                Path { p in
                    p.move(to: CGPoint(x: w * 0.12, y: h * 0.48))
                    p.addQuadCurve(to: CGPoint(x: w * 0.88, y: h * 0.48), control: CGPoint(x: w * 0.5, y: h * 1.05))
                    p.move(to: CGPoint(x: w * 0.23, y: h * 0.76))
                    p.addQuadCurve(to: CGPoint(x: w * 0.77, y: h * 0.76), control: CGPoint(x: w * 0.5, y: h * 1.04))
                }.stroke(color, style: StrokeStyle(lineWidth: w * 0.07, lineCap: .round))
            }
        }.accessibilityHidden(true)
    }
}

struct PrimaryButton: View {
    let title: String
    var symbol: String? = nil
    var busy = false
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                if busy { ProgressView().tint(.white) }
                Text(title).fontWeight(.semibold)
                if let symbol { Image(systemName: symbol) }
            }
            .frame(maxWidth: .infinity).padding(.vertical, 17)
            .foregroundStyle(.white).background(NesticTheme.deepForest, in: RoundedRectangle(cornerRadius: 18))
        }.disabled(busy)
    }
}

struct SubjectAvatar: View {
    let emoji: String
    var photoData: String? = nil
    var size: CGFloat = 52
    var body: some View {
        Group {
            if let image = SubjectPhoto.image(from: photoData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Text(emoji).font(.system(size: size * 0.48))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(NesticTheme.lime.opacity(0.24))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.32))
        .overlay {
            RoundedRectangle(cornerRadius: size * 0.32)
                .stroke(.white.opacity(0.35), lineWidth: 1)
        }
        .accessibilityHidden(true)
    }
}

enum SubjectPhoto {
    private static let imageCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 64
        cache.totalCostLimit = 24 * 1024 * 1024
        return cache
    }()

    static func image(from encoded: String?) -> UIImage? {
        guard let encoded else { return nil }
        let key = encoded as NSString
        if let cached = imageCache.object(forKey: key) { return cached }
        guard let data = Data(base64Encoded: encoded), let image = UIImage(data: data) else { return nil }
        let cost = image.cgImage.map { $0.bytesPerRow * $0.height } ?? data.count
        imageCache.setObject(image, forKey: key, cost: cost)
        return image
    }

    /// Subject photos are avatars, not originals. Keep the base64 value small enough
    /// for the entity JSON request and for lightweight realtime refreshes.
    static func encoded(from data: Data, maxDimension: CGFloat = 320) -> String? {
        guard let image = UIImage(data: data), image.size.width > 0, image.size.height > 0 else { return nil }
        let maxJPEGBytes = 28_000
        var dimension = min(maxDimension, max(image.size.width, image.size.height))
        var quality: CGFloat = 0.58

        for _ in 0..<8 {
            let scale = min(1, dimension / max(image.size.width, image.size.height))
            let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let renderer = UIGraphicsImageRenderer(size: size)
            let resized = renderer.image { _ in
                image.draw(in: CGRect(origin: .zero, size: size))
            }
            if let jpeg = resized.jpegData(compressionQuality: quality), jpeg.count <= maxJPEGBytes {
                return jpeg.base64EncodedString()
            }
            dimension *= 0.78
            quality = max(0.35, quality - 0.04)
        }

        return nil
    }
}

/// Local cache for shared event photos. The server-side R2 object is the
/// source of truth; this cache only avoids downloading the same image for
/// every row render.
enum NesticEntryPhotoStore {
    private static let directoryName = "EntryPhotos"
    private static let imageCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 32
        cache.totalCostLimit = 48 * 1024 * 1024
        return cache
    }()

    private static func cachedImage(identifier: String) -> UIImage? {
        let key = identifier as NSString
        if let image = imageCache.object(forKey: key) { return image }
        guard let url = fileURL(for: identifier), let data = try? Data(contentsOf: url),
              let image = UIImage(data: data) else { return nil }
        let cost = image.cgImage.map { $0.bytesPerRow * $0.height } ?? data.count
        imageCache.setObject(image, forKey: key, cost: cost)
        return image
    }


    private static var directoryURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Nestic", isDirectory: true)
            .appendingPathComponent(directoryName, isDirectory: true)
    }

    private static func fileURL(for identifier: String) -> URL? {
        directoryURL?.appendingPathComponent("\(identifier).jpg")
    }

    static func data(for entryID: UUID) -> Data? {
        guard let url = fileURL(for: entryID.uuidString) else { return nil }
        return try? Data(contentsOf: url)
    }

    static func image(for entryID: UUID) -> UIImage? {
        cachedImage(identifier: entryID.uuidString)
    }

    static func data(forPhotoID photoID: UUID) -> Data? {
        guard let url = fileURL(for: photoID.uuidString) else { return nil }
        return try? Data(contentsOf: url)
    }

    static func image(forPhotoID photoID: UUID) -> UIImage? {
        cachedImage(identifier: photoID.uuidString)
    }

    static func jpegData(from sourceData: Data) throws -> Data {
        guard let image = UIImage(data: sourceData), image.size.width > 0, image.size.height > 0 else {
            throw NSError(domain: "NesticEntryPhotoStore", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "The selected image could not be read."])
        }

        // Keep the request comfortably below the server's default 512 KiB limit.
        // The renderer scale must be explicit: on a Retina iPhone, a 1600-point
        // image otherwise becomes a 4800-pixel image before compression.
        let maxJPEGBytes = 400_000
        var dimension = min(CGFloat(1600), max(image.size.width, image.size.height))
        var quality: CGFloat = 0.78
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1

        for _ in 0..<12 {
            let scale = min(1, dimension / max(image.size.width, image.size.height))
            let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let renderer = UIGraphicsImageRenderer(size: size, format: format)
            let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
            if let jpeg = resized.jpegData(compressionQuality: quality), jpeg.count <= maxJPEGBytes {
                return jpeg
            }

            if quality > 0.42 {
                quality -= 0.07
            } else {
                dimension *= 0.8
                quality = 0.76
            }
        }

        throw NSError(domain: "NesticEntryPhotoStore", code: 2,
                      userInfo: [NSLocalizedDescriptionKey: "That photo is too large to upload. Please choose another photo."])
    }

    static func save(_ sourceData: Data, for entryID: UUID) throws {
        try saveJPEG(jpegData(from: sourceData), for: entryID.uuidString)
    }

    static func save(_ sourceData: Data, forPhotoID photoID: UUID) throws {
        try saveJPEG(jpegData(from: sourceData), for: photoID.uuidString)
    }

    private static func saveJPEG(_ jpeg: Data, for identifier: String) throws {
        guard let directoryURL else {
            throw NSError(domain: "NesticEntryPhotoStore", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "The selected image could not be saved."])
        }
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        guard let fileURL = fileURL(for: identifier) else {
            throw NSError(domain: "NesticEntryPhotoStore", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "The selected image could not be saved."])
        }
        try jpeg.write(to: fileURL, options: .atomic)
        imageCache.removeObject(forKey: identifier as NSString)
    }

    static func remove(for entryID: UUID) {
        imageCache.removeObject(forKey: entryID.uuidString as NSString)
        guard let fileURL = fileURL(for: entryID.uuidString) else { return }
        try? FileManager.default.removeItem(at: fileURL)
    }

    static func remove(forPhotoID photoID: UUID) {
        imageCache.removeObject(forKey: photoID.uuidString as NSString)
        guard let fileURL = fileURL(for: photoID.uuidString) else { return }
        try? FileManager.default.removeItem(at: fileURL)
    }
}

struct NesticEntryPhotoView: View {
    @EnvironmentObject private var store: NesticStore
    let entry: NestEntry
    let size: CGFloat?
    let maxHeight: CGFloat?
    @State private var image: UIImage?

    init(entry: NestEntry, size: CGFloat? = nil, maxHeight: CGFloat? = nil) {
        self.entry = entry
        self.size = size
        self.maxHeight = maxHeight
        _image = State(initialValue: NesticEntryPhotoStore.image(for: entry.id))
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if entry.photoURL != nil {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Label("No photo", systemImage: "photo")
                    .font(.subheadline)
                    .foregroundStyle(NesticTheme.forest)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: size, height: size)
        .frame(maxWidth: size == nil ? .infinity : nil, maxHeight: maxHeight)
        .background(NesticTheme.lime.opacity(0.12), in: RoundedRectangle(cornerRadius: size == nil ? 18 : 12))
        .clipShape(RoundedRectangle(cornerRadius: size == nil ? 18 : 12))
        .task(id: entry.photoURL) {
            guard entry.photoURL != nil, image == nil else { return }
            if let data = try? await store.entryPhotoData(for: entry) {
                image = UIImage(data: data)
            }
        }
    }
}

struct SectionHeading: View {
    let title: String
    var detail: String? = nil
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.system(.title3, design: .rounded, weight: .bold))
            Spacer()
            if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
        }
    }
}

struct EmptyNestView: View {
    let symbol: String
    let title: String
    let message: String
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 32, weight: .light)).foregroundStyle(NesticTheme.forest)
                .frame(width: 76, height: 76).background(NesticTheme.lime.opacity(0.25), in: Circle())
            Text(title).font(.system(.title3, design: .rounded, weight: .bold))
            Text(message).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity).padding(.vertical, 30).padding(.horizontal, 20)
    }
}

extension View {
    func nesticCard() -> some View {
        self.padding(18).background(NesticTheme.card, in: RoundedRectangle(cornerRadius: 24))
    }
    func formStyle() -> some View {
        self.scrollContentBackground(.hidden).background(NesticTheme.paper)
    }
}

func trackerIconValue(_ tracker: NestTracker) -> String {
    tracker.symbol?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        ? tracker.symbol!
        : TrackerIconCatalog.defaultSymbol(for: tracker.name, valueType: tracker.valueType)
}

func trackerSymbol(_ tracker: NestTracker) -> String {
    let value = trackerIconValue(tracker)
    return TrackerIconCatalog.isEmoji(value) ? tracker.valueType.symbol : value
}

func trackerColorValue(_ tracker: NestTracker) -> String {
    tracker.color?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        ? tracker.color!
        : TrackerColorCatalog.defaultColor(for: tracker.name, valueType: tracker.valueType)
}

func trackerColor(_ tracker: NestTracker) -> Color {
    Color(nesticHex: trackerColorValue(tracker)) ?? NesticTheme.forest
}

extension Color {
    init?(nesticHex hex: String) {
        let clean = hex.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        guard clean.count == 6, let value = UInt64(clean, radix: 16) else { return nil }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    var nesticHex: String {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        let uiColor = UIColor(self)
        if uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
            return String(format: "#%02X%02X%02X", Int(red * 255), Int(green * 255), Int(blue * 255))
        }
        var white: CGFloat = 0
        guard uiColor.getWhite(&white, alpha: &alpha) else { return "#2E6B52" }
        red = white
        green = white
        blue = white
        return String(format: "#%02X%02X%02X", Int(red * 255), Int(green * 255), Int(blue * 255))
    }
}

struct TrackerIconView: View {
    let tracker: NestTracker
    var size: Font = .body

    var body: some View {
        let value = trackerIconValue(tracker)
        Group {
            if TrackerIconCatalog.isEmoji(value) {
                Text(value)
            } else {
                Image(systemName: value)
            }
        }
        .font(size)
        .accessibilityHidden(true)
    }
}
