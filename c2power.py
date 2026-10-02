"""Live wattage readout for a Concept2 BikeErg (PM5).

Sources:
  ble   Bluetooth LE straight to the PM5 (no extra hardware). Uses the standard
        Cycling Power / FTMS profiles if exposed, else Concept2's own PM5 service.
  ant   ANT+ PWR / FE-C via a USB ANT+ stick (Garmin/Dynastream/CooSpo/etc).
  demo  Fake data, to preview the display.
"""

import argparse
import asyncio
import math
import random
import shutil
import sys
import threading
import time
from collections import deque

# ---------------------------------------------------------------------------
# Shared state


class Stats:
    def __init__(self):
        self.lock = threading.Lock()
        self.watts = None
        self.cadence = None
        self.last_update = 0.0
        self.samples = deque()  # (t, watts) for rolling average
        self.total = 0
        self.count = 0
        self.max = 0
        self.status = "starting..."
        self.source = ""

    def update(self, watts=None, cadence=None):
        now = time.monotonic()
        with self.lock:
            if cadence is not None:
                self.cadence = cadence
            if watts is not None:
                self.watts = watts
                self.samples.append((now, watts))
                if watts > 0:
                    self.total += watts
                    self.count += 1
                self.max = max(self.max, watts)
            self.last_update = now

    def snapshot(self):
        now = time.monotonic()
        with self.lock:
            while self.samples and now - self.samples[0][0] > 3.0:
                self.samples.popleft()
            avg3 = sum(w for _, w in self.samples) / len(self.samples) if self.samples else None
            return dict(
                watts=self.watts,
                cadence=self.cadence,
                avg3=avg3,
                avg=self.total / self.count if self.count else None,
                max=self.max,
                age=now - self.last_update if self.last_update else None,
                status=self.status,
                source=self.source,
            )


STATS = Stats()

# ---------------------------------------------------------------------------
# Terminal display

FONT = {
    "0": ["█████", "█   █", "█   █", "█   █", "█████"],
    "1": ["  █  ", " ██  ", "  █  ", "  █  ", " ███ "],
    "2": ["█████", "    █", "█████", "█    ", "█████"],
    "3": ["█████", "    █", " ████", "    █", "█████"],
    "4": ["█   █", "█   █", "█████", "    █", "    █"],
    "5": ["█████", "█    ", "█████", "    █", "█████"],
    "6": ["█████", "█    ", "█████", "█   █", "█████"],
    "7": ["█████", "    █", "   █ ", "  █  ", "  █  "],
    "8": ["█████", "█   █", "█████", "█   █", "█████"],
    "9": ["█████", "█   █", "█████", "    █", "█████"],
    "-": ["     ", "     ", "█████", "     ", "     "],
    "W": ["█   █", "█   █", "█ █ █", "██ ██", "█   █"],
    " ": ["  ", "  ", "  ", "  ", "  "],
}


def big(text):
    return ["  ".join(FONT[c][row] for c in text) for row in range(5)]


def fmt(v, unit=""):
    return "--" if v is None else f"{v:.0f}{unit}"


async def display_loop():
    sys.stdout.write("\x1b[?25l")  # hide cursor
    try:
        while True:
            s = STATS.snapshot()
            stale = s["age"] is None or s["age"] > 3
            watts = "---" if stale or s["watts"] is None else f"{s['watts']:>3d}"
            cols = shutil.get_terminal_size().columns
            lines = [""]
            lines += ["  " + row for row in big(watts + " W")]
            lines += [
                "",
                f"  3s avg {fmt(s['avg3'], 'W'):>6}   cadence {fmt(s['cadence'], ' rpm'):>8}",
                f"  avg    {fmt(s['avg'], 'W'):>6}   max     {fmt(s['max'] or None, 'W'):>8}",
                "",
                f"  [{s['source']}] {s['status']}",
            ]
            out = "\x1b[H" + "\n".join(l[:cols].ljust(cols) for l in lines) + "\x1b[J"
            sys.stdout.write(out)
            sys.stdout.flush()
            await asyncio.sleep(0.25)
    finally:
        sys.stdout.write("\x1b[?25h\n")


