# pm5-power

A small always-on-top wattage display for the Concept2 BikeErg on macOS. It reads live power straight from the PM5 over Bluetooth, so you can keep an eye on your watts while watching a movie full screen.

macOS won't let you pair a PM5 in Bluetooth settings, but apps can talk to it directly. No ANT+ dongle needed.

## Install

Requires macOS 14+ and Xcode (or the Xcode command line tools).

```sh
git clone https://github.com/skyronic/pm5-power
cd pm5-power/app
./build.sh
open build/PowerView.app
```

Allow Bluetooth access the first time it launches. To keep it around, drag `build/PowerView.app` into Applications.

## Use

- Wake the PM5 (press any button) and PowerView connects automatically.
- Drag the window anywhere; its position is remembered. It stays on top of full-screen apps.
- Right-click for size, background opacity, showing the 3s average as the main number, disconnect, and quit.
- To save the PM5's and your laptop's batteries, it disconnects after 5 minutes without pedalling and stops searching after 2 minutes. Click the window to reconnect.

## Development

```sh
cd app
swift test                                  # protocol decoder tests
./build.sh                                  # build/PowerView.app
open build/PowerView.app --args --demo      # simulated data, no bike needed
```

On connect, the app uses the first of these the PM5 exposes:

1. Bluetooth Cycling Power Service (`0x1818`)
2. Fitness Machine Service, Indoor Bike Data (`0x1826`)
3. Concept2's PM5 rowing service: power from *Additional Stroke Data* (`CE060036`), cadence from *Additional Status 1* (`CE060032`)

## Status

Tested on a BikeErg. RowErg and SkiErg may work through the Concept2 protocol but haven't been tried. Reports and PRs welcome.

Not affiliated with or endorsed by Concept2.

## License

MIT
