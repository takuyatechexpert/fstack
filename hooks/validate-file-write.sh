#!/usr/bin/env bash
# PreToolUse hook: Edit/Write の事前検証
# 機密ファイル・設定ファイルへの書き込みを検出する

set -euo pipefail

# --- lib ブートストラップ（symlink 追跡で実体を解決し lib/common.sh を source）---
# 安全系（ブロック目的）hook のため、実体解決・lib source・jq・JSON parse の
# いずれの失敗も fail-closed（exit 2）。
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
SCRIPT_DIR=""
if [ -n "$_self" ]; then
  SCRIPT_DIR=$(cd -P "$(dirname "$_self")" 2>/dev/null && pwd || printf '')
fi
if [ -z "$SCRIPT_DIR" ] || [ ! -r "$SCRIPT_DIR/lib/common.sh" ]; then
  echo "[validate-file-write] 共通ライブラリ lib/common.sh を解決できません。安全のためブロックします。" >&2
  exit 2
fi
. "$SCRIPT_DIR/lib/common.sh"

# jq 不在は fail-closed
if ! fstack_have_jq; then
  echo "[validate-file-write] jq が見つかりません。安全のためブロックします。" >&2
  exit 2
fi

# stdin を一度だけ読み、JSON 妥当性を検証（不正 JSON は fail-closed）
INPUT=$(fstack_read_input)
if ! printf '%s' "$INPUT" | fstack_jq empty >/dev/null 2>&1; then
  echo "[validate-file-write] hook 入力の JSON 解析に失敗しました。安全のためブロックします。" >&2
  exit 2
fi

FILE_PATH=$(printf '%s' "$INPUT" | fstack_jq -r '.tool_input.file_path // ""')

# 1. .env ファイルへの書き込み（deny と二重防御）
#    ただし .env.example / .env.sample / .env.public はテンプレート・非シークレット用途のため許可
if echo "$FILE_PATH" | grep -qE '\.env\.(example|sample|public)$'; then
  :
elif echo "$FILE_PATH" | grep -qE '\.env(\.[a-zA-Z]+)?$'; then
  fstack_emit_deny ".env ファイルへの書き込みはブロックされています"
fi

# 2. シークレット関連ディレクトリ
if echo "$FILE_PATH" | grep -qE '/(\.ssh|\.gnupg|\.aws|secrets)/'; then
  fstack_emit_deny "機密ディレクトリへの書き込みはブロックされています"
fi

# 3. SSH 鍵・証明書ファイル
if echo "$FILE_PATH" | grep -qE '\.(pem|key|p12|pfx|jks)$'; then
  fstack_emit_deny "鍵/証明書ファイルへの書き込みはブロックされています"
fi

# 4. Claude Code 設定ファイル（.claude/settings.json）の書き換え試行（hooks 自体の改ざん防止）
#    file_path は展開済み絶対パスで来るため .claude 配下の設定のみに限定する
#    （任意 repo の settings.json や .vscode/settings.json には誤反応しない）
if echo "$FILE_PATH" | grep -qE '/\.claude/settings(\.local)?\.json$'; then
  fstack_emit_ask "Claude Code の設定ファイルを変更しようとしています。意図した操作ですか？"
fi

# 5. crontab / launchd plist
if echo "$FILE_PATH" | grep -qE '(crontab|\.plist)$|/LaunchAgents/|/LaunchDaemons/'; then
  fstack_emit_deny "スケジュールタスクの設定ファイルへの書き込みはブロックされています"
fi

# デフォルト: 許可（何も出力しない）
exit 0
