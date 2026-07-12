#!/bin/bash
# PostToolUse hook: MCP ツールの tool_response に混入したシークレットをマスクして
# LLM のコンテキストに渡す前に書き換える。
# Bash の tool_output は公式に書き換え不可のため、MCP ツール専用。
#
# 入力: PostToolUse イベントの JSON payload (stdin)
# 出力: マスクが発生した場合のみ hookSpecificOutput.updatedMCPToolOutput を返す
#
# fail-closed 方針（全エラー経路で元レスポンスを LLM へ渡さない）:
#   - payload の parse 失敗 / masker 不在 / masker 異常終了 / 実体解決失敗 / 最終 jq 失敗の
#     いずれでも、固定秘匿メッセージ（reason code 付き）を updatedMCPToolOutput で返す
#   - マスク後テキストが JSON として妥当でない場合も、部分マスクは渡さず秘匿する
#   - set -e には依存せず、各失敗を明示的にハンドリングする
#   - ログ追記は best-effort（HOME 未設定等でログ不能でも、マスク/秘匿出力の返却は継続する）

set -uo pipefail

# HOME 未設定でも set -u でクラッシュしないようフォールバック（ログは best-effort）
LOG_FILE="${HOME:-}/.claude/logs/mcp-mask.log"

# 固定秘匿メッセージを updatedMCPToolOutput として出力する（jq 非依存）。
# reason は固定集合 masker_missing/masker_failed/invalid_json/internal_error のみで、
# メッセージ本文に " や \ を含まないため JSON エスケープは不要。
emit_redaction() {
  printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","updatedMCPToolOutput":"[fstack mask-mcp-output] マスク処理を完了できなかったためレスポンスを秘匿しました (reason: %s)"}}\n' "$1"
}

# ログ追記（best-effort。失敗しても呼び出し側の処理は継続する）
append_log() {
  mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || return 1
  printf '[%s] %s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" "$2" >> "$LOG_FILE" 2>/dev/null || return 1
  return 0
}

# jq が無ければ payload 解析もマスク検証もできない → 安全側に秘匿
if ! command -v jq >/dev/null 2>&1; then
  append_log "[MCP_MASK_FALLBACK]" "(jq not found; response redacted)" || true
  emit_redaction "internal_error"
  exit 0
fi

PAYLOAD=$(cat)

# tool_name 抽出。jq の exit code を個別に捕捉し、parse 失敗（rc!=0）は fail-open にせず秘匿する
TOOL_NAME=$(printf '%s' "$PAYLOAD" | jq -r '.tool_name // ""' 2>/dev/null); TN_RC=$?
if [ "$TN_RC" -ne 0 ]; then
  append_log "[MCP_MASK_FALLBACK]" "(payload parse failed; response redacted)" || true
  emit_redaction "internal_error"
  exit 0
fi

# parse 成功かつ MCP ツール以外は正当なスキップ（matcher でも絞っているが念のため）
case "$TOOL_NAME" in
  mcp__*) ;;
  *) exit 0 ;;
esac

# ログ用に TOOL_NAME をサニタイズ（[A-Za-z0-9_-] 以外を除去し最大 128 文字）
SAFE_TOOL_NAME=$(printf '%s' "$TOOL_NAME" | LC_ALL=C tr -cd 'A-Za-z0-9_-' | cut -c1-128)

# tool_response 抽出。jq rc を捕捉し parse 失敗は秘匿。rc=0 で値が真に null/空なら正当なスキップ
TOOL_RESPONSE=$(printf '%s' "$PAYLOAD" | jq '.tool_response' 2>/dev/null); TR_RC=$?
if [ "$TR_RC" -ne 0 ]; then
  append_log "[MCP_MASK_FALLBACK]" "$SAFE_TOOL_NAME (tool_response parse failed; response redacted)" || true
  emit_redaction "internal_error"
  exit 0
