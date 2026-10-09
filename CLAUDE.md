# pm5-power

Open-source macOS tool that shows live wattage from a Concept2 BikeErg's PM5 monitor in a small always-on-top window, so riders can watch it over full-screen video. Shared with the Concept2 community.

## Layout

- `app/` — Swift package for the Mac app (PowerView). No Xcode project.
  - `Sources/PowerProtocol/` — GATT UUIDs and pure payload decoders. No CoreBluetooth; keep it that way so it stays unit-testable.
  - `Sources/PowerView/` — the app: `Bike.swift` (CoreBluetooth), `Model.swift` (live state + `PowerSource` protocol), `Demo.swift` (simulated PM5), `PowerDisplay.swift` (SwiftUI), `Menu.swift` (right-click menu, AppKit), `main.swift` (floating panel setup).
  - `Sources/RideCore/` — `Trace`: the chart's power trace, keyed by the PM5's workout clock. Pure logic, no UI.
  - `Tests/PowerProtocolTests/`, `Tests/RideCoreTests/` — Swift Testing tests.
  - `Info.plist`, `build.sh` — the app bundle is assembled by hand from the SwiftPM binary. `package.sh` wraps it in a DMG.
- `site/` — static download page, deployed to https://pm5-power.netlify.app (`netlify.toml` publishes `site/`). Download links point at `releases/latest/download/PowerView.dmg`, so keep that asset name.

## Commands (run in `app/`)

- `swift test` — decoder and ride tests.
- `./build.sh` — universal release build → `build/PowerView.app` (ad-hoc signed; not notarized, so users go through Gatekeeper's Open Anyway once).
- `./package.sh` — build plus `build/PowerView.dmg` for a GitHub release.
- `open build/PowerView.app --args --demo` — run with simulated data; no bike needed.
- `pkill -f PowerView.app/Contents/MacOS` — quit (there's no Dock icon).
- Release: bump `CFBundleShortVersionString` in Info.plist, `./package.sh`, tag `vX.Y.Z`, `gh release create vX.Y.Z app/build/PowerView.dmg`. Site: `netlify deploy --prod --no-build --dir site --site 70d390c3-95f9-4ccc-b693-66b80cd262f0` (pm5-power).
- `/usr/bin/log stream --predicate 'subsystem == "pm5-power"' --level debug --style compact > bluetooth.log` — capture Bluetooth events, errors, raw payloads and ride events (zsh has a `log` builtin, hence the full path). Start it before connecting; debug messages aren't kept otherwise.

Don't use `swift run` for the real app: CoreBluetooth needs the `NSBluetoothAlwaysUsageDescription` from the bundle's Info.plist, and a bare binary gets killed by TCC.

## Protocol

On connect, `Bike` subscribes to the first source the PM5 exposes:

1. Cycling Power Measurement `0x2A63` (service `0x1818`). Cadence comes from crank-revolution deltas; counters wrap at 16 bits.
2. FTMS Indoor Bike Data `0x2AD2` (service `0x1826`). Field layout depends on the flags; bit 0 *clear* means speed *is* present.
3. Concept2 rowing service `CE060030-43E5-11E4-916C-0800200C9A66`: power = bytes 3–4 of `CE060036` (Additional Stroke Data); cadence = byte 5 of `CE060032` (Additional Status 1, "stroke rate").

Whichever source supplies power, it also subscribes to Concept2 General Status `CE060031` (bytes 0–2 elapsed in 0.01 s; byte 8 workout state, 1–9 = in a workout; byte 9 rowing state, 0 = stopped) and Additional Status 2 `CE060033` (bytes 4–5 workout average watts). Right after connecting, `CE060033` sends a few packets with the average zeroed; they're ignored.

The PM5 only advertises while its screen is awake. macOS Bluetooth settings can't pair it; apps connect directly.

## Things that matter

- **Mirror the PM5.** The clock, average, stopped state and workout start/end are whatever the PM5 last sent (`PM5State` in PowerProtocol, merged from `CE060031`/`CE060033`); the app calculates none of them. Restarting the app or reconnecting mid-workout shows the same values. The only app-side figures are the 3 s average and the chart trace. `--demo` sends the same packets as a PM5, so it exercises the real display path.
- **Battery.** An open BLE connection keeps the PM5 awake indefinitely and keeps the Mac's radio busy (this drained a laptop overnight once). `Bike` disconnects after 5 min stopped, 2 min after the PM5 leaves a workout (so it can sleep), and stops scanning after 2 min. "Stopped" is the PM5's rowing state, not raw watts: Cycling Power sends a stray non-zero reading when a workout is ended. Any new feature must not hold a connection, scan, or redraw on a timer while idle.
- **Floating over full-screen video** depends on all of: `LSUIElement` in Info.plist (accessory app), a non-activating `NSPanel`, `collectionBehavior` with `.canJoinAllSpaces` + `.fullScreenAuxiliary`, and `hidesOnDeactivate = false`. Changing any of these can break it.
- **Testing without hardware.** Only the maintainer has a bike. Verify UI with `--demo` and decoders with `swift test`; anything touching `Bike.swift` needs a real-ride check by the maintainer, so say so instead of claiming it works.
- Untested so far: ANT+ (removed for now; see git history for the old Python CLI), RowErg/SkiErg, the FTMS and Cycling Power paths against a real PM5.
- **Diagnostics are off in releases.** Turn `Bike.diagnostics` on locally while dogfooding: it discovers every service, reads everything readable, subscribes to every notifying characteristic and logs every payload. Only the chosen source feeds the model. It costs radio time while connected, so it must be `false` in anything published.
- Not affiliated with Concept2; don't use their logo or branding.
