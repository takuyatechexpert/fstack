#!/bin/bash
# test-check-implementation-routing.sh: check-implementation-routing.sh を仕様ベースで検証する
#
# 契約（design-contract §3-9 / §5 / §1.3）:
#   - Edit/Write/NotebookEdit 前に skills.log を見て、直近ウィンドウ内に
#     solo-with-verifier / orchestra-of-agents 起動痕跡があるか確認する。
#   - 痕跡あり → exit 0・reminder なし / 痕跡なし → exit 0・stderr に reminder（非ブロッキング）。
#   - FSTACK_ROUTING_WINDOW_SEC でしきい値（既定 1800 秒）を override 可能。
#   - jqless（jq 解決失敗）→ 非ブロッキング advisory のため exit 0 継続（no-op、reminder 出さない）。
#
# skills.log は一時 HOME + FSTACK_LOG_DIR に隔離して用意する。
# タイムスタンプはローカル時刻で生成（hook が date +%s / date -j -f をローカルで扱うため）。

TEST_NAME="check-implementation-routing"
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

HOOK="$HOOKS_DIR/check-implementation-routing.sh"
REMINDER_MARK="implementation-task-routing"

# epoch → "YYYY-MM-DD HH:MM:SS"（macOS: -r / Linux: -d @）
fmt_ts() {
  date -r "$1" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date -d "@$1" '+%Y-%m-%d %H:%M:%S' 2>/dev/null
}

# Edit ツールで非除外パス（.ts）を編集する payload
mk_edit_payload() {
  jq -n --arg p "$1" '{tool_name:"Edit",tool_input:{file_path:$p}}'
}

setup_home() {
  TMPHOME=$(mktemp -d /tmp/fstack-routehome-XXXXXX)
  LOGDIR="$TMPHOME/.claude/logs"
  mkdir -p "$LOGDIR"
  SKILLS_LOG="$LOGDIR/skills.log"
  PAYLOAD=$(mk_edit_payload "/Users/x/proj/src/app.ts")
}

# $1 = FSTACK_ROUTING_WINDOW_SEC（空なら未設定）。ERRTXT / RC を設定する
run_routing() {
  local win="$1" errf
  errf=$(mktemp /tmp/fstack-routeerr-XXXXXX)
  if [ -n "$win" ]; then
    HOME="$TMPHOME" FSTACK_LOG_DIR="$LOGDIR" FSTACK_ROUTING_WINDOW_SEC="$win" \
      bash "$HOOK" >/dev/null 2>"$errf" <<<"$PAYLOAD"; RC=$?
  else
    HOME="$TMPHOME" FSTACK_LOG_DIR="$LOGDIR" \
      bash "$HOOK" >/dev/null 2>"$errf" <<<"$PAYLOAD"; RC=$?
  fi
  ERRTXT=$(cat "$errf")
}

# --- ケース1: 直近に orchestra 痕跡あり → exit 0・reminder なし ---
setup_home
NOW=$(date +%s)
printf '[%s] [SKILL] orchestra-of-agents | wave 1\n' "$(fmt_ts "$NOW")" > "$SKILLS_LOG"
run_routing ""
assert_eq "0" "$RC" "痕跡あり: exit 0（非ブロッキング）"
assert_not_contains "$ERRTXT" "$REMINDER_MARK" "痕跡あり: reminder を出さない"

# --- ケース2: 痕跡なし（無関係な skill のみ）→ exit 0・stderr に reminder ---
setup_home
NOW=$(date +%s)
printf '[%s] [SKILL] todo | list\n' "$(fmt_ts "$NOW")" > "$SKILLS_LOG"
run_routing ""
assert_eq "0" "$RC" "痕跡なし: exit 0（非ブロッキング）"
assert_contains "$ERRTXT" "$REMINDER_MARK" "痕跡なし: stderr に reminder を出す"

# --- ケース3: FSTACK_ROUTING_WINDOW_SEC override がしきい値に反映される ---
# 10 分（600 秒）前の solo 痕跡を置く。
setup_home
NOW=$(date +%s)
printf '[%s] [SKILL] solo-with-verifier | task\n' "$(fmt_ts $((NOW - 600)))" > "$SKILLS_LOG"
# 既定（1800 秒）では 600 秒前は範囲内 → reminder なし
run_routing ""
assert_not_contains "$ERRTXT" "$REMINDER_MARK" "override前(既定1800): 10分前の痕跡は範囲内 → reminder なし"
# window=60 に絞ると 600 秒前は範囲外 → reminder あり（override 反映）
run_routing "60"
assert_eq "0" "$RC" "override後: 非ブロッキングなので exit 0"
assert_contains "$ERRTXT" "$REMINDER_MARK" "FSTACK_ROUTING_WINDOW_SEC=60: しきい値が反映され範囲外 → reminder"

# --- ケース4: jqless → 非ブロッキング advisory のため exit 0 継続（no-op）---
setup_home
NOW=$(date +%s)
printf '[%s] [SKILL] todo | list\n' "$(fmt_ts "$NOW")" > "$SKILLS_LOG"
printf '%s' "$PAYLOAD" > "$TMPHOME/p.json"
SHIM=$(make_jqless_bin)
ERRF=$(mktemp /tmp/fstack-routejqless-XXXXXX)
( PATH="$SHIM" HOME="$TMPHOME" FSTACK_LOG_DIR="$LOGDIR" /bin/bash "$HOOK" \
    < "$TMPHOME/p.json" >/dev/null 2>"$ERRF" ); RC=$?
ERRTXT=$(cat "$ERRF")
assert_eq "0" "$RC" "jqless: 非ブロッキング advisory → exit 0 で継続"
assert_not_contains "$ERRTXT" "$REMINDER_MARK" "jqless: 解析不能のため no-op（reminder 出さない）"

finish
