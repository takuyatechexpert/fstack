#!/bin/bash
# check-implementation-routing.sh
#
# Edit/Write/NotebookEdit を呼ぶ前に「直近 30 分以内に solo-with-verifier
# または orchestra-of-agents が起動されたか」を skills.log で確認する。
# 起動痕跡がなければ stderr で reminder を出す（blocking はしない）。
#
# 関連: rules/implementation-flow.md

set -euo pipefail

INPUT=$(cat)
TOOL_NAME=$(/opt/homebrew/bin/jq -r '.tool_name // ""' <<<"$INPUT")

case "$TOOL_NAME" in
  Edit | Write | NotebookEdit) ;;
  *) exit 0 ;;
esac

# 編集対象パスをチェック — メタ系・設定系・ノート系・履歴系は除外
FILE_PATH=$(/opt/homebrew/bin/jq -r '.tool_input.file_path // ""' <<<"$INPUT")
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

# 直近 30 分（1800 秒）以内に solo-with-verifier / orchestra-of-agents 起動があるかチェック
NOW=$(date +%s)
THRESHOLD=$((NOW - 1800))

RECENT_TRIGGER=0
# skills.log フォーマット: [YYYY-MM-DD HH:MM:SS] [SKILL] <name> | <args>
# tail で末尾 200 行に絞り、新しい順に確認
while IFS= read -r line; do
  TS_STR=$(awk -F'[][]' '{print $2}' <<<"$line")
  [ -z "$TS_STR" ] && continue
  LINE_TS=$(date -j -f "%Y-%m-%d %H:%M:%S" "$TS_STR" +%s 2>/dev/null || echo 0)
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
