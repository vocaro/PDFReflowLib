"""Compare serial quiet and pressured corpus lanes for issue #244.

Usage: python3 measurements/footprint-pressure/compare.py QUIET_DIR PRESSURED_DIR
Both directories are outputs of tools/run_corpus_regressions.py over the same cases.
"""
import json
from pathlib import Path
import sys

MIB = 1024 * 1024


def read(directory):
    summary = json.loads((directory / "summary.json").read_text())
    names = [item["case"] for item in summary["results"]]
    results = {}
    for name in names:
        case = directory / name
        receipt = json.loads((case / "result.json").read_text())
        samples = json.loads((case / "memory-samples.json").read_text())
        levels = [sample.get("memoryPressureLevel") for sample in samples]
        results[name] = {
            "rss": receipt["converterPeakRSSBytes"],
            "footprint": receipt["converterLifetimeMaxPhysicalFootprintBytes"],
            "pressureSamples": sum(level not in (None, 1) for level in levels),
            "samples": len(levels),
            "pressurePeak": receipt.get("peakMemoryPressureLevel"),
            "runPassed": receipt["runPassed"],
            "memoryGate": receipt["memoryGate"]["status"],
            "converterSHA256": receipt["converterSHA256"],
        }
    return names, results


def main():
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    quiet_names, quiet = read(Path(sys.argv[1]))
    pressured_names, pressured = read(Path(sys.argv[2]))
    if quiet_names != pressured_names:
        raise SystemExit("Corpus case sets or order differ")
    print("case,quiet RSS MiB,pressure RSS MiB,RSS change %,quiet footprint MiB,"
          "pressure footprint MiB,footprint change %,pressure sample %")
    for name in quiet_names:
        q, p = quiet[name], pressured[name]
        if q["converterSHA256"] != p["converterSHA256"]:
            raise SystemExit(f"Converter differs for {name}")
        def mib(value):
            return f"{value / MIB:.1f}"
        def change(key):
            return f"{(p[key] / q[key] - 1) * 100:+.1f}"
        pressure_share = p["pressureSamples"] / p["samples"] * 100 if p["samples"] else 0
        print(f"{name},{mib(q['rss'])},{mib(p['rss'])},{change('rss')},"
              f"{mib(q['footprint'])},{mib(p['footprint'])},{change('footprint')},"
              f"{pressure_share:.1f}")
        if q["pressureSamples"] or not p["pressureSamples"]:
            print(f"  INVALID PRESSURE PAIR: quiet {q['pressureSamples']} pressured "
                  f"{p['pressureSamples']}", file=sys.stderr)


if __name__ == "__main__":
    main()