# ---------------------------------------------------------------------------
# BLE

def uuid16(x):
    return f"0000{x:04x}-0000-1000-8000-00805f9b34fb"


def c2uuid(x):
    return f"ce06{x:04x}-43e5-11e4-916c-0800200c9a66"


CPS_SERVICE, CPS_MEASUREMENT = uuid16(0x1818), uuid16(0x2A63)
FTMS_SERVICE, FTMS_BIKE_DATA = uuid16(0x1826), uuid16(0x2AD2)
C2_ROWING_SERVICE = c2uuid(0x0030)
C2_ADDITIONAL_STATUS1 = c2uuid(0x0032)  # has stroke rate (= cadence on BikeErg)
C2_STROKE_DATA2 = c2uuid(0x0036)  # has stroke power (W)


def parse_cps(data, crank_state):
    flags = int.from_bytes(data[0:2], "little")
    watts = int.from_bytes(data[2:4], "little", signed=True)
    i = 4
    if flags & 0x01:
        i += 1  # pedal power balance
    if flags & 0x04:
        i += 2  # accumulated torque
    if flags & 0x10:
        i += 6  # wheel revolution data
    cadence = None
    if flags & 0x20:
        revs = int.from_bytes(data[i : i + 2], "little")
        evt = int.from_bytes(data[i + 2 : i + 4], "little")  # 1/1024 s
        if crank_state:
            prev_revs, prev_evt = crank_state
            dr, dt = (revs - prev_revs) & 0xFFFF, (evt - prev_evt) & 0xFFFF
            if dt:
                cadence = dr * 60 * 1024 / dt
        crank_state[:] = [revs, evt]
    return watts, cadence


def parse_ftms_bike(data):
    flags = int.from_bytes(data[0:2], "little")
    i = 2
    cadence = watts = None
    if not flags & 0x0001:
        i += 2  # instantaneous speed
    if flags & 0x0002:
        i += 2  # average speed
    if flags & 0x0004:
        cadence = int.from_bytes(data[i : i + 2], "little") / 2
        i += 2
    if flags & 0x0008:
        i += 2  # average cadence
    if flags & 0x0010:
        i += 3  # total distance
    if flags & 0x0020:
        i += 2  # resistance level
    if flags & 0x0040:
        watts = int.from_bytes(data[i : i + 2], "little", signed=True)
    return watts, cadence


def looks_like_bike(device, adv):
    name = (device.name or adv.local_name or "").upper()
    uuids = {u.lower() for u in adv.service_uuids}
    return (
        name.startswith("PM5")
        or "CONCEPT2" in name
        or bool(uuids & {CPS_SERVICE, FTMS_SERVICE, C2_ROWING_SERVICE})
    )


