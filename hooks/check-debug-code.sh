#!/bin/bash
# PostToolUse hook: Edit/Write 後に console.log / debugger の残存を検出

# --- lib ブートストラップ: 実体ディレクトリを解決して lib/common.sh を source ---
# symlink 運用でも実体位置の lib/ を辿れるよう POSIX ポータブルに解決（readlink -f 非依存）。
# 警告系 PostToolUse のため lib/jq 解決失敗は best-effort で exit 0 continue（検出しないだけ）。
_self="$0"
_guard=0
while [ -L "$_self" ]; do
  _guard=$((_guard + 1))
  if [ "$_guard" -gt 40 ]; then _self=""; break; fi
  _dir=$(cd -P "$(dirname "$_self")" 2>/dev/null && pwd) || { _self=""; break; }
  _link=$(readlink "$_self") || { _self=""; break; }
  case "$_link" in
    /*) _self="$_link" ;;
    *)  _self="$_dir/$_link" ;;
  esac
done
FSTACK_HOOKS_DIR=""
if [ -n "$_self" ]; then
  FSTACK_HOOKS_DIR=$(cd -P "$(dirname "$_self")" 2>/dev/null && pwd || printf '')
fi
_fstack_lib_loaded=0
if [ -n "$FSTACK_HOOKS_DIR" ] && [ -f "$FSTACK_HOOKS_DIR/lib/common.sh" ]; then
  # shellcheck source=/dev/null
  if . "$FSTACK_HOOKS_DIR/lib/common.sh"; then _fstack_lib_loaded=1; fi
fi
if [ "$_fstack_lib_loaded" != 1 ] || ! fstack_have_jq; then
  exit 0
fi

# 入力は stdin の JSON（$CLAUDE_TOOL_INPUT は存在しない）
INPUT=$(fstack_read_input)
file=$(printf '%s' "$INPUT" | fstack_jq -r '.tool_input.file_path // empty')

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