fi
if [ "$TOOL_RESPONSE" = "null" ] || [ -z "$TOOL_RESPONSE" ]; then
  exit 0
fi

# 自身の実体位置を POSIX ポータブルに解決する（plain readlink + cd -P で symlink を追跡）。
# 解決に失敗した場合は fail-closed で秘匿する。
SELF="$0"
_guard=0
while [ -L "$SELF" ]; do
  _guard=$((_guard + 1))
  if [ "$_guard" -gt 40 ]; then SELF=""; break; fi
  _dir=$(cd -P "$(dirname "$SELF")" 2>/dev/null && pwd) || { SELF=""; break; }
  _link=$(readlink "$SELF") || { SELF=""; break; }
  case "$_link" in
    /*) SELF="$_link" ;;
    *)  SELF="$_dir/$_link" ;;
  esac
done
SCRIPT_DIR=""
if [ -n "$SELF" ]; then
  SCRIPT_DIR=$(cd -P "$(dirname "$SELF")" 2>/dev/null && pwd || printf '')
fi
if [ -z "$SCRIPT_DIR" ]; then
  append_log "[MCP_MASK_FALLBACK]" "$SAFE_TOOL_NAME (script dir resolution failed; response redacted)" || true
  emit_redaction "internal_error"
  exit 0
fi

# 2段フォールバック: 直接参照/symlink 名 → Option B の fstack- プレフィックス付きコピー
MASK_SCRIPT="${SCRIPT_DIR}/mask-secrets.sh"
if [ ! -f "$MASK_SCRIPT" ]; then
  MASK_SCRIPT="${SCRIPT_DIR}/fstack-mask-secrets.sh"
fi
if [ ! -f "$MASK_SCRIPT" ]; then
  append_log "[MCP_MASK_FALLBACK]" "$SAFE_TOOL_NAME (mask-secrets.sh not found; response redacted)" || true
  emit_redaction "masker_missing"
  exit 0
fi

# マスク実行。LC_ALL=C で不正バイト列による sed クラッシュを回避し、exit code を捕捉する
MASKED=$(printf '%s' "$TOOL_RESPONSE" | LC_ALL=C bash "$MASK_SCRIPT"); MASK_RC=$?
if [ "$MASK_RC" -ne 0 ]; then
  append_log "[MCP_MASK_FALLBACK]" "$SAFE_TOOL_NAME (masker exit ${MASK_RC}; response redacted)" || true
  emit_redaction "masker_failed"
  exit 0
fi

# 変化がなければスキップ（fast path）
if [ "$TOOL_RESPONSE" = "$MASKED" ]; then
  exit 0
fi

# マスク後テキストが JSON として妥当かを検証。壊れていたら部分マスクは渡さず秘匿する
if ! printf '%s' "$MASKED" | jq empty >/dev/null 2>&1; then
  append_log "[MCP_MASK_FALLBACK]" "$SAFE_TOOL_NAME (masked output invalid JSON; response redacted)" || true
  emit_redaction "invalid_json"
  exit 0
fi

# マスク発生を記録（値は残さない）。ログ追記は best-effort で、失敗しても秘匿せず続行する
append_log "[MCP_MASK]" "$SAFE_TOOL_NAME (secrets masked in response)" || true

# updatedMCPToolOutput で置換。巨大レスポンス対策として値渡しは stdin 経由（--argjson を使わない）
FINAL=$(printf '%s' "$MASKED" | jq -c '{
  hookSpecificOutput: {
    hookEventName: "PostToolUse",
    updatedMCPToolOutput: .
  }
}' 2>/dev/null); FINAL_RC=$?
if [ "$FINAL_RC" -ne 0 ] || [ -z "$FINAL" ]; then
  append_log "[MCP_MASK_FALLBACK]" "$SAFE_TOOL_NAME (final jq failed; response redacted)" || true
  emit_redaction "internal_error"
  exit 0
fi
printf '%s\n' "$FINAL"
exit 0
