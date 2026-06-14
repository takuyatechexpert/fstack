#!/bin/bash
# PostToolUse hook for Read tool
# 指定したナレッジディレクトリ配下のファイル読み込みのみをログに記録する。
# マッチ対象は CLAUDE_KNOWLEDGE_DIR で上書き可能（デフォルト: ~/knowledge）。

KNOWLEDGE_DIR="${CLAUDE_KNOWLEDGE_DIR:-$HOME/knowledge}"

INPUT=$(cat)
FILE_PATH=$(/opt/homebrew/bin/jq -r '.tool_input.file_path // ""' <<<"$INPUT")

if [[ "$FILE_PATH" == "$KNOWLEDGE_DIR"/* ]]; then
  BASENAME=$(basename "$FILE_PATH")
  mkdir -p ~/.claude/logs
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [KNOWLEDGE] READ ${BASENAME}" >> ~/.claude/logs/knowledge.log
fi
