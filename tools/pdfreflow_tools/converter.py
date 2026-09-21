"""Run the pdf-reflow command-line converter and EPUBCheck in fresh processes."""
import json
from pathlib import Path
import subprocess
from typing import NamedTuple

# Pinning the identifier and the modification date makes two conversions of one source
# byte-identical (doc/conversion-options.md).
PINNED_MODIFICATION_DATE = '2026-01-01T00:00:00Z'


def pinned_packaging(identifier):
    """CLI flags that pin the package identifier and modification date."""
    return ['--package-identifier', identifier, '--modification-date', PINNED_MODIFICATION_DATE]


class Conversion(NamedTuple):
    command: list
    returncode: int
    stdout: str
    stderr: str
    report: dict | None


def convert(converter, source, output, *flags, timeout=None, check=True, input=None):
    """Convert source to output in a fresh converter process.

    stdout holds the conversion report, parsed into `report` when the process exits zero;
    stderr holds the progress log. With `check`, a nonzero exit raises
    subprocess.CalledProcessError as subprocess.run does; without it the caller reads
    `returncode` and `report` is None. `input` is written to the process's standard input,
    which is how a password reaches it without becoming an argument (#252).
    """
    command = [str(converter), str(source), str(output), *flags]
    run = subprocess.run(command, capture_output=True, text=True, timeout=timeout, check=check,
                         input=input)
    report = json.loads(run.stdout) if run.returncode == 0 else None
    return Conversion(command, run.returncode, run.stdout, run.stderr, report)


def run_epubcheck(epubcheck, book, log, *, timeout=None, check=False):
    """Validate book with EPUBCheck, writing its combined output to log; returns the exit code."""
    with Path(log).open('w') as stream:
        run = subprocess.run([str(epubcheck), str(book)], stdout=stream, stderr=subprocess.STDOUT,
                             timeout=timeout, check=check)
    return run.returncode
