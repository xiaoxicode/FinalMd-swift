#!/bin/bash
# 全量回归：主流矩阵 + 冒烟 + 语料 compat
cd /Users/daijh/WorkBuddy/2026-11-25-12-05-46/FinalMd-swift || exit 2
echo "== lazy/004 probe =="
python3 scripts/probe-lazy.py | head -25
echo
echo "== mainstream 317 =="
timeout 300 /tmp/finalmd-mainstream tests/fixtures/specs/mainstream-round2.json /tmp/mainstream-results.json >/dev/null && \
  python3 scripts/run-mainstream.py 2>&1 | tail -8
echo
echo "== smoke =="
bash scripts/run-smoke.sh 2>&1 | tail -8
