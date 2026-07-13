#!/usr/bin/env bash
# PreCompact hook: 自動圧縮直前に handover 実行を Claude へ強く指示する
# stdin: JSON {session_id, transcript_path, cwd, trigger: "manual|auto"}
# stdout: JSON {additionalContext: "..."} で Claude セッションへ system-reminder を注入

JQ=$(command -v jq || echo "/opt/homebrew/bin/jq")

INPUT=$(cat)
TRIGGER=$(echo "$INPUT" | "$JQ" -r '.trigger // "auto"')
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

mkdir -p ~/.claude/logs
echo "[$TIMESTAMP] [PRE_COMPACT_HANDOVER] trigger:$TRIGGER" >> ~/.claude/logs/sessions.log

# 自動圧縮の場合のみ、handover 実行を強く指示
# manual 圧縮（ユーザーが /compact を明示的に実行）は意図的なので介入しない
if [ "$TRIGGER" = "auto" ]; then
  "$JQ" -n '{
    additionalContext: "🚨 AUTO-COMPACT IMMINENT — コンテキスト自動圧縮が直前に迫っています。圧縮で会話の細かい文脈が失われる前に、**いま即座に handover スキルを実行し、引き継ぎドキュメントを生成してください**。圧縮後では正確な引き継ぎ資料を作るのが困難になります。ユーザーの明示的な「圧縮していい」「handover不要」の指示がない限り、handover を実行してから作業を継続してください。"
  }'
fi

exit 0
