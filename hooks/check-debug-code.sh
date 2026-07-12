#!/bin/bash
# PostToolUse hook: Edit/Write 後に console.log / debugger の残存を検出

JQ=$(command -v jq || echo "/opt/homebrew/bin/jq")

# 入力は stdin の JSON（$CLAUDE_TOOL_INPUT は存在しない）
INPUT=$(cat)
file=$(echo "$INPUT" | "$JQ" -r '.tool_input.file_path // empty')

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

# PostToolUse は実行済みでブロック不可。警告を Claude に届けるには stderr + exit 2。
# マッチ行の内容は出さず、ファイルパスと行番号リストのみを渡す（行内容の露出防止）
if [ -n "$matches" ]; then
  lines=$(printf '%s\n' "$matches" | awk -F: 'NR>1{printf ", "} {printf "%s", $1}')
  echo "WARNING: debug code found in $file (lines: $lines)" >&2
  exit 2
fi

exit 0
