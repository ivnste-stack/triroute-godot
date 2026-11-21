#!/usr/bin/env python3
"""tables.json (legacy/tools/dump_tables.js) -> godot/scripts/logistics/game_data.gd"""
import json, sys
d = json.load(open(sys.argv[1]))
def lit(v):
    if isinstance(v, dict): return "{" + ", ".join(json.dumps(k, ensure_ascii=False) + ": " + lit(x) for k, x in v.items()) + "}"
    if isinstance(v, list): return "[" + ", ".join(lit(x) for x in v) + "]"
    if v is None: return "null"
    if v is True: return "true"
    if v is False: return "false"
    if isinstance(v, float): return repr(v)
    return json.dumps(v, ensure_ascii=False)
L = ["class_name GameData", "extends RefCounted",
     "## Game tables, generated from the HTML version: legacy/tools/dump_tables.js + native/tools/gen_game_data.py. Do not edit by hand.", ""]
for k, v in d.items():
    L.append(f"const {k} = {lit(v)}")
open(sys.argv[2] if len(sys.argv) > 2 else "godot/scripts/logistics/game_data.gd", "w").write("\n".join(L) + "\n")
