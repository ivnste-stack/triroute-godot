#!/usr/bin/env python3
"""Compares generated states with the HTML reference.   states_compare.py <ref_dir> <states.json>"""
import json, sys
ref = json.load(open(sys.argv[1] + "/board.json"))["states"]
cpp = json.load(open(sys.argv[2]))
keys = ["pop", "name", "full", "color", "dev", "gdp", "stability", "infl", "unemp", "tech", "corr", "mil", "leader", "age", "ideol", "trait", "electionIn", "treasury", "debt", "laws", "deposit"]
bad = 0
for i, (a, b) in enumerate(zip(ref, cpp)):
    d = [k for k in keys if a.get(k) != b.get(k)]
    if d:
        bad += 1
        if bad <= 3: print(f"  state {i}: " + ", ".join(f"{k}: {a.get(k)} vs {b.get(k)}" for k in d[:4]))
if len(ref) != len(cpp): bad += 1; print("  count", len(ref), len(cpp))
print(f"  {'FAIL' if bad else 'ok  '} states {len(ref)}, {bad} differ ({len(keys)} fields each)")
sys.exit(1 if bad else 0)
