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
#
# スキャン範囲:
#   commit = index の内容（:0:file）、push = HEAD ツリーの内容（HEAD:file）。
#   push で全履歴（過去コミット）を遡ることはしない（gitleaks 等の領域で本 hook の射程外）。
#
# 作業起点の解釈（既知の制限）:
#   コマンド先頭の `cd <path> &&` と最初の `git -C <path>` のみ解釈する。
#   サブシェル・変数展開・クォート付きパス等の複雑形は解釈せず .cwd 起点で続行する。

set -euo pipefail

# jq 不在は fail-closed（PreToolUse のブロッキングエラー）
if ! command -v jq >/dev/null 2>&1; then
  echo "[check-secret-patterns] jq が見つかりません。安全のためコミット/プッシュをブロックします。" >&2
  exit 2
fi

# stdin の JSON は一度だけ読む（jq を2回呼ぶと1回目が stdin を消費し CWD が空になる）
INPUT=$(cat)

# JSON parse に失敗したら fail-closed
if ! printf '%s' "$INPUT" | jq empty >/dev/null 2>&1; then
  echo "[check-secret-patterns] hook 入力の JSON 解析に失敗しました。安全のためブロックします。" >&2
  exit 2
fi

COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""')
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // ""')

# git commit または git push コマンドでなければスキップ
# 各 dash オプションに続く値トークン（例: -c user.name=x）も飛ばせる形にして、
# `git -c x=y commit` のようなオプション挟みも検出する（git log 等は誤検出しない）
if ! printf '%s' "$COMMAND" | grep -qE '(^|[[:space:]&;|])git([[:space:]]+-[^[:space:]]+([[:space:]]+[^-][^[:space:]]*)?)*[[:space:]]+(commit|push)([[:space:]]|$)'; then
  exit 0
fi

# プロジェクトルートを探す（.git がある場所）
# 進展ガード: dirname の結果が前回と変わらなくなったら解決不能として打ち切る
# （`dirname "."` → `.` のような無限ループを塞ぐ。M3）
find_project_root() {
  local dir="$1" prev=""
  while [ -n "$dir" ] && [ "$dir" != "/" ] && [ "$dir" != "$prev" ]; do
    if [ -d "$dir/.git" ]; then
      echo "$dir"
      return 0
    fi
    prev="$dir"
    dir=$(dirname "$dir")
  done
  return 1
}

# 作業起点を決定（L6: 先頭 cd と最初の -C を解釈。複雑形は .cwd 起点で続行）
ORIGIN="$CWD"
read -ra _TOK <<< "$COMMAND"
if [ "${_TOK[0]:-}" = "cd" ] && [ -n "${_TOK[1]:-}" ]; then
  case "${_TOK[1]}" in
    /*) ORIGIN="${_TOK[1]}" ;;
    *)  ORIGIN="${ORIGIN:+$ORIGIN/}${_TOK[1]}" ;;
  esac
fi
for ((i = 0; i < ${#_TOK[@]}; i++)); do
  if [ "${_TOK[$i]}" = "-C" ] && [ -n "${_TOK[$((i + 1))]:-}" ]; then
    case "${_TOK[$((i + 1))]}" in
      /*) ORIGIN="${_TOK[$((i + 1))]}" ;;
      *)  ORIGIN="${ORIGIN:+$ORIGIN/}${_TOK[$((i + 1))]}" ;;
    esac
    break
  fi
done

# L6-1: commit/push を検出したのに root が解決できなければ fail-closed（exit 2）。
# 従来の exit 0 素通り（空 CWD 含む。§10 A5 の exit 0 は §11 で上書き）を廃止する
if [ -z "$ORIGIN" ]; then
  echo "[check-secret-patterns] 作業ディレクトリを解決できません。安全のためブロックします。" >&2
  exit 2
fi

# M3: 相対起点（`git -C relative` 等）や `.` を cd -P で絶対パスに正規化してから使う。
# 正規化失敗（存在しないパス等）は fail-closed。dirname 無限ループの入口も同時に塞ぐ
ORIGIN=$(cd -P "$ORIGIN" 2>/dev/null && pwd) || {
  echo "[check-secret-patterns] 作業ディレクトリを解決できません。安全のためブロックします。" >&2
  exit 2
}

PROJECT_ROOT=$(find_project_root "$ORIGIN") || {
  echo "[check-secret-patterns] git リポジトリのルートを解決できません。安全のためブロックします。" >&2
  exit 2
}

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

# チェック対象ファイルと参照元を決定
# commit: index の内容（:0:file）、push: HEAD の内容（HEAD:file）をスキャンする。
# working tree でなく git の内容を見ることで「stage 後に working tree を戻す」バイパスを塞ぐ
GIT_REF=""
if printf '%s' "$COMMAND" | grep -qE '(^|[[:space:]&;|])git([[:space:]]+-[^[:space:]]+([[:space:]]+[^-][^[:space:]]*)?)*[[:space:]]+commit([[:space:]]|$)'; then
  FILES=$(cd "$PROJECT_ROOT" && git diff --cached --name-only 2>/dev/null || true)
  GIT_REF=":0:"
elif printf '%s' "$COMMAND" | grep -qE '(^|[[:space:]&;|])git([[:space:]]+-[^[:space:]]+([[:space:]]+[^-][^[:space:]]*)?)*[[:space:]]+push([[:space:]]|$)'; then
  # HEAD ツリーのファイルを列挙（git show HEAD:file と対象を揃える）
  FILES=$(cd "$PROJECT_ROOT" && git ls-tree -r HEAD --name-only 2>/dev/null || true)
  GIT_REF="HEAD:"
fi

if [ -z "${FILES:-}" ] || [ -z "$GIT_REF" ]; then
  exit 0
fi

# 各パターンでチェック（git の内容をスキャン。working tree は見ない）
NL=$'\n'
VIOLATIONS=""
for i in "${!PATTERNS[@]}"; do
  pattern="${PATTERNS[$i]}"
  n=$((i + 1))
  while IFS= read -r file; do
    [ -n "$file" ] || continue

    # secret-patterns.txt 自体はスキップ
    [[ "$file" == ".claude/secret-patterns.txt" ]] && continue

    # git の内容を取得（取得失敗したファイルはスキップ）
    content=$(cd "$PROJECT_ROOT" && git show "${GIT_REF}${file}" 2>/dev/null) || continue

    matches=$(printf '%s\n' "$content" | grep -nEI -- "$pattern" 2>/dev/null || true)
    if [ -n "$matches" ]; then
      while IFS= read -r match; do
        # 出力は "行番号:マッチ行" 形式。マッチ内容（＝シークレット値）と pattern 文字列は
        # トランスクリプトに焼き付くため出さず、行番号とパターン番号のみを残す
        linenum="${match%%:*}"
        VIOLATIONS="${VIOLATIONS}${NL}  ${file}:${linenum} (pattern #${n})"
      done <<< "$matches"
    fi
  done <<< "$FILES"
done

if [ -n "$VIOLATIONS" ]; then
  # printf のフォーマット解釈を避け、$'\n' 連結で理由文を組み立てる
  REASON="シークレットパターンが検出されました。コミット/プッシュをブロックします。${NL}${NL}検出箇所:${VIOLATIONS}${NL}${NL}パターン定義: ${PATTERNS_FILE}"
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
