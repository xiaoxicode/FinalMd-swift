#!/usr/bin/env python3
"""探针：打印指定输入的 out1/frag，对比期望差异"""
import json, subprocess, sys

tests = {
    "escaped-closing-hashes": "### foo \\###\n## foo #\\##\n# foo \\#",
    "escaped-plus-autolink": "<foo\\+@bar.example.com>",
    "atx-closing": "# heading #\n### heading ###",
    "atx-esc-single": "# foo \\#",
}
probe = {"source": "p", "version": "t", "count": len(tests),
         "cases": [{"id": i, "section": n, "markdown": md, "ref": "cm", "check": "full"}
                   for i, (n, md) in enumerate(tests.items(), 1)]}
with open("/tmp/probe.json", "w") as f:
    json.dump(probe, f)
subprocess.run(["/tmp/finalmd-mainstream", "/tmp/probe.json", "/tmp/probe.out.json"], timeout=30)
r = json.load(open("/tmp/probe.out.json"))
rows = r["results"] if isinstance(r, dict) and "results" in r else r
by_id = {x["id"]: x for x in rows}
for i, (n, md) in enumerate(tests.items(), 1):
    x = by_id[i]
    print(f"== {n} ==")
    print("  md  :", repr(md))
    print("  out1:", repr(x.get("out1", "")))
    print("  out2:", repr(x.get("out2", "")))
    print("  frag:", repr(x.get("frag", ""))[:150])
    print("  stable:", x.get("stable"))
