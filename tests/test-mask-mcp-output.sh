#!/bin/bash
# T5: mask-mcp-output.sh の再現テスト
#
# 契約（design-contract §4 T5 / §2 PostToolUse(MCP) / §7）:
#   - mcp__ ツールの tool_response をマスクし updatedMCPToolOutput で返す
#   - mask-secrets.sh は自身の実体位置から解決する（直接・symlink・コピー対応）
#   - mask-secrets.sh も fstack-mask-secrets.sh も無い場合は fail-closed
#     （元レスポンスは絶対に返さず、説明文字列に置換して updatedMCPToolOutput を返す）
#   - 非 MCP ツールは素通り（exit 0・出力なし）
#
# 基準版 (46938a3) は mask-secrets.sh を ~/.claude/hooks/ にハードコードするため
# 自身の隣接ファイルを解決できず、パスが不在だと set -euo pipefail でクラッシュして
# 何も出力しない → Claude 側では元レスポンス（シークレット入り）が素通りする fail-open。
#
# 各テストは HOME を tmp サンドボックスに差し替え、実環境の ~/.claude を巻き込まない。

TEST_NAME="mask-mcp-output"
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

SECRET='Bearer abcdefghij1234567890'
SECRET_TAIL='abcdefghij1234567890'

# mcp payload（tool_response は JSON 文字列にシークレットを含める）
mcp_payload() {
  printf '{"tool_name":"mcp__demo__fetch","tool_response":"result: %s done"}' "$SECRET"
}

# サンドボックスを作り、mask-mcp-output.sh を配置する。
# $1=with_sibling(yes/no) — yes なら隣接 mask-secrets.sh も配置する。
# グローバル SANDBOX / HOOKSBOX を設定する。
make_sandbox() {
  SANDBOX=$(mktemp -d /tmp/fstack-mcpbox-XXXXXX)   # HOME 兼サンドボックス
  HOOKSBOX="$SANDBOX/hooks"
  mkdir -p "$HOOKSBOX"
  cp "$HOOKS_DIR/mask-mcp-output.sh" "$HOOKSBOX/mask-mcp-output.sh"
  chmod +x "$HOOKSBOX/mask-mcp-output.sh"
  # lib/common.sh を同梱（実デプロイ構成の再現。単体コピーだと lib 解決失敗で秘匿に落ちる）
  mkdir -p "$HOOKSBOX/lib" && cp "$HOOKS_DIR/lib/common.sh" "$HOOKSBOX/lib/common.sh"
  if [ "$1" = "yes" ]; then
    cp "$HOOKS_DIR/mask-secrets.sh" "$HOOKSBOX/mask-secrets.sh"
    chmod +x "$HOOKSBOX/mask-secrets.sh"
  fi
}

# masker が exit 1 する壊れたダミーを隣接配置したサンドボックスを作る
make_sandbox_failmasker() {
  SANDBOX=$(mktemp -d /tmp/fstack-mcpbox-XXXXXX)
  HOOKSBOX="$SANDBOX/hooks"
  mkdir -p "$HOOKSBOX"
  cp "$HOOKS_DIR/mask-mcp-output.sh" "$HOOKSBOX/mask-mcp-output.sh"
  chmod +x "$HOOKSBOX/mask-mcp-output.sh"
  # lib/common.sh を同梱（masker 失敗の検証意図が lib 不在で崩れないようにする）
  mkdir -p "$HOOKSBOX/lib" && cp "$HOOKS_DIR/lib/common.sh" "$HOOKSBOX/lib/common.sh"
  printf '#!/bin/bash\ncat >/dev/null\nexit 1\n' > "$HOOKSBOX/mask-secrets.sh"
  chmod +x "$HOOKSBOX/mask-secrets.sh"
}

is_valid_json_str() { printf '%s' "$1" | jq empty >/dev/null 2>&1 && echo yes || echo no; }

# HOME を差し替えて hook を起動する
run_mcp() {
  # $1: 起動する mask-mcp-output.sh のパス（実体 or symlink）
  HOME="$SANDBOX" bash "$1"
}

