#!/usr/bin/env python3
"""Compares the C++ board (board_dump output) with the HTML reference (legacy/tests/boardref.js output).
   board_compare.py <ref_dir> <cpp_json>"""
import json, struct, sys

ref_dir, cpp_path = sys.argv[1], sys.argv[2]
ref = json.load(open(ref_dir + "/board.json"))
cpp = json.load(open(cpp_path))
f32 = lambda v: struct.unpack("f", struct.pack("f", v))[0]
ok = True


def report(name, bad, total, first=None):
    global ok
    if bad:
        ok = False
        print(f"  FAIL {name:12} {bad} of {total} differ" + (f"; first: {first}" if first else ""))
    else:
        print(f"  ok   {name:12} {total} identical")


# towns: every field
rt, ct = ref["towns"], cpp["towns"]
bad, first = 0, None
for i in range(max(len(rt), len(ct))):
    a = rt[i] if i < len(rt) else None
    b = ct[i] if i < len(ct) else None
    if a is None or b is None:
        bad += 1
        first = first or (i, a, b)
        continue
    diff = [k for k in ("x", "z", "node", "type", "pop", "cid", "name", "port", "wc", "airOv", "extra") if a[k] != b[k]]
    if (a.get("portOv") is True) != (b.get("portOv") is True):
        diff.append("portOv")
    if diff:
        bad += 1
        first = first or (i, {k: (a[k], b[k]) for k in diff})
report("towns", bad, len(rt), first)

# roads and railways: level and every vertex (float32)
for name, R, Cc in (("roads", ref["hw"], cpp["hw"]), ("railways", ref["rail"], cpp["rail"])):
    bad, first = 0, None
    for i in range(max(len(R), len(Cc))):
        a = R[i] if i < len(R) else None
        b = Cc[i] if i < len(Cc) else None
        if a is None or b is None:
            bad += 1
            first = first or (i, "missing")
            continue
        pa, pb = (a["p"], b["p"]) if name == "roads" else (a, b)
        if name == "roads" and a["lv"] != b["lv"]:
            bad += 1
            first = first or (i, "level", a["lv"], b["lv"])
            continue
        if len(pa) != len(pb) or any(f32(x) != f32(y) for x, y in zip(pa, pb)):
            bad += 1
            first = first or (i, "path", len(pa), len(pb))
    report(name, bad, len(R), first)

# checkpoints
rc, cc = ref["cps"], cpp["cps"]
bad = sum(1 for i in range(max(len(rc), len(cc))) if i >= len(rc) or i >= len(cc) or rc[i] != cc[i])
report("checkpoints", bad, len(rc), (rc[0] if rc else None, cc[0] if cc else None) if bad else None)

# route search: road, rail and sea paths between sample town pairs
bad = tot = 0
first = None
for a, b in zip(ref.get("routes", []), cpp.get("routes", [])):
    for k in ("road", "rail", "sea"):
        tot += 1
        x, y = a[k], b[k]
        same = (x is None and y is None) or (x is not None and y is not None and len(x) == len(y) and all(f32(p) == f32(q) for p, q in zip(x, y)))
        if not same:
            bad += 1
            first = first or (a["a"], a["b"], k, None if x is None else len(x), None if y is None else len(y))
report("routes", bad, tot, first)

# road / rail graphs and land components
for name, ext, size in (("road graph", "bits", 1), ("rail graph", "rbits", 1), ("components", "comp", 4)):
    a = open(f"{ref_dir}/{ext}.{'u8' if size == 1 else 'i32'}", "rb").read()
    b = open(f"{cpp_path}.{ext}", "rb").read()
    n = len(a) // size
    bad = sum(1 for i in range(n) if a[i * size:(i + 1) * size] != b[i * size:(i + 1) * size]) if len(a) == len(b) else n
    report(name, bad, n)

print("ALL IDENTICAL" if ok else "DIFFERENCES FOUND")
sys.exit(0 if ok else 1)
