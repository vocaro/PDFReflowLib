#!/usr/bin/env python3
"""Run an opt-in real-PDF baseline, checking source identity before invoking the converter.

No downloads; large input/output files stay outside the committed fixture bundle.
A successful run measures conversion and package conformance, not content fidelity.
"""
import argparse
import ctypes
import json
import math
import os
from pathlib import Path
import platform
import re
import signal
import subprocess
import sys
import time
import uuid

import check_epubs
from conversion_provenance import probe_errors
from pdfreflow_tools.converter import run_epubcheck
from pdfreflow_tools.corpus import ROOT, digest, find_case, manifest_cases, matches_identity

# Exit status for a run whose every other gate passed but whose memory ceiling host memory
# pressure left unmeasurable. Distinct from 1 so that a loaded host is not read as a regression.
UNMEASURED_MEMORY_EXIT = 3


class MemorySample(ctypes.Structure):
    # rusage_info_v4, from the Apple SDK's sys/resource.h.
    _fields_ = [("uuid", ctypes.c_uint8 * 16)] + [
        (name, ctypes.c_uint64) for name in (
            "user", "system", "idleWakeups", "interruptWakeups", "pageins", "wired",
            "resident", "footprint", "started", "exited", "childUser", "childSystem",
            "childIdleWakeups", "childInterruptWakeups", "childPageins", "childElapsed",
            "diskReads", "diskWrites", "defaultQoS", "maintenanceQoS", "backgroundQoS",
            "utilityQoS", "legacyQoS", "userInitiatedQoS", "userInteractiveQoS",
            "billedSystem", "servicedSystem", "logicalWrites", "lifetimeMaxFootprint",
            "instructions", "cycles", "billedEnergy", "servicedEnergy",
            "intervalMaxFootprint", "runnableTime")]


def memory_reader():
    if sys.platform != "darwin":
        return lambda pid: None
    library = ctypes.CDLL("/usr/lib/libproc.dylib")
    library.proc_pid_rusage.argtypes = [ctypes.c_int, ctypes.c_int, ctypes.c_void_p]
    library.proc_pid_rusage.restype = ctypes.c_int

    def read(pid):
        sample = MemorySample()
        if library.proc_pid_rusage(pid, 4, ctypes.byref(sample)) != 0:
            return None
        # lifetimeMaxFootprint is the kernel's own high-water mark of the footprint ledger, so
        # unlike the sampled values it cannot miss a spike between two samples. It is recorded as
        # corroborating evidence, not gated on: the ceilings are peak RSS ceilings.
        return {"residentBytes": sample.resident, "physicalFootprintBytes": sample.footprint,
                "lifetimeMaxPhysicalFootprintBytes": sample.lifetimeMaxFootprint}
    return read


def pressure_reader():
    """Host memory pressure: 1 normal, 2 warning, 4 critical (kern.memorystatus_vm_pressure_level)."""
    if sys.platform != "darwin":
        return lambda: None
    library = ctypes.CDLL("/usr/lib/libSystem.B.dylib")
    library.sysctlbyname.argtypes = [ctypes.c_char_p, ctypes.c_void_p, ctypes.POINTER(ctypes.c_size_t),
                                     ctypes.c_void_p, ctypes.c_size_t]
    library.sysctlbyname.restype = ctypes.c_int

    def read():
        value = ctypes.c_int(0)
        size = ctypes.c_size_t(ctypes.sizeof(value))
        if library.sysctlbyname(b"kern.memorystatus_vm_pressure_level", ctypes.byref(value),
                                ctypes.byref(size), None, 0) != 0:
            return None
        return value.value
    return read


