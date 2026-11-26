#!/bin/bash
# 临时脚本：在仓库根运行 compat 阈值闸门
cd /Users/daijh/WorkBuddy/2026-11-25-12-05-46/FinalMd-swift || exit 2
echo "cwd=$(pwd)"
python3 scripts/check-compat-thresholds.py
echo "exit=$?"
