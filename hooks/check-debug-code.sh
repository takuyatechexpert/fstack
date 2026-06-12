#!/bin/bash
# PostToolUse hook: Edit/Write 後に console.log / debugger の残存を検出

JQ=$(command -v jq || echo "/opt/homebrew/bin/jq")

file=$(echo "$CLAUDE_TOOL_INPUT" | "$JQ" -r '.file_path // empty')

# ファイルパスが空なら終了
[ -z "$file" ] && exit 0

# 対象拡張子のチェック
case "$file" in
  *.ts|*.tsx|*.js|*.jsx) ;;
  *) exit 0 ;;
esac

# ファイルが存在しなければ終了
[ -f "$file" ] || exit 0

# デバッグコードの検出
matches=$(grep -n -E 'console\.(log|debug|warn|error|info|trace)|debugger' "$file" 2>/dev/null)

if [ -n "$matches" ]; then
  echo "WARNING: debug code found in $file"
  echo "$matches"
fi