# --- ケース1: 隣接 mask-secrets.sh を解決してマスクする ---
make_sandbox yes
OUT=$(mcp_payload | run_mcp "$HOOKSBOX/mask-mcp-output.sh" 2>/dev/null)
assert_contains "$OUT" "updatedMCPToolOutput" "隣接解決: updatedMCPToolOutput を返す（基準版はハードコードパス不在でクラッシュ → RED）"
assert_contains "$OUT" "[MASKED]" "隣接解決: レスポンスがマスクされる"
assert_not_contains "$OUT" "$SECRET_TAIL" "隣接解決: 元トークンが返り値に残らない"

# --- ケース2: symlink 経由で起動してもマスクする ---
make_sandbox yes
LINKDIR=$(mktemp -d /tmp/fstack-mcplink-XXXXXX)
ln -s "$HOOKSBOX/mask-mcp-output.sh" "$LINKDIR/mmo.sh"
OUT=$(mcp_payload | run_mcp "$LINKDIR/mmo.sh" 2>/dev/null)
assert_contains "$OUT" "updatedMCPToolOutput" "symlink: updatedMCPToolOutput を返す（基準版は実体解決せず → RED）"
assert_contains "$OUT" "[MASKED]" "symlink: レスポンスがマスクされる"
assert_not_contains "$OUT" "$SECRET_TAIL" "symlink: 元トークンが返り値に残らない"

# --- ケース3: mask-secrets.sh が不在なら fail-closed（元レスポンスを返さない）---
make_sandbox no
OUT=$(mcp_payload | run_mcp "$HOOKSBOX/mask-mcp-output.sh" 2>/dev/null)
assert_contains "$OUT" "updatedMCPToolOutput" "fail-closed: 置換出力を返す（基準版は無出力=元レスポンス素通り → RED）"
assert_not_contains "$OUT" "$SECRET_TAIL" "fail-closed: 元シークレットが返り値に残らない"
assert_contains "$OUT" "masker_missing" "fail-closed: reason code が masker_missing（両不在・C2 正規語彙v2）"

# --- ケース4: 非 MCP ツールは素通り ---
make_sandbox yes
OUT=$(printf '{"tool_name":"Bash","tool_response":"result: %s done"}' "$SECRET" \
  | run_mcp "$HOOKSBOX/mask-mcp-output.sh" 2>/dev/null); RC=$?
assert_eq "0" "$RC" "非MCP: exit 0"
assert_empty "$OUT" "非MCP: 出力なし（素通り）"

# --- C1-2: masker が失敗したら fail-closed（B1: reason=masker_failed）---
make_sandbox_failmasker
OUT=$(mcp_payload | run_mcp "$HOOKSBOX/mask-mcp-output.sh" 2>/dev/null)
assert_contains "$OUT" "updatedMCPToolOutput" "C1-2: masker 失敗でも updatedMCPToolOutput を返す"
assert_contains "$OUT" "masker_failed" "C1-2: reason code が masker_failed"
assert_not_contains "$OUT" "$SECRET_TAIL" "C1-2: masker 失敗時に元シークレットが残らない（fail-closed）"
assert_eq "yes" "$(is_valid_json_str "$OUT")" "C1-2: fail-closed 出力が妥当な JSON"

# --- L7-1: 不正 payload（壊れ JSON）→ internal_error 秘匿を返す（fail-open にしない・L1）---
make_sandbox yes
OUT=$(printf '%s' '{this is not valid json' | run_mcp "$HOOKSBOX/mask-mcp-output.sh" 2>/dev/null)
assert_contains "$OUT" "updatedMCPToolOutput" "L7-1: 不正 payload でも updatedMCPToolOutput を返す（無出力 exit 0 でない）"
assert_contains "$OUT" "internal_error" "L7-1: reason code が internal_error"
assert_eq "yes" "$(is_valid_json_str "$OUT")" "L7-1: 秘匿出力が妥当な JSON"

# --- L7-2: HOME 未設定（env -u HOME）でもマスク出力を返す（ログは best-effort・L2）---
make_sandbox yes
OUT=$(mcp_payload | env -u HOME bash "$HOOKSBOX/mask-mcp-output.sh" 2>/dev/null)
assert_contains "$OUT" "updatedMCPToolOutput" "L7-2: HOME 未設定でも updatedMCPToolOutput を返す"
assert_contains "$OUT" "[MASKED]" "L7-2: HOME 未設定でもマスクが行われる"
assert_not_contains "$OUT" "$SECRET_TAIL" "L7-2: HOME 未設定でも元トークンが残らない"

finish
