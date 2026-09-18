#!/usr/bin/env python3
"""usage: summarize.py <comparison.json> — the comparator's verdict fields on one line."""
import json
import sys
d = json.load(open(sys.argv[1]))
print(f"   comparator passed={d.get('passed')} provenanceErrors={len(d.get('provenanceErrors', []))} "
      f"changedPages={len(d.get('changedPages', []))} changedImages={len(d.get('changedImages', []))} "
      f"navigationChanged={d.get('navigationChanged')} changedReportFields={d.get('changedReportFields')} "
      f"changedOCRPages={d.get('changedOCRPages')} sameVisionPrograms={d.get('sameVisionPrograms')} "
      f"pageMarkersEqual={d.get('pageMarkersEqual')}")
