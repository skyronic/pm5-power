# Plan: use the PM5 as the source of truth for time, average and pause

## Context
In the first real ride (2026-10-02, `bluetooth.log`), the window's clock and average were close to the PM5's but not the same, and the clock sometimes jumped by 2 seconds. The PM5 already sends its own elapsed time, average power and an active/stopped flag. **Rule: if the PM5 provides a value, show it as is. Only calculate our own values when it doesn't** (demo mode, or devices without the Concept2 service). The chart stays as it is.

## What the log shows
**The average drifts high.** Comparing app and PM5 at the same moments:

| When | App | PM5 |
|---|---|---|
| 5 min | 85.8 W | 84 W |
| First stop | 89 W | 87 W |
| Second stop | 87 W | 84 W |

**The app's pause and resume run about 3 s late:**

| | PM5 clock | App |
|---|---|---|
| First stop | froze 23:25:45.5 | paused 23:25:48.4 |
| First restart | restarted 23:26:19.8 | resumed 23:26:22.9 |

Pause waits for the 4 s rule, and resume waits for the first non-zero Cycling Power reading.

**The ride starts 3 s late.** The PM5 clock started at 23:18:00.3 and the app's ride at 23:18:03.5.

**Cause of the 2-second jumps.** The app's clock only advances when a Cycling Power reading arrives, by however much time actually passed. Readings arrive every 0.81–1.26 s, so the whole-second display sometimes skips one.

**The PM5 clock is clean.** In 522 of 582 packets, the PM5 elapsed time advanced by exactly 1.00 s, however late the packet arrived. The other 54 packets came while it was frozen during stops. The fraction of a second stays the same through each stretch of riding. So showing the whole seconds of the PM5's own value moves up by exactly one second per packet, with no skips and no timer. The only unevenness is when each packet arrives: about 0.1 s typical, 0.22 s in 95% of packets. That's too small to notice, so there's no need to run our own clock and re-sync it to the PM5.

**The PM5 flags pauses exactly.** Byte 9 of `CE060031` (rowing state) switches 1→0 in the same packet in which the clock freezes, and 0→1 in the same packet in which it restarts. For example, at 23:25:45.505 the elapsed time moved only 0.13 s to 464.30 and the state switched to 0. This makes it a delay-free signal for the pause icon.

### Fields used
All are little-endian. Both characteristics arrive about once a second, within milliseconds of each other.
- **`CE060033` Additional Status 2:**
  - bytes 0–2: elapsed time in 0.01 s
  - byte 3: interval count
  - bytes 4–5: average power (W)
  - bytes 6–7: total calories
- **`CE060031` General Status:**
  - bytes 0–2: elapsed time
  - bytes 3–5: distance in 0.1 m
  - byte 8: workout state
  - byte 9: rowing state (0 = stopped, 1 = active)
  - byte 18: drag factor

## Changes
1. **`PowerProtocol`**: add `struct WorkoutStatus { elapsed: TimeInterval; averageWatts: Int?; active: Bool? }`, plus `Decode.c2AdditionalStatus2(_:)` and `Decode.c2GeneralStatus(_:)`. Add tests that use payloads copied from `bluetooth.log`: a normal packet, the packet at the moment of stopping, and a frozen one.
2. **`Bike.swift`**: when the Concept2 service is present, also subscribe to `CE060031` and `CE060033`, whichever source supplies power. This is needed for when `diagnostics` is off. They feed `model.updateStatus(_:)`, while power and cadence still go through `model.update(_:)`.
3. **`Model.swift`**: add `@Published var pm5: WorkoutStatus?` with a timestamp, treated as stale after 3 s just like `live`. Publish only when the displayed values change (the whole second, the average, or the active flag), so it redraws once a second while riding and never while stopped.
4. **`PowerDisplay.swift`**, when PM5 status is fresh:
   - **clock:** whole seconds of the PM5 elapsed time, rounded down as the PM5's own screen does
   - **avg:** the PM5 average
   - **pause icon:** follows the PM5 rowing state

   When PM5 status is missing or stale, all three fall back to `Ride` as they work today. The chart keeps `Ride.trace`; its dashed average line uses the PM5 average when it has one.
5. **Resetting rides**:
   - If the PM5 elapsed time goes backwards, a new workout started on the monitor, so the app starts a new ride automatically.
   - If you press New Ride in the app mid-workout, show the app's own values until the PM5 resets. Subtracting the earlier part from the PM5's average would mean guessing how the PM5 calculates it, which breaks the "don't infer" rule. The menu item could say so ("Restart the workout on the PM5 to reset its clock").
6. **Logging**: write PM5 and app values side by side on each ride event, so later rides keep checking the match.

## Worth considering next (separate change)
The app still calculates cadence itself from Cycling Power crank counts. The PM5 sends cadence directly (`CE060032` byte 5, stroke rate), and in this log the two agreed (47.7 calculated, 47 reported). Following the same rule, PM5s could use the Concept2 service for everything: put it ahead of Cycling Power in the source priority. Power would then come per pedal stroke (`CE060036`) rather than about once a second. First compare the two power streams in `bluetooth.log`.

## Verification
- `swift test`: the new decoder tests using the logged payloads.
- `--demo`: no PM5 status, so the clock, average and pause icon still come from `Ride`. This checks the fallback path.
- Real ride (maintainer):
  - the clock and average match the PM5 screen
  - the clock never skips a second
  - the pause icon appears when the PM5 clock stops, not 3 s later
  - starting a new workout on the PM5 resets the app
  - New Ride in the app falls back to app values
