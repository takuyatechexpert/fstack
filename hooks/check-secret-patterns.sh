#!/bin/bash
# PreToolUse hook: git commit/push 前にプロジェクト固有のシークレットパターンをチェック
# .claude/secret-patterns.txt が存在するプロジェクトでのみ動作する
#
# secret-patterns.txt 例:
#   # 1行1パターン、# で始まる行はコメント
#   sk_live_[A-Za-z0-9]{24,}
#   ghp_[A-Za-z0-9]{30,}
#
# Usage:
#   ~/.claude/settings.json の PreToolUse > matcher: "Bash" にぶら下げる
#   詳細は同梱の README.md を参照

set -euo pipefail

COMMAND=$(jq -r '.tool_input.command // ""')
CWD=$(jq -r '.cwd // ""')

# git commit または git push コマンドでなければスキップ
if ! echo "$COMMAND" | grep -qE '\bgit\s+(commit|push)\b'; then
  exit 0
fi

# プロジェクトルートを探す（.git がある場所）
find_project_root() {
  local dir="$1"
  while [ "$dir" != "/" ]; do
    if [ -d "$dir/.git" ]; then
      echo "$dir"
      return 0
    fi
    dir=$(dirname "$dir")
  done
  return 1
}

PROJECT_ROOT=$(find_project_root "$CWD") || exit 0

PATTERNS_FILE="$PROJECT_ROOT/.claude/secret-patterns.txt"

# パターンファイルがなければスキップ
if [ ! -f "$PATTERNS_FILE" ]; then
  exit 0
fi

# パターンを読み込み（空行とコメント行を除外）
PATTERNS=()
while IFS= read -r line; do
  [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
  PATTERNS+=("$line")
done < "$PATTERNS_FILE"

if [ ${#PATTERNS[@]} -eq 0 ]; then
  exit 0
fi

# チェック対象ファイルを決定
if echo "$COMMAND" | grep -qE '\bgit\s+commit\b'; then
  # git commit: ステージされたファイルをチェック
  FILES=$(cd "$PROJECT_ROOT" && git diff --cached --name-only 2>/dev/null || true)
elif echo "$COMMAND" | grep -qE '\bgit\s+push\b'; then
  # git push: 追跡されている全ファイルをチェック
  FILES=$(cd "$PROJECT_ROOT" && git ls-files 2>/dev/null || true)
fi

if [ -z "$FILES" ]; then
  exit 0
fi

# 各パターンでチェック
VIOLATIONS=""
for pattern in "${PATTERNS[@]}"; do
  while IFS= read -r file; do
    filepath="$PROJECT_ROOT/$file"
    [ -f "$filepath" ] || continue

    # secret-patterns.txt 自体はスキップ
    [[ "$file" == ".claude/secret-patterns.txt" ]] && continue

    matches=$(grep -n "$pattern" "$filepath" 2>/dev/null || true)
    if [ -n "$matches" ]; then
      while IFS= read -r match; do
        VIOLATIONS="${VIOLATIONS}\n  ${file}:${match} (pattern: ${pattern})"
      done <<< "$matches"
    fi
  done <<< "$FILES"
done

if [ -n "$VIOLATIONS" ]; then
  REASON=$(printf "シークレットパターンが検出されました。コミット/プッシュをブロックします。\n\n検出箇所:${VIOLATIONS}\n\nパターン定義: ${PATTERNS_FILE}")
  jq -n --arg reason "$REASON" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $reason
    }
  }'
  exit 0
fi

exit 0
