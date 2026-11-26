#!/bin/bash
# 临时脚本：在仓库根运行 compat 检查器（避免 shell 工作目录不持久问题）
cd /Users/daijh/WorkBuddy/2026-11-25-12-05-46/FinalMd-swift || exit 2
echo "cwd=$(pwd)"
timeout 480 /tmp/finalmd-compat > /tmp/compat-run.log 2>&1
echo "exit=$?"
wc -l /tmp/compat-run.log
tail -15 /tmp/compat-run.log
