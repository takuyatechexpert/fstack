#!/bin/bash
# test-validate-bash.sh: validate-bash.sh の分岐を仕様ベースで検証する
#
# 契約（design-contract §3-5 / §3-6 / §3-3 / §5）:
#   §3-5 $VAR 参照緩和: 出力・露出文脈（echo/printf/cat<<< 等でシークレット変数を stdout に出す）だけ deny。
#         .env 経由の $VAR 参照そのもの（curl の URL/ヘッダに $TOKEN を渡す）は通す。
#         既知の残余リスク: 同一コマンド内の変数ロンダリング（T=$SECRET; echo $T）は素通り（現状固定）。
#   §3-6 eval コマンド位置限定: コマンド語位置（行頭/;/&/|/(/$( /バッククォート/改行 直後）の eval のみ deny。
#         パス（docs/eval/）・オプション（--eval）・部分文字列は通す。
#   §3-3 fail-closed: jq 不在 → exit 2、不正 JSON → exit 2。
#   回帰維持: リテラル直書き・トレース露出・| bash などの既存 deny はそのまま。
#
# 各分岐を個別 assert（列挙ホワイトリストの網羅原則）。

TEST_NAME="validate-bash"
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

HOOK="$HOOKS_DIR/validate-bash.sh"
TMPD=$(mktemp -d /tmp/fstack-vb-XXXXXX)

# permissionDecision を取り出す（出力なし → "none"）
decision_of() {
  [ -z "$1" ] && { echo "none"; return; }
  printf '%s' "$1" | jq -r '.hookSpecificOutput.permissionDecision // "none"' 2>/dev/null
}

# $1 = command 文字列。OUT / RC を設定する
run_vb() {
  OUT=$(jq -n --arg c "$1" '{tool_input:{command:$c}}' | bash "$HOOK" 2>/dev/null); RC=$?
}

# --- §3-5: $VAR 参照のみ（curl の URL に $API_KEY）→ 通す（無条件参照 deny を撤廃）---
run_vb 'curl "https://api.example.com/data?key=$API_KEY"'
assert_eq "0" "$RC" "\$VAR参照: exit 0"
assert_eq "none" "$(decision_of "$OUT")" "\$VAR参照: curl の URL に \$API_KEY を渡すのは通す（L48 無条件 deny 撤廃）"

# --- §3-5: echo 経由のシークレット出力 → deny 維持 ---
run_vb 'echo $GITHUB_TOKEN'
assert_eq "deny" "$(decision_of "$OUT")" "echo \$GITHUB_TOKEN: 出力文脈なので deny 維持"

# --- §3-5: 変数ロンダリング → 通す（既知の残余リスクを現状固定）---
# T=$AWS_SECRET_ACCESS_KEY; echo $T の echo $T は 3b の命名パターンに合致せず素通り。
# hook の静的解析範囲を超えるため塞がない（将来 dataflow 対応の余地をログに残す）。
run_vb 'T=$AWS_SECRET_ACCESS_KEY; echo $T'
assert_eq "0" "$RC" "変数ロンダリング: exit 0"
assert_eq "none" "$(decision_of "$OUT")" "変数ロンダリング（T=\$SECRET; echo \$T）: 現状は素通り（既知の残余リスク）"

# --- §3-6: eval コマンド位置 → deny ---
run_vb 'eval "$x"'
assert_eq "deny" "$(decision_of "$OUT")" "eval \"\$x\": 行頭のコマンド語位置 eval → deny"

# --- §3-6: 複数行コマンドの 2 行目先頭 eval → deny ---
run_vb $'echo hi\neval "$x"'
assert_eq "deny" "$(decision_of "$OUT")" "複数行の2行目先頭 eval: 改行直後のコマンド語位置 → deny"

# --- §3-6: & の後の eval → deny ---
run_vb 'foo & eval bar'
assert_eq "deny" "$(decision_of "$OUT")" "foo & eval bar: & 直後のコマンド語位置 eval → deny"

# --- §3-6: パス中の eval（docs/eval/）→ 通す（誤反応解消）---
run_vb 'cat docs/eval/foo.md'
assert_eq "0" "$RC" "docs/eval パス: exit 0"
assert_eq "none" "$(decision_of "$OUT")" "cat docs/eval/foo.md: パス中の eval は誤反応せず通す"

# --- §3-6: --eval オプション → 通す ---
run_vb 'node --eval "1+1"'
assert_eq "none" "$(decision_of "$OUT")" "node --eval: オプション中の eval は通す"

# --- 回帰維持: パイプでシェルに渡す → deny ---
run_vb 'echo x | bash'
assert_eq "deny" "$(decision_of "$OUT")" "echo x | bash: パイプ経由のシェル実行は deny 維持"

# --- §3-3: jq 不在 → fail-closed exit 2 ---
jq -n --arg c "ls -la" '{tool_input:{command:$c}}' > "$TMPD/vb.json"
SHIM=$(make_jqless_bin)
( PATH="$SHIM" /bin/bash "$HOOK" < "$TMPD/vb.json" >/dev/null 2>/dev/null ); RC=$?
assert_eq "2" "$RC" "jqless: 安全系は jq 不在で fail-closed exit 2（従来の素通りを塞ぐ）"

# --- §3-3: 不正 JSON → fail-closed exit 2 ---
( printf 'not-json-at-all' | bash "$HOOK" >/dev/null 2>/dev/null ); RC=$?
assert_eq "2" "$RC" "不正 JSON: parse 失敗で fail-closed exit 2"

finish
