#!/bin/bash
cd /Users/daijh/WorkBuddy/2026-11-25-12-05-46/FinalMd-swift || exit 2
python3 scripts/gen-compat-report.py || exit 3
python3 scripts/check-compat-thresholds.py --update-baseline || exit 4
python3 scripts/check-compat-thresholds.py | tail -6
