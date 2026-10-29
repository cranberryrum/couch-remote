# CouchRemote

A personal iPhone app that controls my Mac (cursor, clicks, scroll, media keys) over Wi-Fi, for
watching YouTube/Netflix from bed. Personal use only: no sandbox, no App Store.

```
RemoteiPhone  ──TCP (Bonjour _couchremote._tcp)──▶  RemoteMac (menu-bar agent) ──▶ CGEvent / media keys
        └──────────── Packages/RemoteKit (wire protocol, shared) ────────────┘
```

| Path | What |
|---|---|
| `project.yml` | XcodeGen spec. The `.xcodeproj` is generated and git-ignored. |
| `Packages/RemoteKit` | Message enum, binary codec, length-prefixed framing, Bonjour/TCP settings, unit tests. |
| `RemoteMac` | macOS 14+ menu-bar app (LSUIElement, sandbox off, hardened runtime on). |
| `RemoteiPhone` | iOS 17+ SwiftUI app. Raw-touch trackpad + media bar. |
| `RemoteiPhone/Tuning.swift` | **All feel constants** (pointer sensitivity/acceleration, scroll gain, momentum, tap slop). |

Stage 1 deliberately has no pairing/encryption (see the `TODO(stage 2)` in `RemoteServer.swift`),
no text input, no now-playing, no UDP motion channel.

## Run it

### 0. Generate the project

```sh
xcodegen generate          # brew install xcodegen if missing
open CouchRemote.xcodeproj
```

Re-run `xcodegen generate` any time `project.yml` changes (or files are added/removed).

### 1. Signing

`project.yml` already sets `DEVELOPMENT_TEAM: 5PYDBJJN92` with automatic signing. If Xcode shows
"No team" for either target: select the target → **Signing & Capabilities** → pick your team. To
make that permanent, change `DEVELOPMENT_TEAM` in `project.yml` and regenerate (editing only in
Xcode is overwritten by the next `xcodegen generate`).

Keep signing consistent between rebuilds: macOS ties the Accessibility permission to the code
signature.

### 2. Run RemoteMac

1. Scheme **RemoteMac**, destination **My Mac**, ⌘R.
2. A phone icon appears in the menu bar (no Dock icon). Click it: you should see
   *Listening* and *No device connected*.
3. If macOS asks to allow **Local Network** access, click Allow.

### 3. Grant Accessibility

1. On first launch macOS shows an Accessibility prompt → **Open System Settings**
   (or use the menu's **Open Accessibility Settings**).
2. **System Settings → Privacy & Security → Accessibility** → switch **CouchRemote** on.
3. The menu flips to *Accessibility granted* within a couple of seconds. If it says granted but
   the cursor still doesn't move, quit CouchRemote from its menu and run it again.

**If a rebuild drops the permission** (the entry is on but the menu says *NOT granted*): in the
Accessibility list select **CouchRemote**, click **−** to remove it, then click **+** and add the
freshly built app (Xcode: **Product → Show Build Folder in Finder → Products/Debug/CouchRemote.app**),
and make sure the switch is on. Then relaunch the app.

### 4. Run RemoteiPhone on the phone

1. **Developer Mode** (once): iPhone **Settings → Privacy & Security → Developer Mode** → on → restart → confirm.
2. Plug the phone in, unlock it, tap **Trust This Computer**.
3. Scheme **RemoteiPhone**, destination your iPhone, ⌘R.
4. First launch only: if iOS says "Untrusted Developer", go to **Settings → General → VPN & Device
   Management → your Apple Development profile → Trust**, then launch again.
5. Allow the **Local Network** prompt. (If you tapped Don't Allow: **Settings → CouchRemote → Local
   Network** on.) The app shows *Local Network access denied* until you do.
6. Keep the Mac app running. The phone shows a green dot and the Mac's name, with the round-trip
   time at the top right. It reconnects automatically when you return to the app.

Both devices must be on the same Wi-Fi.

### Gestures

| Gesture | Action |
|---|---|
| 1-finger drag | Move cursor |
| 1-finger tap / double-tap | Left click / double click (triple-tap = triple click) |
| 2-finger tap | Right click |
| 2-finger drag | Scroll (natural direction, with momentum) |
| Bottom bar | ← seek, play/pause, → seek, volume −, volume + |

### Tweaking the feel

- Cursor too slow/fast or too jumpy: `RemoteiPhone/Tuning.swift` (`pointerSensitivity`,
  `pointerAcceleration`, `maxPointerGain`).
- Scroll backwards on the Mac: flip `invertScroll` at the top of `RemoteMac/InputInjector.swift`.
- Taps registering as drags (or vice versa): `tapSlop`, `tapMaxDuration`.

### Tests

```sh
cd Packages/RemoteKit && swift test
```

### Command-line builds

```sh
xcodebuild -project CouchRemote.xcodeproj -scheme RemoteMac -destination 'platform=macOS' build
xcodebuild -project CouchRemote.xcodeproj -scheme RemoteiPhone -destination 'generic/platform=iOS Simulator' build
```

## Wire protocol (v1)

Frame: `[u32 big-endian length][payload]`, payload `[u8 tag][fields…]`; max payload 1024 bytes.
`hello` · `move` · `button` · `click` · `scroll` · `media` · `key` · `ping`/`pong`. Details in
`Packages/RemoteKit/Sources/RemoteKit/WireFormat.swift`. `click(button, count)` carries the
click-state of that one click (1, then 2 for the second click of a double-click).
