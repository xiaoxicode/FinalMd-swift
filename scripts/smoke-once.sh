#!/bin/bash
cd /Users/daijh/WorkBuddy/2026-11-25-12-05-46/FinalMd-swift || exit 2
bash scripts/run-smoke.sh 2>&1 | tail -6
