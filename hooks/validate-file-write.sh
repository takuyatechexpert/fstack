#!/bin/bash
# PreToolUse hook: Edit/Write の事前検証
# 機密ファイル・設定ファイルへの書き込みを検出する

set -euo pipefail

FILE_PATH=$(jq -r '.tool_input.file_path // ""')

deny_with_reason() {
  jq -n --arg reason "$1" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $reason
    }
  }'
  exit 0
}

ask_with_reason() {
  jq -n --arg reason "$1" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "ask",
      permissionDecisionReason: $reason
    }
  }'
  exit 0
}

# 1. .env ファイルへの書き込み（deny と二重防御）
#    ただし .env.example / .env.sample / .env.public はテンプレート・非シークレット用途のため許可
if echo "$FILE_PATH" | grep -qE '\.env\.(example|sample|public)$'; then
  :
elif echo "$FILE_PATH" | grep -qE '\.env(\.[a-zA-Z]+)?$'; then
  deny_with_reason ".env ファイルへの書き込みはブロックされています"
fi

# 2. シークレット関連ディレクトリ
if echo "$FILE_PATH" | grep -qE '/(\.ssh|\.gnupg|\.aws|secrets)/'; then
  deny_with_reason "機密ディレクトリへの書き込みはブロックされています"
fi

# 3. SSH 鍵・証明書ファイル
if echo "$FILE_PATH" | grep -qE '\.(pem|key|p12|pfx|jks)$'; then
  deny_with_reason "鍵/証明書ファイルへの書き込みはブロックされています"
fi

# 4. settings.json の書き換え試行（hooks 自体の改ざん防止）
if echo "$FILE_PATH" | grep -qE 'settings\.json$|settings\.local\.json$'; then
  ask_with_reason "Claude Code の設定ファイルを変更しようとしています。意図した操作ですか？"
fi

# 5. crontab / launchd plist
if echo "$FILE_PATH" | grep -qE '(crontab|\.plist)$|/LaunchAgents/|/LaunchDaemons/'; then
  deny_with_reason "スケジュールタスクの設定ファイルへの書き込みはブロックされています"
fi

# デフォルト: 許可（何も出力しない）
exit 0
