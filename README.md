# Nestic for iOS

A native SwiftUI app for sharing everyday updates with your family or group. The interface uses a warm paper background, forest green controls, and lime highlights. The original nest mark and app icon live in the [brand assets](../Branding/README.md).

## Open and run

1. Open **Xcode-beta** at `/Applications/Xcode-beta.app` on this Mac.
2. Open `Nestic-iOS.xcodeproj` in this directory.
3. Select the **Nestic-iOS** scheme in the toolbar.
4. Select an iPhone simulator. **iPhone 17 Pro** with the installed iOS 26 runtime is a suitable test device.
5. Choose **Product → Run** or press **⌘R**.

The deployment target is iOS 17.0. A simulator run does not require an Apple Developer membership or device signing.

If Terminal commands report that a simulator SDK is unavailable, select the full Xcode installation for that terminal:

```sh
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
xcodebuild -version
xcrun simctl list devices available
```

Change the path if Xcode is installed under a different name. You do not need to change the Mac’s global developer-directory setting.

## Explore without a server

On the welcome screen, tap **Explore a sample nest**. This creates a local sample household with subjects, trackers, and activity to explore.

Try this sequence:

1. Open Milo and log a Pee or Poop update.
2. Add a note or change the event time when needed.
3. Check the activity feed for the new update.
4. Add another subject and create a tracker of your own.
5. Close and reopen the app to confirm your sample changes remain.

Sample data stays on this installation. It is isolated from account data and is not uploaded when you sign in. Use the sample-mode exit control in settings to return to the welcome screen.

For repeatable development runs, add launch arguments in **Product → Scheme → Edit Scheme → Run → Arguments**:

| Argument | Effect |
| --- | --- |
| `--demo` | Opens the local sample nest automatically |
| `--demo --reset-demo` | Opens a fresh sample nest on each launch; discards previous sample edits |

Remove these arguments to test normal account onboarding.

## Connect to the server

Start the server using the [server README](../NesticServer/README.md). The short local sequence, run from the repository root, is:

```sh
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
cd NesticServer
docker compose up -d db
swift run NesticServer migrate --yes
swift run NesticServer serve
```

Wait until the database is healthy before migrations. Leave the server running during testing.

On the welcome screen, tap **Server settings**. The authentication sheet also has **Connection settings**, so you can configure the connection before you have an account.

| Where the app runs | Server address |
| --- | --- |
| iPhone simulator on your Mac | `http://127.0.0.1:8080` |
| Physical iPhone on the Mac’s Wi-Fi | Your Mac’s LAN IP, for example `http://192.168.1.20:8080` |
| Any device using a hosted server | Your Railway HTTPS URL, or `https://api.nestic-app.com` after configuring it |

Use the server origin without adding an `/api` path. Changing servers signs you out so one server’s account session cannot be reused against another.

For a local iPhone connection, open **System Settings → Wi-Fi → Details → TCP/IP** on your Mac to find its current IP address. The Mac and iPhone must be able to reach one another on the network. Allow the app’s local-network permission and any Mac firewall prompt for the server. If the address changes, update Connection settings.

## Create your real nest

1. Tap **Create your nest** and register with your name, email, and a password of at least eight characters.
2. Create a nest, such as “Our home.”
3. Add a subject, such as your dog. Choose its kind and an emoji.
4. Choose suggested trackers or make your own. Bathroom updates can use **Just an update**; food can use **Number** with “cups”; notes can use **Text**; a completed check can use **Yes or no**.
5. Tap the plus button beside a tracker to quick-log it. The timestamp is captured at the moment you press plus, and you can adjust it before saving if needed. Long-press a tracker or use its ellipsis menu to edit or delete it; deleting a tracker also removes its history.
6. Log an update. The feed shows the subject, tracker, time, value when applicable, and author.
7. Add household members through the nest’s member controls. They must first register on the same server. Use the email they registered with.

