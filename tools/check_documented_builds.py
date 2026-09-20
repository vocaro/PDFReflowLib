#!/usr/bin/env python3
"""Compile the standalone Swift probes, and the build commands the documentation prints.

A probe under `tools/probes/` is compiled by hand with swiftc beside the library files it calls,
so nothing else proves that its source list is still sufficient: the library gains a dependency,
the list stays as it was, and the command in the runbook fails the next time somebody runs it
(#204). This gate compiles every probe from `pdfreflow_tools.swift_sources`, the one list the
gates and the documented recipes both read, and then runs each swiftc command printed in the
documentation exactly as written, with only its `-o` target moved into a scratch directory.

A documented build that is renamed, deleted or left pointing at a probe that no longer exists
fails here, as does a source list the library has outgrown.
"""
import argparse
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

from pdfreflow_tools import swift_sources
from pdfreflow_tools.corpus import ROOT

# The documentation that prints a probe build, and the probe each of its commands builds. A
# command the documentation adds, drops or repoints is a mismatch, not a silently skipped check.
DOCUMENTED = {
    ('doc/corpus.md', 'probe-raster-environment.swift'),
    ('doc/memory-testing.md', 'probe-pdfkit-memory.swift'),
    ('doc/regression-testing.md', 'capture-layout-fixture.swift'),
    ('doc/regression-testing.md', 'capture-algebra-layout.swift'),
}

FENCE = re.compile(r'^\s*```')
OUTPUT = re.compile(r'(?<=\s)-o\s+\S+')


def commands(text):
    """The shell commands inside the text's fenced blocks, with continuation lines joined."""
    found, inside, pending = [], False, ''
    for line in text.splitlines():
        if FENCE.match(line):
            inside, pending = not inside, ''
            continue
        if not inside:
            continue
        pending += line.rstrip()
        if pending.endswith('\\'):
            pending = pending[:-1].rstrip() + ' '
            continue
        found.append(pending)
        pending = ''
    return found


def swift_builds(text):
    """The swiftc commands among them, each paired with the probe it builds."""
    builds = []
    for command in commands(text):
        words = command.split()
        if not (words[:1] == ['swiftc'] or words[:2] == ['xcrun', 'swiftc']):
            continue
        named = [probe for probe in swift_sources.PROBE_SOURCES if probe in command]
        builds.append((command, named[0] if len(named) == 1 else None))
    return builds


def environment():
    values = dict(os.environ)
    values.setdefault('DEVELOPER_DIR', subprocess.check_output(['xcode-select', '-p'], text=True).strip())
    return values


def compile_sources(sources, binary, env):
    """Compile the probe's listed sources; returns swiftc's output when it fails."""
    result = subprocess.run(['xcrun', 'swiftc', '-swift-version', '6', *sources, '-o', str(binary)],
                            cwd=ROOT, env=env, capture_output=True, text=True)
    return None if result.returncode == 0 else (result.stdout + result.stderr).strip()


def run_documented(command, binary, env):
    """Run the documented command from the repository root, writing its product to `binary`."""
    rewritten, count = OUTPUT.subn(f'-o {binary}', command)
    if count != 1:
        return f'the command names {count} output files; one `-o` target is expected'
    result = subprocess.run(['bash', '-euo', 'pipefail', '-c', rewritten],
                            cwd=ROOT, env=env, capture_output=True, text=True)
    return None if result.returncode == 0 else (result.stdout + result.stderr).strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.parse_args()
    if sys.platform != 'darwin':
        parser.error('The probes require macOS and a full Xcode installation')
    env = environment()
    failures = []
    with tempfile.TemporaryDirectory(prefix='pdfreflow-documented-builds-') as directory:
        scratch = Path(directory)
        for probe in sorted(swift_sources.PROBE_SOURCES):
            problem = compile_sources(swift_sources.sources(probe), scratch / probe, env)
            print(f'{"FAIL" if problem else "PASS"} source list {probe}')
            if problem:
                failures.append(f'{probe} does not compile from its listed sources:\n{problem}')

        found = set()
        for name in sorted({document for document, _ in DOCUMENTED}):
            path = ROOT / name
            if not path.is_file():
                failures.append(f'{name} is gone; it documented a probe build')
                continue
            for index, (command, probe) in enumerate(swift_builds(path.read_text())):
                if probe is None:
                    failures.append(f'{name} builds something other than one known probe: {command}')
                    continue
                found.add((name, probe))
                problem = run_documented(command, scratch / f'documented-{index}-{probe}', env)
                print(f'{"FAIL" if problem else "PASS"} {name} builds {probe} as written')
                if problem:
                    failures.append(f'{name} no longer compiles its documented {probe} build:\n{problem}')
        for document, probe in sorted(DOCUMENTED - found):
            failures.append(f'{document} no longer documents the {probe} build')
        for document, probe in sorted(found - DOCUMENTED):
            failures.append(f'{document} documents an unregistered {probe} build; add it to DOCUMENTED')

    for failure in failures:
        print(failure, file=sys.stderr)
    if failures:
        raise SystemExit(f'{len(failures)} documented build or probe source list is stale')
    print(f'PASS {len(swift_sources.PROBE_SOURCES)} probe source lists and {len(DOCUMENTED)} documented builds')


if __name__ == '__main__':
    main()
