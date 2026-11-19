#!/usr/bin/env python3
"""Offline one-hop session lifecycle checks; no live executor or teleport claims."""
import argparse
import json
import sys
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--deps',type=Path)
p.add_argument('--json',type=Path)
a=p.parse_args()
if a.deps:sys.path.insert(0,str(a.deps))
from lupa import LuaRuntime
r=Path(__file__).resolve().parent
lua=LuaRuntime(unpack_returned_tuples=True)
result=lua.execute((r/'chalk-session-continuity-selftest.lua').read_text())(
    lua.execute((r/'chalk-session-continuity.lua').read_text()),(r/'chalk-overlay-core.lua').read_text())
report={'passed':result['passed'],'total':result['total'],'results':[
    dict(row.items()) for _,row in sorted(result['results'].items())]}
print(json.dumps(report,indent=2))
if a.json:a.json.write_text(json.dumps(report,indent=2)+'\n')
raise SystemExit(result['failed']>0)