For every tracked subject, Nestic includes a structured **Incident** event type. Incident events capture the type, location, resolution status, and context. They appear in the normal activity history and can be edited or removed with the same permissions as other updates. Existing subjects can enable the event type from their detail screen; a nest owner or admin needs to do the one-time setup.

Every tracker update can also be marked **Was this an accident?** and can be included or excluded from on-device predictive models. These flags stay attached to the individual event, so an accident remains in shared history without necessarily influencing forecasts.

## Insights, bathroom forecasts, and widgets

The **Insights** tab adds Daily Scoop-style history without making Nestic pet-only. It has Today, 7-day, and 30-day ranges, per-tracker charts, totals, and a compact daily history grid for any subject.

**Activity forecast** is a Pro feature. The model is learned privately on-device from intervals between the events the user selects, with a small ridge-regression model. The resulting forecast is published to the nest's shared forecast store, so every member and device sees the same latest result; the private learning ledger and feedback remain on the originating device. Open **Tune forecast** to choose which trackers to predict and which data points (such as Food, Water, Walk, Sleep, chores, symptoms, or custom trackers) become model inputs. The app needs at least two updates for a baseline and becomes more useful after three or more intervals. The widget independently forecasts each of its two selected metrics and shows whichever is predicted next. It is a pattern estimate, not medical, veterinary, or other professional advice.

The project now includes a configurable WidgetKit target with small, medium, large, and Lock Screen layouts. Long-press a widget, choose **Edit Widget**, select any person or thing in the nest, then choose two of that subject’s metrics. The medium layout shows those metrics and quick-log buttons; the large layout adds a daily 24-hour timeline with a marker for every update. Lock Screen widgets include inline, circular, and rectangular variants for quick metric counts. The app and widget share data through the `group.com.bausch.Nestic-iOS` App Group; replace that identifier in both entitlements and `NesticWidgetBridge.swift` if you change the bundle/team setup.

Before shipping subscriptions, create an auto-renewable App Store Connect product with ID `com.nestic.predictions.monthly`, set its price to $0.99/month, and enable Family Sharing. StoreKit access is already wired to that product; the sample nest has a session-only preview button while the product is being configured.

Nestic keeps core family tracking free: members, subjects, trackers, updates, and the first nest are not limited. Nestic Pro — Family unlocks activity forecasts, 30-day trends, predictive widget output, and additional nests. The iOS app reads the Apple entitlement locally; web Pro access and server-enforced nest limits still require Apple transaction sync on the API.

Pro also includes routines. A routine belongs to one subject and saves a set of tracker values—for example, a food amount plus two medication updates—so a family member can tap “Log Morning feeding” once. Routine definitions are shared with the nest, and the server records all of their entries atomically.

A tracker belongs to its nest and can be used for subjects in that nest. Creating a tracker on a subject automatically adds it to that subject’s quick actions. Multiple nests let you keep different groups separate.

## Run on your iPhone

1. Connect the iPhone to your Mac, trust the computer, and enable Developer Mode on the iPhone if prompted.
2. In Xcode, select the app target and open **Signing & Capabilities**.
3. Select your own Apple development team and enable automatic signing. If the bundle identifier is unavailable to your team, change it to a unique identifier you own.
4. Select the connected iPhone as the run destination and press **⌘R**.
5. Use the sample nest, or set your Mac’s LAN server address as described above.

The repository may contain the original developer’s team identifier; replace it with your team for device builds. Keep credentials and signing material outside the repository.

## Apple Watch and Siri

The project includes a single-target **NesticWatch** app. After installing the iPhone app on a paired device, the watch receives the selected nest’s subjects and trackers through WatchConnectivity. The watch can record directly against the server when it has connectivity; if that request fails, it keeps the event locally and transfers it to the iPhone when the connection returns.

App Shortcuts are also available for Siri. After the first install, say **“Hey Siri, record Pee for Milo in Nestic”** and choose the suggested tracker/entity target if Siri asks. A number tracker without a spoken amount records one unit; text trackers use “Recorded by Siri”; structured trackers should be entered in the watch app or iPhone. The watch app and shortcut use the same server API and permissions as the iPhone app.

