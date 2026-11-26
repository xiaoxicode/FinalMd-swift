#!/bin/bash
# 重建检查器并跑 4 个倒退用例探针
cd /Users/daijh/WorkBuddy/2026-11-25-12-05-46/FinalMd-swift || exit 2
bash scripts/build-mainstream.sh || exit 3
python3 scripts/probe-regress.py
