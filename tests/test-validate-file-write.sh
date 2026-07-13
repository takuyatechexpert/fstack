#!/bin/bash
# test-validate-file-write.sh: validate-file-write.sh の分岐を仕様ベースで検証する
#
# 契約（design-contract §3-11 / §3-3 / §5）:
#   §3-11 settings.json 誤反応修正: 親ディレクトリが .claude の設定のみ ask。
#         /…/.claude/settings.json・/…/.claude/settings.local.json → ask、
#         .vscode/settings.json・任意 repo の settings.json → 通す。
#   既存 deny 維持: .env → deny（.env.example は通す）、鍵/証明書（.pem 等）→ deny。
#   §3-3 fail-closed: jq 不在 → exit 2、不正 JSON → exit 2。
#
# file_path は展開済み絶対パスで来る前提（~ リテラルは来ない）。各分岐を個別 assert。

TEST_NAME="validate-file-write"
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

HOOK="$HOOKS_DIR/validate-file-write.sh"
TMPD=$(mktemp -d /tmp/fstack-vfw-XXXXXX)

decision_of() {
  [ -z "$1" ] && { echo "none"; return; }
  printf '%s' "$1" | jq -r '.hookSpecificOutput.permissionDecision // "none"' 2>/dev/null
}

# $1 = file_path。OUT / RC を設定する
run_vfw() {
  OUT=$(jq -n --arg p "$1" '{tool_input:{file_path:$p}}' | bash "$HOOK" 2>/dev/null); RC=$?
}

# --- §3-11: .claude/settings.json → ask ---
run_vfw '/Users/x/.claude/settings.json'
assert_eq "ask" "$(decision_of "$OUT")" ".claude/settings.json: Claude 設定なので ask"

# --- §3-11: .claude/settings.local.json → ask ---
run_vfw '/Users/x/.claude/settings.local.json'
assert_eq "ask" "$(decision_of "$OUT")" ".claude/settings.local.json: Claude 設定なので ask"

# --- §3-11: .vscode/settings.json → 通す（誤反応解消）---
run_vfw '/Users/x/project/.vscode/settings.json'
assert_eq "0" "$RC" ".vscode/settings.json: exit 0"
assert_eq "none" "$(decision_of "$OUT")" ".vscode/settings.json: .claude 配下でないので通す"

# --- §3-11: 任意 repo の settings.json → 通す ---
run_vfw '/Users/x/myrepo/settings.json'
assert_eq "none" "$(decision_of "$OUT")" "任意 repo の settings.json: .claude 配下でないので通す"

# --- 既存 deny 維持: .env → deny ---
run_vfw '/Users/x/project/.env'
assert_eq "deny" "$(decision_of "$OUT")" ".env: シークレットファイルなので deny"

# --- 既存 deny 維持: .env.example → 通す（テンプレート用途）---
run_vfw '/Users/x/project/.env.example'
assert_eq "0" "$RC" ".env.example: exit 0"
assert_eq "none" "$(decision_of "$OUT")" ".env.example: テンプレートなので通す"

# --- 既存 deny 維持: 鍵/証明書（.pem、.ssh 外）→ deny ---
run_vfw '/Users/x/certs/id_rsa.pem'
assert_eq "deny" "$(decision_of "$OUT")" "id_rsa.pem: 鍵/証明書ファイルなので deny"

# --- §3-3: jq 不在 → fail-closed exit 2 ---
jq -n --arg p "/Users/x/project/src/app.ts" '{tool_input:{file_path:$p}}' > "$TMPD/vfw.json"
SHIM=$(make_jqless_bin)
( PATH="$SHIM" /bin/bash "$HOOK" < "$TMPD/vfw.json" >/dev/null 2>/dev/null ); RC=$?
assert_eq "2" "$RC" "jqless: 安全系は jq 不在で fail-closed exit 2"

# --- §3-3: 不正 JSON → fail-closed exit 2 ---
( printf 'not-json-at-all' | bash "$HOOK" >/dev/null 2>/dev/null ); RC=$?
assert_eq "2" "$RC" "不正 JSON: parse 失敗で fail-closed exit 2"

finish