def settle(read_pressure, seconds):
    """Wait for host memory pressure to fall back to normal before a measured conversion.

    Returns the seconds spent waiting, or None when the host never settled. Zero seconds checks
    once and never waits.
    """
    start = time.monotonic()
    while True:
        if read_pressure() in (None, 1):
            return time.monotonic() - start
        waited = time.monotonic() - start
        if waited >= seconds:
            return None
        time.sleep(min(0.5, seconds - waited))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--case", required=True)
    parser.add_argument("--pdf", type=Path, required=True)
    parser.add_argument("--converter", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True, help="new directory")
    parser.add_argument("--epubcheck", type=Path)
    parser.add_argument("--execution-context", help="supplemental caller-declared launch label, e.g. host-terminal or codex-sandbox; not capability evidence")
    parser.add_argument("--environment-probe", type=Path,
                        help="compiled probe-raster-environment; executes in this launch context before conversion")
    parser.add_argument("--timeout", type=float, default=1800)
    parser.add_argument("--max-peak-rss-mib", type=float, help="override the case memory ceiling; fails after conversion when exceeded")
    parser.add_argument("--memory-attempts", type=int, default=2,
                        help="conversions to spend obtaining a peak RSS the host did not spoil (default 2)")
    parser.add_argument("--settle-seconds", type=float, default=60,
                        help="seconds to wait for host memory pressure to return to normal before each conversion (default 60; 0 checks once and never waits)")
    parser.add_argument("--concurrent-evaluations", type=int, default=1,
                        help="evaluations the caller runs at once on this host; recorded, not enforced")
    args = parser.parse_args()
    case = find_case(manifest_cases(ROOT), args.case)
    if case is None:
        parser.error("unknown corpus case")
    if not math.isfinite(args.timeout) or args.timeout <= 0:
        parser.error("timeout must be positive")
    memory_limit = args.max_peak_rss_mib
    if memory_limit is None:
        memory_limit = case.get("memoryBudget", {}).get("maxPeakRSSMiB")
    if memory_limit is not None and (not math.isfinite(memory_limit) or memory_limit <= 0):
        parser.error("memory ceiling must be finite and positive")
    if args.concurrent_evaluations < 1:
        parser.error("concurrent evaluations must be positive")
    if args.memory_attempts < 1:
        parser.error("memory attempts must be positive")
    if not math.isfinite(args.settle_seconds) or args.settle_seconds < 0:
        parser.error("settle seconds must be finite and not negative")
    if not matches_identity(args.pdf, case):
        parser.error("PDF identity differs from the pinned corpus case")
    converter = args.converter.resolve(strict=True)
    probe = args.environment_probe.resolve(strict=True) if args.environment_probe else None
    args.output.mkdir(parents=True, exist_ok=False)
    output = args.output / (case["id"] + ".epub")
    receipt = {
        "provenanceSchemaVersion": 1,
        "runID": str(uuid.uuid4()),
        "case": case,
        "converterSHA256": digest(converter),
        "system": platform.platform(),
        "systemBuild": platform.version(),
        "machine": platform.machine(),
        "executionContext": args.execution_context,
        "concurrentEvaluations": args.concurrent_evaluations,
        "options": "library defaults",
        "qualifiedForFidelity": False,
    }
    if probe:
        probe_result = args.output / 'environment-probe.json'
        command = [str(probe), str(args.pdf.resolve()), '1', args.execution_context or 'unspecified',
                   receipt['runID'], str(probe_result.resolve())]
        capture = {'executableSHA256': digest(probe), 'command': command}
        receipt['environmentProbeCapture'] = capture
        try:
            with (args.output / 'environment-probe.log').open('w') as log:
                run = subprocess.run(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT,
                                     timeout=args.timeout)
            capture['exitCode'] = run.returncode
            if run.returncode != 0:
                raise ValueError('probe process failed')
            capture['resultSHA256'] = digest(probe_result)
            receipt['environmentProbe'] = json.loads(probe_result.read_text())
            if digest(probe) != capture['executableSHA256']:
                raise ValueError('probe executable changed during capture')
        except (OSError, ValueError, subprocess.TimeoutExpired) as error:
            capture['error'] = str(error)
        receipt['environmentProbeCheck'] = {'errors': probe_errors(receipt)}
        receipt['environmentProbeCheck']['passed'] = not receipt['environmentProbeCheck']['errors']
    report_path = args.output / "conversion-report.json"
    progress_path = args.output / "progress.log"
    read_memory = memory_reader()
    read_pressure = pressure_reader()
    limit_bytes = int(memory_limit * 1024 * 1024) if memory_limit is not None else None

    def convert(attempt):
        """One converter run, returning that run's measurements. A later attempt replaces the
        output, report and progress log of the one before it; every attempt's samples are kept."""
        if output.exists():
            output.unlink()
        started = time.monotonic()
        measurement = {"attempt": attempt}
        samples = []
        pressures = []
        with report_path.open("w") as report, progress_path.open("w") as log:
            process = subprocess.Popen([str(converter), str(args.pdf.resolve()), str(output.resolve())],
                                       stdout=report, stderr=log)
            stage = "starting"
            pending = ""
            with progress_path.open() as progress:
                while True:
                    waited_pid, status, usage = os.wait4(process.pid, os.WNOHANG)
                    if waited_pid:
                        process.returncode = os.waitstatus_to_exitcode(status)
                        break
                    pending += progress.read()
                    lines = pending.split("\n")
                    pending = lines.pop()
                    for line in lines:
                        if re.match(r"^\d+% ", line):
                            stage = line
                    sample = read_memory(process.pid)
                    # Only pressure while this converter is running can have compressed this
                    # converter's pages, so only these readings bear on this measurement.
                    pressures.append(read_pressure())
                    if sample is not None:
                        samples.append({"seconds": time.monotonic() - started, "progress": stage,
                                        "memoryPressureLevel": pressures[-1], **sample})
                    if time.monotonic() - started > args.timeout:
                        os.kill(process.pid, signal.SIGKILL)
                        measurement["timedOut"] = True
                        _, status, usage = os.wait4(process.pid, 0)
                        process.returncode = os.waitstatus_to_exitcode(status)
                        break
                    time.sleep(0.1)
            measurement["conversionExitCode"] = process.wait()
        measurement["conversionSeconds"] = time.monotonic() - started
        measurement["converterPeakRSSBytes"] = usage.ru_maxrss * (1 if sys.platform == "darwin" else 1024)
        measurement["converterCPUSeconds"] = usage.ru_utime + usage.ru_stime
        if samples:
            measurement["sampledPeakPhysicalFootprintBytes"] = max(s["physicalFootprintBytes"] for s in samples)
            footprints = [s["lifetimeMaxPhysicalFootprintBytes"] for s in samples
                          if "lifetimeMaxPhysicalFootprintBytes" in s]
            if footprints:
                measurement["converterLifetimeMaxPhysicalFootprintBytes"] = max(footprints)
        levels = [level for level in pressures if level is not None]
        measurement["peakMemoryPressureLevel"] = max(levels) if levels else None
        measurement["samples"] = samples
        return measurement

    def spoiled(measurement):
        """Whether host memory pressure spoiled this measurement rather than the library failing.

        macOS compresses and pages out resident memory under pressure, which can only lower a
        peak RSS, never raise it. A peak taken under pressure that came in under the ceiling
        therefore neither passes it nor fails it: it does not measure it.
        """
        return (limit_bytes is not None and measurement["conversionExitCode"] == 0
                and not measurement.get("timedOut")
                and measurement["converterPeakRSSBytes"] <= limit_bytes
                and measurement["peakMemoryPressureLevel"] not in (None, 1))

    def settle_if_gated():
        """Nothing is measured against a ceiling here without one, so wait for the host only when
        there is a ceiling to measure against."""
        return settle(read_pressure, args.settle_seconds) if limit_bytes is not None else None

    attempts = []
    waited = settle_if_gated()
    while True:
        measurement = convert(len(attempts) + 1)
        measurement["settledSecondsBeforeLaunch"] = waited
        attempts.append(measurement)
        if not spoiled(measurement) or len(attempts) >= args.memory_attempts:
            break
        # Another conversion costs minutes and would be spoiled the same way, so spend one only
        # once the host is quiet again.
        waited = settle_if_gated()
        if waited is None:
            break
    for earlier in attempts[:-1]:
        (args.output / ("memory-samples-%d.json" % earlier["attempt"])).write_text(
            json.dumps(earlier.pop("samples"), indent=2) + "\n")
    (args.output / "memory-samples.json").write_text(
        json.dumps(attempts[-1].pop("samples"), indent=2) + "\n")
    receipt.update({key: value for key, value in attempts[-1].items() if key != "attempt"})
    if len(attempts) > 1:
        receipt["conversionAttempts"] = attempts
    receipt["measurementScope"] = "One process run; RSS excludes separate Apple services. Timing excludes validation and includes contention from concurrentEvaluations - 1 other evaluations. Not a latency distribution or physical mobile-device measurement."
    success = receipt["conversionExitCode"] == 0
    if probe:
        success = success and receipt['environmentProbeCheck']['passed']
    events = re.findall(r"^(\d+)% (\w+)(?: page (\d+)/(\d+))?$",
                        (args.output / "progress.log").read_text(), re.MULTILINE)
    fractions = [int(event[0]) for event in events]
    progress_valid = bool(events) and fractions[0] == 0 and fractions[-1] == 100
    progress_valid = progress_valid and all(a <= b for a, b in zip(fractions, fractions[1:]))
    progress_valid = progress_valid and all(0 <= value <= 100 for value in fractions)
    progress_valid = progress_valid and bool(events) and events[-1][1] == "completed"
    progress_valid = progress_valid and all(
        not page or (1 <= int(page) <= case["pages"] and int(total) == case["pages"])
        for _, _, page, total in events)
    receipt["progressCheck"] = {"passed": progress_valid, "events": len(events),
                                "scope": "CLI work fraction, page bounds and completion; not elapsed-time prediction"}
    success = success and progress_valid
    if receipt["conversionExitCode"] == 0:
        try:
            report = json.loads(report_path.read_text())
            receipt["conversionReport"] = {key: value for key, value in report.items() if key != "outputURL"}
            if report["pageCount"] != case["pages"]:
                raise ValueError("source page count mismatch")
            receipt["outputBytes"] = output.stat().st_size
            receipt["outputSHA256"] = digest(output)
            text = check_epubs.check(output)
            receipt["structuralCheck"] = "passed"
            receipt["outputTextCharacters"] = len(text)
        except Exception as error:
            receipt["structuralCheck"] = str(error)
            success = False
        if args.epubcheck:
            receipt["epubcheckExitCode"] = run_epubcheck(args.epubcheck.resolve(), output.resolve(),
                                                         args.output / "epubcheck.log")
            success = success and receipt["epubcheckExitCode"] == 0
    if limit_bytes is not None:
        gate = {"limitBytes": limit_bytes, "metric": "converter process peak RSS from wait/rusage",
                "attempts": len(attempts)}
        if receipt["converterPeakRSSBytes"] > limit_bytes:
            # Pressure only lowers a resident size, so a peak over the ceiling is over it whatever
            # the host was doing.
            gate["status"] = "exceeded"
        elif not spoiled(receipt):
            gate["status"] = "passed"
        else:
            gate["status"] = "notMeasured"
            gate["error"] = ("host memory pressure rose above normal during every attempt; this run "
                             "measured a loaded host rather than the library, and neither passes "
                             "nor fails the ceiling")
        gate["passed"] = gate["status"] == "passed"
        receipt["memoryGate"] = gate
    else:
        receipt["memoryGate"] = {"status": "not configured"}
    # Recorded so that a reader of this receipt alone — the content assessment, a person — can
    # tell a run the memory ceiling alone held back from one that failed a gate.
    receipt["gatesPassedApartFromMemory"] = success
    receipt["runPassed"] = success and receipt["memoryGate"].get("passed", True)
    (args.output / "result.json").write_text(json.dumps(receipt, indent=2) + "\n")
    print(json.dumps({key: value for key, value in receipt.items()
                      if key not in {"case", "conversionReport"}}, indent=2))
    if receipt["runPassed"]:
        return 0
    # An unmeasured ceiling exits apart from a failure so that a caller, and a person reading a
    # summary, can tell a loaded host from a regression instead of investigating one as the other.
    return UNMEASURED_MEMORY_EXIT if success and receipt["memoryGate"]["status"] == "notMeasured" else 1


if __name__ == "__main__":
    raise SystemExit(main())
