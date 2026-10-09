# pm5-power

A small always-on-top wattage display for the Concept2 BikeErg on macOS. It reads live power straight from the PM5 over Bluetooth, so you can keep an eye on your watts while watching a movie full screen.

macOS won't let you pair a PM5 in Bluetooth settings, but apps can talk to it directly. No ANT+ dongle needed.

## Install

Download `PowerView.dmg` from the [latest release](https://github.com/skyronic/pm5-power/releases/latest) (or from [pm5-power.netlify.app](https://pm5-power.netlify.app)), open it and drag PowerView into Applications. Requires macOS 14+.

The app isn't notarized (no paid Apple developer account), so macOS blocks it the first time. Open it once, click **Done** on the warning, then go to **System Settings → Privacy & Security** and click **Open Anyway**. Or from the Terminal:

```sh
xattr -dr com.apple.quarantine /Applications/PowerView.app
```

Allow Bluetooth access when it asks.

### Build from source

Requires Xcode (or the Xcode command line tools).

```sh
git clone https://github.com/skyronic/pm5-power
cd pm5-power/app
./build.sh
open build/PowerView.app
```

## Use

- Wake the PM5 (press any button) and PowerView connects automatically.
- The window mirrors the PM5: the workout clock, average power and pause come straight from the monitor, so they always match its screen, even if you reconnect or restart the app mid-workout. Start a new workout on the PM5 to reset the window.
- Below the big number: the 3-second average and cadence. The chart shows the last two minutes, with your workout average as a dashed line.
- The dot shows the connection: green while data arrives, amber when connected but silent, pulsing blue while searching, grey when disconnected, red if Bluetooth is off or not allowed.
- Drag the window anywhere; its position is remembered. It stays on top of full-screen apps.
- Right-click (or Control-click) for:
  - **Size** and **Background** darkness.
  - **Opacity** of the whole window, for watching a movie behind it. It goes back to full while the mouse is over it.
  - **Refresh**: update live, or every 2/5/10 seconds if the changing numbers are distracting.
  - Showing the 3s average as the main number, connect/disconnect, and quit. The top of the menu shows which PM5 and data source are in use, and the last Bluetooth error if any.
- To save the PM5's and your laptop's batteries, it disconnects after 5 minutes stopped, 2 minutes after you end a workout on the PM5 (so it can go to sleep), and stops searching after 2 minutes. A countdown shows in the last minute. Click the window to reconnect.

## Development

```sh
cd app
swift test                                  # protocol decoder tests
./build.sh                                  # build/PowerView.app
./package.sh                                # build/PowerView.dmg, for a release
open build/PowerView.app --args --demo      # simulated PM5, no bike needed
```

To capture a Bluetooth trace (connection events, errors, every payload) for a bug report:

```sh
/usr/bin/log stream --predicate 'subsystem == "pm5-power"' --level debug --style compact > bluetooth.log
```

On connect, the app uses the first of these the PM5 exposes:

1. Bluetooth Cycling Power Service (`0x1818`)
2. Fitness Machine Service, Indoor Bike Data (`0x1826`)
3. Concept2's PM5 rowing service: power from *Additional Stroke Data* (`CE060036`), cadence from *Additional Status 1* (`CE060032`)

It also always reads the PM5's workout clock, average power, rowing state and workout state from Concept2's *General Status* (`CE060031`) and *Additional Status 2* (`CE060033`).

## Status

Tested on a BikeErg. RowErg and SkiErg may work through the Concept2 protocol but haven't been tried. Reports and PRs welcome.

Not affiliated with or endorsed by Concept2.

## License

MIT
