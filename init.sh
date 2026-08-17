#!/usr/bin/env bash
# init.sh — session bootstrap. Run this FIRST, every session, human or agent.
#
# The point is determinism: every session starts from the same known state with
# the same picture of what is done and what is next. No archaeology required.

set -uo pipefail
cd "$(dirname "$0")"

BOLD=$'\033[1m'; DIM=$'\033[2m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[0;33m'; NC=$'\033[0m'

printf "\n${BOLD}REDACT — Shipaton 2026${NC}\n"
printf "${DIM}on-device PII redaction for iOS${NC}\n\n"

# ── Deadline pressure, stated plainly ───────────────────────────────────────
DEADLINE="2026-09-05"
CLOSE="2026-09-30"
today_s=$(date +%s)
sub_s=$(date -j -f "%Y-%m-%d" "$DEADLINE" +%s 2>/dev/null || echo "$today_s")
close_s=$(date -j -f "%Y-%m-%d" "$CLOSE" +%s 2>/dev/null || echo "$today_s")
printf "  ${YELLOW}%s days${NC} until App Store submission target (%s)\n" \
  "$(( (sub_s - today_s) / 86400 ))" "$DEADLINE"
printf "  ${YELLOW}%s days${NC} until Shipaton closes (%s)\n\n" \
  "$(( (close_s - today_s) / 86400 ))" "$CLOSE"

# ── Environment ─────────────────────────────────────────────────────────────
printf "${BOLD}Environment${NC}\n"
printf "  Xcode    %s\n" "$(xcodebuild -version 2>/dev/null | head -1 | cut -d' ' -f2 || echo 'MISSING')"
printf "  Swift    %s\n" "$(swift --version 2>&1 | grep -o 'Swift version [0-9.]*' | cut -d' ' -f3 || echo '?')"
printf "  Python   %s\n" "$(python3 --version 2>&1 | cut -d' ' -f2)"
printf "  Sim      %s\n" "$(xcrun simctl list runtimes 2>/dev/null | grep -m1 '^iOS' || echo 'none')"

# ── Feature state ───────────────────────────────────────────────────────────
printf "\n${BOLD}Feature state${NC}\n"
if [ -f feature_list.json ]; then
  python3 - <<'PY'
import json, collections
data = json.load(open("feature_list.json"))
features = data["features"]
counts = collections.Counter(f["status"] for f in features)
order = ["verified", "built", "in_progress", "not_started", "blocked"]
mark = {"verified": "✓", "built": "◐", "in_progress": "◔",
        "not_started": "○", "blocked": "✗"}
for status in order:
    if counts[status]:
        print("  {} {:<12} {}".format(mark[status], status, counts[status]))
total = len(features)
done = counts["verified"]
print("\n  {}/{} verified ({}%)".format(done, total, round(100 * done / total) if total else 0))
nxt = [f for f in features if f["status"] in ("not_started", "in_progress")]
if nxt:
    print("\n  Next: {} — {}".format(nxt[0]["id"], nxt[0]["name"]))
PY
else
  printf "  ${YELLOW}feature_list.json missing${NC}\n"
fi

# ── Memory ──────────────────────────────────────────────────────────────────
printf "\n${BOLD}Memory${NC}\n"
LAST=$(ls -t docs/memory/sessions/*.md 2>/dev/null | head -1)
if [ -n "$LAST" ]; then
  printf "  last session: %s\n" "$(basename "$LAST")"
  printf "  ${DIM}%s${NC}\n" "$(grep -m1 '^## ' "$LAST" | cut -c1-70)"
else
  printf "  ${YELLOW}no session logs yet${NC}\n"
fi
python3 tools/memory_index.py build 2>/dev/null | sed 's/^/  /'

# ── What to read ────────────────────────────────────────────────────────────
printf "\n${BOLD}Read before working${NC}\n"
printf "  1. CLAUDE.md        the ten rules\n"
printf "  2. docs/memory.md   current state\n"
printf "  3. AGENTS.md        your scope allowlist\n"
printf "\n${BOLD}Then${NC}\n"
printf "  ./verify.sh                                  run the gate\n"
printf "  python3 tools/memory_index.py query \"...\"     search memory\n\n"
