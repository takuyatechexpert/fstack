#!/usr/bin/env bash
# PostCompact hook: ログ記録 + 自動圧縮後の handover 強制指示
# stdin: JSON {trigger: "manual|auto", compact_summary: "..."}
# stdout: JSON {additionalContext: "..."} で Claude セッションへ system-reminder を注入

JQ=$(command -v jq || echo "/opt/homebrew/bin/jq")

INPUT=$(cat)
TRIGGER=$(echo "$INPUT" | "$JQ" -r '.trigger // ""')
SUMMARY=$(echo "$INPUT" | "$JQ" -r '.compact_summary // ""')
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# ログ記録
mkdir -p ~/.claude/logs
echo "[$TIMESTAMP] [POST_COMPACT] trigger:$TRIGGER | $SUMMARY" >> ~/.claude/logs/sessions.log

# 自動圧縮の場合: Claude に handover 実行を強く指示する additionalContext を返す
if [ "$TRIGGER" = "auto" ]; then
  "$JQ" -n '{
    additionalContext: "⚠️ AUTO-COMPACT EXECUTED — 自動圧縮が実行されました。会話の細かい文脈が失われている可能性が高いです。**いま即座に handover スキルを実行し、現在判明している情報だけでも引き継ぎドキュメントを生成してください**。圧縮済みサマリーから読み取れる範囲で（タスク概要・残タスク・関連ファイル・直近の判断）を整理し、次セッション用の handover ファイルを保存してください。ユーザーが明示的に「handover不要」と言わない限り、handover を作成してから作業を再開してください。"
  }'
fi

exit 0
