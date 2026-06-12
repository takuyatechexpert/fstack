#!/bin/bash
# PostToolUse hook: MCP ツールの tool_response に混入したシークレットをマスクして
# LLM のコンテキストに渡す前に書き換える。
# Bash の tool_output は公式に書き換え不可のため、MCP ツール専用。
#
# 入力: PostToolUse イベントの JSON payload (stdin)
# 出力: マスクが発生した場合のみ hookSpecificOutput.updatedMCPToolOutput を返す

set -euo pipefail

PAYLOAD=$(cat)
TOOL_NAME=$(printf '%s' "$PAYLOAD" | jq -r '.tool_name // ""')

# MCP ツール以外はスキップ（safety net; matcher でも絞っているが念のため）
if [[ ! "$TOOL_NAME" =~ ^mcp__ ]]; then
  exit 0
fi

# tool_response を取得（存在しなければスキップ）
TOOL_RESPONSE=$(printf '%s' "$PAYLOAD" | jq '.tool_response')
if [ "$TOOL_RESPONSE" = "null" ] || [ -z "$TOOL_RESPONSE" ]; then
  exit 0
fi

# JSON 全体を文字列としてマスク処理
MASKED=$(printf '%s' "$TOOL_RESPONSE" | ~/.claude/hooks/mask-secrets.sh)

# 変化がなければスキップ（fast path）
if [ "$TOOL_RESPONSE" = "$MASKED" ]; then
  exit 0
fi

# マスクが発生したことをログに残す（値は残さない）
mkdir -p ~/.claude/logs
printf '[%s] [MCP_MASK] %s (secrets masked in response)\n' \
  "$(date '+%Y-%m-%d %H:%M:%S')" "$TOOL_NAME" >> ~/.claude/logs/mcp-mask.log

# updatedMCPToolOutput で置き換え
jq -n --argjson output "$MASKED" '{
  hookSpecificOutput: {
    hookEventName: "PostToolUse",
    updatedMCPToolOutput: $output
  }
}'
