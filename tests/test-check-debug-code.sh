#!/bin/bash
# T2: check-debug-code.sh の再現テスト
#
# 契約（design-contract §4 T2 / §2 PostToolUse）:
#   - 入力は stdin の JSON（.tool_input.file_path）。環境変数は使わない
#   - console.log 等の残存を検出したら stderr に警告 + exit 2（Claude に届く経路）
#   - クリーンファイル・対象外拡張子では exit 0・stderr なし
#
# 基準版 (46938a3) は $CLAUDE_TOOL_INPUT（存在しない環境変数）を読むため
# 入力が空になり、検出処理に到達せず黙って exit 0（サイレント故障）。

TEST_NAME="check-debug-code"
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

HOOK="$HOOKS_DIR/check-debug-code.sh"

# CLAUDE_TOOL_INPUT を明示的に unset して stdin だけで hook を起動する
run_hook() {
  # $1: stdin payload / errfile 経由で stderr を取得
  local payload="$1" errfile="$2"
  env -u CLAUDE_TOOL_INPUT bash "$HOOK" >/dev/null 2>"$errfile" <<EOF
$payload
EOF
}

payload_for() { printf '{"tool_input":{"file_path":"%s"}}' "$1"; }

# --- ケース1: console.log 入り .ts → exit 2 + stderr に警告 ---
WORK=$(mktemp -d /tmp/fstack-debug-XXXXXX)
printf 'export function f() {\n  console.log("dbg");\n}\n' > "$WORK/debug.ts"
ERR="$WORK/err1"
run_hook "$(payload_for "$WORK/debug.ts")" "$ERR"; RC=$?
ERRTXT=$(cat "$ERR")
assert_eq "2" "$RC" "検出: exit 2 で返る（基準版は env 未設定で exit 0 → RED）"
assert_nonempty "$ERRTXT" "検出: stderr に警告が出る（基準版は無出力 → RED）"
assert_contains "$ERRTXT" "debug.ts" "検出: 警告に対象ファイルパスを含む"

# --- ケース2: クリーンな .ts → exit 0・stderr なし ---
WORK=$(mktemp -d /tmp/fstack-debug-XXXXXX)
printf 'export const answer = 42;\n' > "$WORK/clean.ts"
ERR="$WORK/err2"
run_hook "$(payload_for "$WORK/clean.ts")" "$ERR"; RC=$?
ERRTXT=$(cat "$ERR")
assert_eq "0" "$RC" "クリーン: exit 0"
assert_empty "$ERRTXT" "クリーン: stderr なし"

# --- ケース3: 対象外拡張子（.txt）は console.log があっても素通り ---
WORK=$(mktemp -d /tmp/fstack-debug-XXXXXX)
printf 'console.log("not code")\n' > "$WORK/note.txt"
ERR="$WORK/err3"
run_hook "$(payload_for "$WORK/note.txt")" "$ERR"; RC=$?
assert_eq "0" "$RC" "対象外拡張子: exit 0"

# --- C1-5: stderr 警告にマッチ行の内容を含めない（A4: `(lines: <n>, ...)` のみ）---
WORK=$(mktemp -d /tmp/fstack-debug-XXXXXX)
printf 'function g() {\n  console.log("SENTINELPAYLOAD42");\n}\n' > "$WORK/leak.ts"
ERR="$WORK/err5"
run_hook "$(payload_for "$WORK/leak.ts")" "$ERR"; RC=$?
ERRTXT=$(cat "$ERR")
assert_eq "2" "$RC" "C1-5: 検出で exit 2"
assert_contains "$ERRTXT" "lines:" "C1-5: 新形式 (lines: <n>) で行番号のみ提示"
assert_not_contains "$ERRTXT" "SENTINELPAYLOAD42" "C1-5: stderr にマッチ行の内容を含めない"

finish
