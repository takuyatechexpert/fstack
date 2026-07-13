#!/usr/bin/env bash
# check-implementation-routing.sh
#
# Edit/Write/NotebookEdit を呼ぶ前に「直近 30 分以内に solo-with-verifier
# または orchestra-of-agents が起動されたか」を skills.log で確認する。
# 起動痕跡がなければ stderr で reminder を出す（blocking はしない）。
#
# 関連: rules/implementation-flow.md
#
# 非ブロッキング advisory のため set -euo pipefail は使わない。
# set -e 下だと grep/date 等の非ゼロ終了で誤って hook が落ち、reminder だけの
# 想定を超えて編集を妨げるリスクがあるため、best-effort continue を明示的に保つ。

# --- lib ブートストラップ: 実体ディレクトリを解決して lib/common.sh を source ---
# symlink 運用でも実体位置の lib/ を辿れるよう POSIX ポータブルに解決（readlink -f 非依存）。
# 本 hook は非ブロッキング advisory のため、lib/jq 解決失敗は best-effort で exit 0 continue。
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
# lib 未ロード or jq 不在なら advisory を諦めて素通り（ブロックしないのが正しい挙動）
if [ "$_fstack_lib_loaded" != 1 ] || ! fstack_have_jq; then
  exit 0
fi

# 30 分（1800 秒）のしきい値は FSTACK_ROUTING_WINDOW_SEC で上書き可
ROUTING_WINDOW_SEC="${FSTACK_ROUTING_WINDOW_SEC:-1800}"

INPUT=$(fstack_read_input)
TOOL_NAME=$(fstack_jq -r '.tool_name // ""' <<<"$INPUT")

case "$TOOL_NAME" in
  Edit | Write | NotebookEdit) ;;
  *) exit 0 ;;
esac

# 編集対象パスをチェック — メタ系・設定系・ノート系・履歴系は除外
FILE_PATH=$(fstack_jq -r '.tool_input.file_path // ""' <<<"$INPUT")
case "$FILE_PATH" in
  */.claude/* | */MEMORY.md | */memory/*.md | */.todo/* \
    | */handovers/* | */knowledge/*.md | */docs/*.md | */README*.md \
    | */CLAUDE.md | */prompts/*.md | */runs/*.md | */design/*.md \
    | */ONBOARDING*.md | */CHANGELOG.md | *.json | *.yaml | *.yml \
    | *.toml | *.lock | *.txt | *.ndjson | *.jsonl | *.log | *.env*)
    exit 0
    ;;
esac

SKILLS_LOG="$HOME/.claude/logs/skills.log"
if [ ! -f "$SKILLS_LOG" ]; then
  # ログがなければスキップ
  exit 0
fi

# 直近 ROUTING_WINDOW_SEC 秒以内に solo-with-verifier / orchestra-of-agents 起動があるかチェック
NOW=$(date +%s)
THRESHOLD=$((NOW - ROUTING_WINDOW_SEC))

RECENT_TRIGGER=0
# skills.log フォーマット: [YYYY-MM-DD HH:MM:SS] [SKILL] <name> | <args>
# tail で末尾 200 行に絞り、新しい順に確認
while IFS= read -r line; do
  TS_STR=$(awk -F'[][]' '{print $2}' <<<"$line")
  [ -z "$TS_STR" ] && continue
  LINE_TS=$(fstack_epoch_from_datetime "$TS_STR")
  [ "$LINE_TS" -lt "$THRESHOLD" ] && continue
  if grep -qE "solo-with-verifier|orchestra-of-agents" <<<"$line"; then
    RECENT_TRIGGER=1
    break
  fi
done < <(tail -200 "$SKILLS_LOG")

if [ "$RECENT_TRIGGER" -eq 1 ]; then
  exit 0
fi

# 警告: stderr に reminder（blocking しない）
cat >&2 <<EOF
[implementation-task-routing] 直近 30 分以内に solo-with-verifier / orchestra-of-agents の起動痕跡がありません。

判定:
  - typo / 1 行修正 / コメント変更のみ → 直接実装 OK
  - 1〜3 ファイル / 50 行以下 → /solo-with-verifier
  - 5 タスク以上 / 横断的変更 → /orchestra-of-agents

極小スコープでなければスキル起動を検討してください。
（このメッセージは reminder です。極小スコープなら無視して続行可能。）
対象ファイル: $FILE_PATH
EOF

exit 0
