#!/usr/bin/env python3
"""Run an opt-in real-PDF baseline, checking source identity before invoking the converter.

No downloads; large input/output files stay outside the committed fixture bundle.
A successful run measures conversion and package conformance, not content fidelity.
"""
import argparse
import ctypes
import importlib.util
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

from conversion_provenance import digest, probe_errors

ROOT = Path(__file__).resolve().parents[1]


class MemorySample(ctypes.Structure):
    # rusage_info_v0, from the Apple SDK's sys/resource.h.
    _fields_ = [("uuid", ctypes.c_uint8 * 16)] + [
        (name, ctypes.c_uint64) for name in (
            "user", "system", "idleWakeups", "interruptWakeups", "pageins", "wired",
            "resident", "footprint", "started", "exited")]


def memory_reader():
    if sys.platform != "darwin":
        return lambda pid: None
    library = ctypes.CDLL("/usr/lib/libproc.dylib")
    library.proc_pid_rusage.argtypes = [ctypes.c_int, ctypes.c_int, ctypes.c_void_p]
    library.proc_pid_rusage.restype = ctypes.c_int

    def read(pid):
        sample = MemorySample()
        if library.proc_pid_rusage(pid, 0, ctypes.byref(sample)) != 0:
            return None
        return {"residentBytes": sample.resident, "physicalFootprintBytes": sample.footprint}
    return read


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
    parser.add_argument("--converter-option", action="append", default=[], metavar="FLAG=VALUE",
                        help="explicit converter option, e.g. --raster-dpi=240, forwarded as two arguments "
                             "after the input/output paths and recorded in the receipt; repeatable")
    args = parser.parse_args()
    converter_options = []
    for option in args.converter_option:
        flag, separator, value = option.partition("=")
        if not flag.startswith("--") or not separator or not value:
            parser.error("converter option must look like --flag=value")
        converter_options += [flag, value]
    cases = json.loads((ROOT / "corpus/manifest.json").read_text())["documents"]
    case = next((item for item in cases if item["id"] == args.case), None)
    if case is None:
        parser.error("unknown corpus case")
    if not math.isfinite(args.timeout) or args.timeout <= 0:
        parser.error("timeout must be positive")
    memory_limit = args.max_peak_rss_mib
    if memory_limit is None:
        memory_limit = case.get("memoryBudget", {}).get("maxPeakRSSMiB")
    if memory_limit is not None and (not math.isfinite(memory_limit) or memory_limit <= 0):
        parser.error("memory ceiling must be finite and positive")
    if args.pdf.stat().st_size != case["bytes"] or digest(args.pdf) != case["sha256"]:
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
        "options": " ".join(converter_options) if converter_options else "library defaults",
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
    start = time.monotonic()
    with report_path.open("w") as report, (args.output / "progress.log").open("w") as log:
        read_memory = memory_reader()
        samples = []
        process = subprocess.Popen([str(converter), str(args.pdf.resolve()), str(output.resolve()), *converter_options],
                                   stdout=report, stderr=log)
        stage = "starting"
        pending = ""
        with (args.output / "progress.log").open() as progress:
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
                if sample is not None:
                    samples.append({"seconds": time.monotonic() - start, "progress": stage, **sample})
                if time.monotonic() - start > args.timeout:
                    os.kill(process.pid, signal.SIGKILL)
                    receipt["timedOut"] = True
                    _, status, usage = os.wait4(process.pid, 0)
                    process.returncode = os.waitstatus_to_exitcode(status)
                    break
                time.sleep(0.1)
        receipt["conversionExitCode"] = process.wait()
        (args.output / "memory-samples.json").write_text(json.dumps(samples, indent=2) + "\n")
        if samples:
            receipt["sampledPeakPhysicalFootprintBytes"] = max(s["physicalFootprintBytes"] for s in samples)
    receipt["conversionSeconds"] = time.monotonic() - start
    receipt["converterPeakRSSBytes"] = usage.ru_maxrss * (1 if sys.platform == "darwin" else 1024)
    receipt["converterCPUSeconds"] = usage.ru_utime + usage.ru_stime
    receipt["measurementScope"] = "One process run; RSS excludes separate Apple services. Timing excludes validation. Not a latency distribution or physical mobile-device measurement."
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
            spec = importlib.util.spec_from_file_location("epub_contracts", ROOT / "tools/check-epubs.py")
            module = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(module)
            text = module.check(output)
            receipt["structuralCheck"] = "passed"
            receipt["outputTextCharacters"] = len(text)
        except Exception as error:
            receipt["structuralCheck"] = str(error)
            success = False
        if args.epubcheck:
            with (args.output / "epubcheck.log").open("w") as log:
                result = subprocess.run([str(args.epubcheck.resolve()), str(output.resolve())],
                                        stdout=log, stderr=subprocess.STDOUT)
            receipt["epubcheckExitCode"] = result.returncode
            success = success and result.returncode == 0
    if memory_limit is not None:
        limit_bytes = int(memory_limit * 1024 * 1024)
        within_limit = receipt["converterPeakRSSBytes"] <= limit_bytes
        receipt["memoryGate"] = {"limitBytes": limit_bytes, "passed": within_limit,
                                 "metric": "converter process peak RSS from wait/rusage"}
        success = success and within_limit
    else:
        receipt["memoryGate"] = {"status": "not configured"}
    receipt["runPassed"] = success
    (args.output / "result.json").write_text(json.dumps(receipt, indent=2) + "\n")
    print(json.dumps({key: value for key, value in receipt.items()
                      if key not in {"case", "conversionReport"}}, indent=2))
    return 0 if success else 1


if __name__ == "__main__":
    raise SystemExit(main())
