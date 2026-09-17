#!/usr/bin/env python3
"""Two CDC concurrent repeat checks at once (four simultaneous conversions), to load Vision.

usage: loaded_cdc.py <scratch-dir> <round-tag>
"""
from pathlib import Path
import subprocess
import sys

HERE = Path(__file__).resolve().parent
scratch, tag = sys.argv[1], sys.argv[2]
processes = [subprocess.Popen([sys.executable, HERE / 'run_case.py', scratch, 'cdc-zombie-pandemic-2011',
                               'concurrent', '--tag', f'loaded-{tag}{side}'])
             for side in ('a', 'b')]
sys.exit(max(process.wait() for process in processes))
