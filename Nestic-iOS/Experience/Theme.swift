import SwiftUI

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
    var size: CGFloat = 52
    var body: some View {
        Text(emoji).font(.system(size: size * 0.48))
            .frame(width: size, height: size)
            .background(NesticTheme.lime.opacity(0.24), in: RoundedRectangle(cornerRadius: size * 0.32))
            .accessibilityHidden(true)
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

func trackerSymbol(_ tracker: NestTracker) -> String {
    let name = tracker.name.lowercased()
    if name.contains("pee") || name.contains("water") { return "drop.fill" }
    if name.contains("poop") { return "leaf.fill" }
    if name.contains("food") || name.contains("fed") || name.contains("grocer") { return "fork.knife" }
    if name.contains("walk") { return "figure.walk" }
    if name.contains("sleep") { return "moon.fill" }
    if name.contains("clean") { return "sparkles" }
    return tracker.valueType.symbol
}