async def run_ble(args):
    from bleak import BleakClient, BleakScanner

    STATS.source = "BLE"
    while True:
        STATS.status = "scanning... wake the PM5 (press any button), or use Connect on the PM5 menu"
        device = await BleakScanner.find_device_by_filter(
            lambda d, a: looks_like_bike(d, a)
            and (not args.name or args.name.upper() in (d.name or a.local_name or "").upper()),
            timeout=15,
        )
        if not device:
            continue
        STATS.status = f"connecting to {device.name}..."
        disconnected = asyncio.Event()
        try:
            async with BleakClient(device, disconnected_callback=lambda _: disconnected.set()) as client:
                chars = {c.uuid.lower() for s in client.services for c in s.characteristics}
                crank_state = []

                if CPS_MEASUREMENT in chars and not args.c2:
                    mode = "Cycling Power"

                    def on_cps(_, data):
                        STATS.update(*parse_cps(data, crank_state))

                    await client.start_notify(CPS_MEASUREMENT, on_cps)
                elif FTMS_BIKE_DATA in chars and not args.c2:
                    mode = "FTMS"
                    await client.start_notify(FTMS_BIKE_DATA, lambda _, d: STATS.update(*parse_ftms_bike(d)))
                elif C2_STROKE_DATA2 in chars:
                    mode = "Concept2 PM5"
                    await client.start_notify(
                        C2_STROKE_DATA2,
                        lambda _, d: STATS.update(watts=int.from_bytes(d[3:5], "little")),
                    )
                    await client.start_notify(C2_ADDITIONAL_STATUS1, lambda _, d: STATS.update(cadence=d[5]))
                else:
                    STATS.status = f"{device.name}: no power characteristic found; retrying"
                    await asyncio.sleep(5)
                    continue

                STATS.status = f"connected to {device.name} via {mode}"
                await disconnected.wait()
                STATS.status = "disconnected; reconnecting..."
        except Exception as e:  # noqa: BLE001 - keep retrying on any BLE hiccup
            STATS.status = f"BLE error: {e}; retrying"
            await asyncio.sleep(2)


# ---------------------------------------------------------------------------
# ANT+


def ant_thread(args):
    try:
        from openant.devices import ANTPLUS_NETWORK_KEY
        from openant.devices.fitness_equipment import FitnessEquipment
        from openant.devices.power_meter import PowerMeter
        from openant.easy.node import Node
    except ImportError as e:
        STATS.status = f"openant not available: {e}"
        return

    try:
        node = Node()
    except Exception as e:  # noqa: BLE001
        STATS.status = f"no ANT+ USB stick found ({type(e).__name__}). Plug one in and retry."
        return
    node.set_network_key(0x00, ANTPLUS_NETWORK_KEY)

    # FE-C preferred (also carries cadence); PWR as a second channel. Device id 0 = wildcard pairing.
    devices = [FitnessEquipment(node, device_id=args.ant_id), PowerMeter(node, device_id=args.ant_id)]
    for dev in devices:

        def on_found(dev=dev):
            STATS.status = f"paired ANT+ {dev}"

        def on_data(page, page_name, data):
            if page_name == "standard_power":
                cad = data.cadence if data.cadence != 255 else None
                STATS.update(watts=data.instantaneous_power, cadence=cad)

        dev.on_found = on_found
        dev.on_device_data = on_data

    STATS.status = "searching for ANT+ FE-C / PWR... start pedalling"
    try:
        node.start()
    finally:
        for dev in devices:
            dev.close_channel()
        node.stop()


async def run_ant(args):
    STATS.source = "ANT+"
    threading.Thread(target=ant_thread, args=(args,), daemon=True).start()
    await asyncio.Event().wait()


# ---------------------------------------------------------------------------
# Demo


async def run_demo(_args):
    STATS.source = "demo"
    STATS.status = "simulated data"
    t = 0.0
    while True:
        base = 180 + 60 * math.sin(t / 20)
        STATS.update(watts=int(base + random.uniform(-15, 15)), cadence=85 + random.uniform(-3, 3))
        t += 0.5
        await asyncio.sleep(0.5)


# ---------------------------------------------------------------------------


async def amain(args):
    runner = {"ble": run_ble, "ant": run_ant, "demo": run_demo}[args.source]
    sys.stdout.write("\x1b[2J")
    await asyncio.gather(display_loop(), runner(args))


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("source", nargs="?", default="ble", choices=["ble", "ant", "demo"])
    p.add_argument("--name", help="BLE: only connect to a device whose name contains this (e.g. your PM5 serial)")
    p.add_argument("--c2", action="store_true", help="BLE: force the Concept2 proprietary service")
    p.add_argument("--ant-id", type=int, default=0, help="ANT+: device number to pair with (0 = any)")
    args = p.parse_args()
    try:
        asyncio.run(amain(args))
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