## Automated tests

The iPhone simulator build, 9 core tests, and 3 UI tests passed. The backend and real two-account live-sync check also passed; see the [verification record](../VERIFICATION.md).

From the repository root:

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcodebuild test \
  -project Nestic-iOS/Nestic-iOS.xcodeproj \
  -scheme Nestic-iOS \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.0' \
  -derivedDataPath /tmp/nestic-derived \
  CODE_SIGNING_ALLOWED=NO
```

Alternatively, press **⌘U** in Xcode. Choose an installed simulator if the named destination is unavailable. Unit and UI tests are in `Nestic-iOSTests/` and `Nestic-iOSUITests/`; the server has its own suite. UI tests use a reset sample nest so they do not depend on your real account or a running backend.

A real two-account WebSocket check is also included. With the local API running, execute `Nestic-iOS/Scripts/check-live-sync.sh` from the repository root. It verifies registration, shared starter trackers, automatic delivery of logs/deletions/new trackers, boolean values, and nest isolation. It creates uniquely named test accounts and nests on the local database and prints their suffix for inspection or cleanup. It does not send email.

Local HTTP is limited to loopback and private network addresses in `Configuration/Info.plist`; hosted URLs should use HTTPS. The local-network exceptions follow [Apple’s ATS documentation](https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity/nsallowslocalnetworking).

## Test shared updates with two devices

Use two simulators, a simulator and an iPhone, or two iPhones. Both must use the same running server.

1. On device A, create account A and a nest. Add a dog with Pee and Poop trackers.
2. On device B, create account B on the same server.
3. On device A, add account B’s registered email to the nest.
4. On device B, refresh the nest list, or sign out and back in if needed, and select the shared nest.
5. Keep both apps in the foreground. Log a Pee event on A. Confirm B’s activity feed updates without relaunching the app, with the correct author and time.
6. Log a Poop event with a note on B. Confirm A receives it and the subject’s latest activity changes.
7. Switch away from and back to the app, then confirm the recent activity is refreshed.
8. Create a separate nest and switch between them. Confirm each shows only its own subjects and activity.

Do this test against a deployed HTTPS server as well before inviting external testers. Local sample mode cannot exercise shared updates.

## Connection and history behavior

Connected accounts retain their last fetched data on-device, scoped to the account and server. You can view that cached content when disconnected. Creating subjects, trackers, members, or iPhone-side shared updates requires the server; the Apple Watch has a separate queue for tracker logs made while the phone or server is unavailable.

While the app is open, its WebSocket connection receives changes for the selected nest. It reconnects after a dropped connection with a delay that grows from two to thirty seconds and fetches the current snapshot on subscription. Returning to the foreground or pulling to refresh also refreshes data. There is no periodic polling fallback, push notification service, or guaranteed background synchronization.

The current activity view loads the latest **200 updates** for the selected nest. Older entries remain on the server, but the app does not yet provide history pagination.

## Where to make changes

- `Nestic-iOS/Experience/`: SwiftUI screens, shared components, and the theme.
- `Nestic-iOS/AppCore/`: `NesticStore`, API requests, live connection, models, and local persistence.
- `Nestic-iOS/Assets.xcassets/`: app icon and accent color.
- `../Branding/`: editable logo sources and icon generation script.
- `LegacyPrototype/`: the archived early implementation. It is outside the active app source directory; make app changes in `Nestic-iOS/`.

The app’s current data flow runs through `NesticStore`. Add a model/API operation in AppCore when needed, then call the store from a SwiftUI screen. Keep shared account data on the server and preserve the separate sample experience when adding features.

## Hosting and release

Railway runs the Vapor backend and PostgreSQL. It does not host the iOS application binary. See the [server deployment guide](../NesticServer/README.md) for setup, then save the deployed HTTPS origin in Connection settings.

Use `api.nestic-app.com` for the backend when you connect the domain. `www.nestic-app.com` can later host your public website. Neither deployment nor DNS changes are performed by building this app.

The app reads the bundled `NesticServerURL` value at launch. Debug, Release, and TestFlight builds default to `https://api.nestic-app.com`. In a Debug build, use the Connection button on the welcome screen to switch to `http://127.0.0.1:8080` when the local API is running, or to your Mac’s LAN address for a physical device. Release/TestFlight builds do not show server configuration to testers. Change the Release `NESTIC_SERVER_URL` build setting in the project to the actual deployed HTTPS API before archiving. Manual server overrides remain available only in Debug builds.

