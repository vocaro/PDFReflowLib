"""Bounded host-pressure helper for issue #244's macOS measurement.

Run only when no other conversion measurements use the host. The process retains touched
anonymous pages, adding one chunk when pressure falls to normal, and exits on critical
pressure or its allocation cap. Stop it with SIGTERM after the pressured corpus lane.
Its JSON-lines stdout records every allocation and pressure reading.
"""
import argparse
import ctypes
import json
import mmap
import signal
import subprocess
import sys
import time


def pressure_reader():
    library = ctypes.CDLL("/usr/lib/libSystem.B.dylib")
    library.sysctlbyname.argtypes = [ctypes.c_char_p, ctypes.c_void_p,
                                     ctypes.POINTER(ctypes.c_size_t), ctypes.c_void_p, ctypes.c_size_t]
    library.sysctlbyname.restype = ctypes.c_int

    def read():
        value = ctypes.c_int()
        size = ctypes.c_size_t(ctypes.sizeof(value))
        if library.sysctlbyname(b"kern.memorystatus_vm_pressure_level", ctypes.byref(value),
                                ctypes.byref(size), None, 0) != 0:
            raise OSError("Cannot read host memory pressure")
        return value.value
    return read


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--max-gib", type=float,
                        help="maximum touched allocation (default: smaller of 12 GiB or one third of RAM)")
    parser.add_argument("--step-mib", type=int, default=256,
                        help="allocation increment (default 256 MiB)")
    args = parser.parse_args()
    if sys.platform != "darwin" or not 16 <= args.step_mib <= 512:
        parser.error("requires macOS and 16–512 MiB increments")
    physical = int(subprocess.check_output(["sysctl", "-n", "hw.memsize"], text=True).strip())
    max_gib = args.max_gib if args.max_gib is not None else min(12, physical / (3 * 1024**3))
    if max_gib <= 0 or max_gib * 1024**3 > physical * 0.4:
        parser.error("allocation cap must be positive and at most 40% of physical RAM")
    read = pressure_reader()
    if read() != 1:
        raise SystemExit("Host is not quiet before induced pressure")
    cap = int(max_gib * 1024 * 1024 * 1024)
    step = args.step_mib * 1024 * 1024
    chunks = []
    running = True

    def stop(_signum, _frame):
        nonlocal running
        running = False

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)

    def note(level, event):
        print(json.dumps({"epochSeconds": time.time(), "event": event,
                          "pressureLevel": level, "allocatedBytes": len(chunks) * step}), flush=True)

    normal_since = None
    while running:
        level = read()
        if level >= 4:
            note(level, "critical: stop")
            return 4
        if level == 1:
            if normal_since is None:
                normal_since = time.monotonic()
            if time.monotonic() - normal_since >= 2:
                if (len(chunks) + 1) * step > cap:
                    note(level, "cap reached without sustained warning: stop")
                    return 2
                chunk = mmap.mmap(-1, step)
                for offset in range(0, step, mmap.PAGESIZE):
                    chunk[offset] = 1
                chunks.append(chunk)
                note(read(), "allocated")
                normal_since = None
        else:
            normal_since = None
            note(level, "holding")
        time.sleep(1)
    note(read(), "stopped")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
