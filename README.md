# pm5-power

A small always-on-top wattage display for the Concept2 BikeErg on macOS. It reads live power straight from the PM5 over Bluetooth, so you can keep an eye on your watts while watching a movie full screen.

macOS won't let you pair a PM5 in Bluetooth settings, but apps can talk to it directly. No ANT+ dongle needed.

## Mac app (PowerView)

A small floating window that stays on top of everything, including full-screen video.

```sh
cd mac
./build.sh
open PowerView.app
```

Requires macOS 14+ and the Xcode command line tools. Allow Bluetooth access the first time it launches.

- Wake the PM5 (press any button) and it connects automatically.
- Drag the window anywhere; its position is remembered.
- Right-click for size, background opacity, showing the 3s average as the main number, disconnect, and quit.
- To save the PM5's and your laptop's batteries, it disconnects after 5 minutes without pedalling and stops searching after 2 minutes. Click the window to reconnect.

## CLI (`c2power.py`)

A terminal version with big digits, 3s average, cadence, and session average/max.

```sh
uv run c2power.py          # Bluetooth LE
uv run c2power.py ant      # ANT+ FE-C / PWR via a USB ANT+ stick
uv run c2power.py demo     # simulated data
```

Options: `--name <text>` to pick a specific PM5, `--c2` to force the Concept2 protocol, `--ant-id <n>` to pair a specific ANT+ device.

## How it works

On connect, the app uses the first of these the PM5 exposes:

1. Bluetooth Cycling Power Service (`0x1818`)
2. Fitness Machine Service, Indoor Bike Data (`0x1826`)
3. Concept2's PM5 rowing service: power from *Additional Stroke Data* (`CE060036`), cadence from *Additional Status 1* (`CE060032`)

## Status

Tested on a BikeErg over Bluetooth. ANT+ support uses [openant](https://github.com/Tigge/openant) but hasn't been tested with a real stick yet. Other PM5 ergs (RowErg, SkiErg) may work through the Concept2 protocol but haven't been tried. Reports and PRs welcome.

Not affiliated with or endorsed by Concept2.

## License

MIT