### TestFlight tester flow

TestFlight installation and Nestic account creation are separate:

1. Send a tester the TestFlight email invitation or public link. They install Apple’s TestFlight app, accept the invitation, and install Nestic.
2. They open Nestic and choose **Create your nest** or **I already have an account**. Registration uses a Nestic email/password account on the hosted API; it does not require App Store Connect access.
3. The first person creates a nest. The second person creates their own Nestic account using the same API, then the owner adds that account’s email under **Your nest → Add a nest member**.
4. The added person reopens the app or pulls to refresh, selects the shared nest, and can see the shared activity and live foreground updates.

The current beta adds existing accounts directly and does not send invitation, verification, or password-reset email. Keep the API on a public HTTPS origin for TestFlight; local `127.0.0.1` and LAN addresses are only for development.

For external iOS testers, configure signing and an App Store Connect app, archive a release build in Xcode, and distribute through TestFlight. Before public release, complete account recovery, email verification, privacy/support pages, and release review work. Foreground WebSocket updates do not provide push notifications or guaranteed background updates. Adding a member currently adds an existing account; it does not send an email invitation.

### Widget updates and two subjects

Add **Nestic · Two subjects** from the iOS widget gallery (medium or large), then edit the widget to choose two distinct subjects and two trackers for each. Simple trackers log directly through App Intents; trackers requiring values, photos, or structured details open the existing logging flow. A refresh control fetches current server data without opening the app.

Both widget types request a timeline reload after five minutes and include a midnight snapshot to reset daily counts. Local mutations, foreground/server updates, and widget actions request immediate reloads. Background App Refresh requests a server fetch after fifteen minutes, reschedules itself, and preserves cached data on failure. iOS controls actual execution and widget reload budgets; neither interval is guaranteed. Background App Refresh must be enabled for unattended server fetches.

Widget action pickers also include saved routines labeled **Routine:**. Choose a routine in either slot of Nestic care or any of the four slots in Two subjects. Tapping logs the entire saved routine with its configured values, including every subject in a multi-subject routine. Routines retain their existing Nestic Pro requirement. Routine labels show how many trackers and subjects will be logged; they do not display a fabricated daily completion count. Small home-screen widgets also support tapping their routine rows.

The Two subjects widget now shows each selected tracker's last recorded time and its own upcoming forecast (with Pro access). Medium displays the first selected action for each subject to keep these details readable; large displays both actions for each subject. Routine actions keep their saved scope summary rather than implying a tracker forecast or completion time.

## Tutorial and onboarding

The first signed-in visit to Home automatically opens a skippable getting-started guide, including accounts with existing nests. Viewing it is remembered locally on the device in UserDefaults (`nestic.tutorial.viewed.v1`); skipping or swiping it away also counts, so later launches and sign-ins do not automatically show it again. It can also be opened from **How Nestic works** on Welcome and **Your nest → Help & legal → Getting started**. Nine topics explain the app’s capabilities with explicit Free/Pro labels and a topic picker. Home’s setup checklist opens existing setup screens and disappears when a tracker has been recorded. Checklist dismissal is remembered per account and server on the device. The guide does not create records or enable Pro.

The focused UI checks are `testFirstSignedInLaunchShowsTutorialAndRemembersViewingLocally` and `testTutorialExplainsFreeHealthUpdatesAndProFeaturesAndCanReopen` in the iOS UI test suite. Debug launches accept `--reset-tutorial` to clear the local viewed flag; normal sample mode does not automatically present the guide.
