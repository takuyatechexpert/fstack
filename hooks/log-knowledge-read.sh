#!/bin/bash
# PostToolUse hook for Read tool
# 指定したナレッジディレクトリ配下のファイル読み込みのみをログに記録する。
# マッチ対象は CLAUDE_KNOWLEDGE_DIR で上書き可能（デフォルト: ~/knowledge）。
# ログ先は fstack_log_dir（FSTACK_LOG_DIR 既定 ~/.claude/logs）。

KNOWLEDGE_DIR="${CLAUDE_KNOWLEDGE_DIR:-$HOME/knowledge}"

# --- lib ブートストラップ: 実体ディレクトリを解決して lib/common.sh を source ---
# symlink 運用でも実体位置の lib/ を辿れるよう POSIX ポータブルに解決（readlink -f 非依存）。
# 記録系 PostToolUse のため lib/jq 解決失敗は best-effort で exit 0 continue（記録しないだけ）。
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

INPUT=$(fstack_read_input)
FILE_PATH=$(fstack_jq -r '.tool_input.file_path // ""' <<<"$INPUT")

if [[ "$FILE_PATH" == "$KNOWLEDGE_DIR"/* ]]; then
  BASENAME=$(basename "$FILE_PATH")
  LOG_DIR=$(fstack_log_dir)
  mkdir -p "$LOG_DIR"
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [KNOWLEDGE] READ ${BASENAME}" >> "$LOG_DIR/knowledge.log"
fi
