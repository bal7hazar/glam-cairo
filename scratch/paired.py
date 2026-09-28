#!/usr/bin/env python3
"""Paired measurement of variants A (c3) and B (vB): cold builds interleaved on one machine.

usage: paired.py WS_A WS_B N   (workspaces built by make.py c3 / make_vb.py)
Imports scripts/consumer_cost.py (unchanged) for the consumer manifest and the timed build."""
import json, os, shutil, statistics, subprocess, sys, tempfile
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "scripts"))
import consumer_cost as cc

WA, WB, N = sys.argv[1], sys.argv[2], int(sys.argv[3])
EDITION = "2024_07"


def deps(ws, crates):
    return [{"name": c, "root": os.path.join(ws, c), "features": [], "default_features": True}
            for c in crates]


PROFILES = {
    "core": ["glam_core"],
    "core+swizzles": ["glam_core", "glam_swizzles"],
    "core+integers": ["glam_core", "glam_int"],
    "core+int_swizzles": ["glam_core", "glam_int_swizzles"],
    "everything": ["glam"],
}
consumers = {"baseline": cc.consumer_manifest([], EDITION, None)}
for tag, ws in (("A", WA), ("B", WB)):
    for p, cr in PROFILES.items():
        if tag == "A" and p == "core+int_swizzles":
            cr = ["glam_int", "glam_int_swizzles"]  # A: the int swizzles need glam_int
        consumers[f"{tag}:{p}"] = cc.consumer_manifest(deps(ws, cr), EDITION, None)

env = dict(os.environ, SCARB_INCREMENTAL="false")
dirs = {}
for name, man in consumers.items():
    d = tempfile.mkdtemp(prefix="paired_")
    os.makedirs(os.path.join(d, "src"))
    open(os.path.join(d, "Scarb.toml"), "w").write(man)
    open(os.path.join(d, "src", "lib.cairo"), "w").write("pub fn consumer_cost_answer() -> u32 {\n    42\n}\n")
    subprocess.run(["scarb", "fetch"], cwd=d, env=env, check=True, capture_output=True)
    dirs[name] = d
names = list(consumers)
res = {n: {"s": [], "gb": []} for n in names}
for i in range(N):
    order = names[i % len(names):] + names[:i % len(names)]
    for n in order:
        d = dirs[n]
        shutil.rmtree(os.path.join(d, "target"), ignore_errors=True)
        wall, rss, rc, err = cc.timed_build(["scarb", "build"], d, env)
        assert rc == 0, err
        res[n]["s"].append(wall)
        res[n]["gb"].append((rss or 0) / 1e9)
b_s = statistics.median(res["baseline"]["s"])
b_g = statistics.median(res["baseline"]["gb"])
out = {"n": N, "baseline_s": b_s, "baseline_gb": b_g, "rows": {}}
print(f"baseline {b_s:.2f} s {b_g:.2f} GB (median of {N}, interleaved)")
print("| profile | A added s | B added s | B/A s | A added GB | B added GB | B/A GB |")
print("|---|---:|---:|---:|---:|---:|---:|")
for p in PROFILES:
    a, b = res[f"A:{p}"], res[f"B:{p}"]
    a_s, b_s2 = statistics.median(a["s"]) - b_s, statistics.median(b["s"]) - b_s
    a_g, b_g2 = statistics.median(a["gb"]) - b_g, statistics.median(b["gb"]) - b_g
    out["rows"][p] = {"A_s": a_s, "B_s": b_s2, "A_gb": a_g, "B_gb": b_g2,
                      "A_samples": a, "B_samples": b}
    print(f"| {p} | {a_s:.2f} | {b_s2:.2f} | {b_s2 / a_s:.2f} | {a_g:.2f} | {b_g2:.2f} | {b_g2 / a_g:.2f} |")
json.dump(out, open("paired.json", "w"), indent=1)
