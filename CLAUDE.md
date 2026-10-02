# pm5-power

Open-source macOS tool that shows live wattage from a Concept2 BikeErg's PM5 monitor in a small always-on-top window, so riders can watch it over full-screen video. Shared with the Concept2 community; a mini website is planned.

## Layout

- `app/` — Swift package for the Mac app (PowerView). No Xcode project.
  - `Sources/PowerProtocol/` — GATT UUIDs and pure payload decoders. No CoreBluetooth; keep it that way so it stays unit-testable.
  - `Sources/PowerView/` — the app: `Bike.swift` (CoreBluetooth), `Model.swift` (live state + `PowerSource` protocol), `Demo.swift` (simulated rider), `PowerDisplay.swift` (SwiftUI), `main.swift` (floating panel setup).
  - `Tests/PowerProtocolTests/` — Swift Testing tests for the decoders.
  - `Info.plist`, `build.sh` — the app bundle is assembled by hand from the SwiftPM binary.
- `site/` — planned website (doesn't exist yet).

## Commands (run in `app/`)

- `swift test` — decoder tests.
- `./build.sh` — universal release build → `build/PowerView.app` (ad-hoc signed).
- `open build/PowerView.app --args --demo` — run with simulated data; no bike needed.
- `pkill -f PowerView.app/Contents/MacOS` — quit (there's no Dock icon).

Don't use `swift run` for the real app: CoreBluetooth needs the `NSBluetoothAlwaysUsageDescription` from the bundle's Info.plist, and a bare binary gets killed by TCC.

## Protocol

On connect, `Bike` subscribes to the first source the PM5 exposes:

1. Cycling Power Measurement `0x2A63` (service `0x1818`). Cadence comes from crank-revolution deltas; counters wrap at 16 bits.
2. FTMS Indoor Bike Data `0x2AD2` (service `0x1826`). Field layout depends on the flags; bit 0 *clear* means speed *is* present.
3. Concept2 rowing service `CE060030-43E5-11E4-916C-0800200C9A66`: power = bytes 3–4 of `CE060036` (Additional Stroke Data); cadence = byte 5 of `CE060032` (Additional Status 1, "stroke rate").

The PM5 only advertises while its screen is awake. macOS Bluetooth settings can't pair it; apps connect directly.

## Things that matter

- **Battery.** An open BLE connection keeps the PM5 awake indefinitely and keeps the Mac's radio busy (this drained a laptop overnight once). `Bike` disconnects after 5 min without non-zero power and stops scanning after 2 min. Any new feature must not hold a connection, scan, or redraw on a timer while idle.
- **Floating over full-screen video** depends on all of: `LSUIElement` in Info.plist (accessory app), a non-activating `NSPanel`, `collectionBehavior` with `.canJoinAllSpaces` + `.fullScreenAuxiliary`, and `hidesOnDeactivate = false`. Changing any of these can break it.
- **Testing without hardware.** Only the maintainer has a bike. Verify UI with `--demo` and decoders with `swift test`; anything touching `Bike.swift` needs a real-ride check by the maintainer, so say so instead of claiming it works.
- Untested so far: ANT+ (removed for now; see git history for the old Python CLI), RowErg/SkiErg, the FTMS and Cycling Power paths against a real PM5.
- Not affiliated with Concept2; don't use their logo or branding.
