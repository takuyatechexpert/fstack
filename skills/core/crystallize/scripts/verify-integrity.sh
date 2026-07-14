#!/usr/bin/env bash
# crystallize Phase 5: セルフ検証
# サイズ規律・インデックス整合性（MEMORY.md / KNOWLEDGE.md ⇄ 実ファイル）を機械判定する。
# 終了コード = 致命的不整合（✗）の件数。⚠ は手動確認推奨（非致命）。
#
# ナレッジベースの場所は、環境変数 KNOWLEDGE_DIR または第1引数で上書きできる。
# 既定は ~/.claude/knowledge。
#   KNOWLEDGE_DIR=/path/to/knowledge bash verify-integrity.sh
#   bash verify-integrity.sh /path/to/knowledge
set -u

KNOWLEDGE_DIR="${KNOWLEDGE_DIR:-${1:-$HOME/.claude/knowledge}}"
ERRORS=0
fail() { echo "✗ $1"; ERRORS=$((ERRORS + 1)); }
warn() { echo "⚠ $1"; }

echo "=== 1. ナレッジ サイズ規律 ==="
if [ ! -d "$KNOWLEDGE_DIR" ]; then
  fail "ナレッジディレクトリが存在しない: $KNOWLEDGE_DIR"
else
  always_total=0
  for name in user-profile.md work-patterns.md collaboration.md; do
    f="$KNOWLEDGE_DIR/$name"
    [ -f "$f" ] && always_total=$((always_total + $(wc -l < "$f")))
  done
  echo "常時読み込み合計: ${always_total}行 / 上限120"
  [ "$always_total" -gt 120 ] && fail "常時読み込み3ファイルが上限120行を超過"
  for f in "$KNOWLEDGE_DIR"/*.md; do
    [ -e "$f" ] || continue
    base=$(basename "$f")
    case "$base" in
      KNOWLEDGE.md|user-profile.md|work-patterns.md|collaboration.md) continue ;;
    esac
    lines=$(wc -l < "$f")
    echo "遅延: $base ${lines}行 / 上限100"
    [ "$lines" -gt 100 ] && fail "$base が上限100行を超過"
  done
fi

echo "=== 2. KNOWLEDGE.md インデックス整合性 ==="
kidx="$KNOWLEDGE_DIR/KNOWLEDGE.md"
if [ -f "$kidx" ]; then
  while IFS= read -r ref; do
    case "$ref" in http*) continue ;; esac
    [ -e "$KNOWLEDGE_DIR/$ref" ] || fail "KNOWLEDGE.md の参照切れ: $ref"
  done < <(grep -oE '\]\([^)]+\)' "$kidx" | sed -E 's/\]\((.*)\)/\1/')
  for f in "$KNOWLEDGE_DIR"/*.md; do
    [ -e "$f" ] || continue
    base=$(basename "$f")
    [ "$base" = "KNOWLEDGE.md" ] && continue
    grep -q "$base" "$kidx" || warn "KNOWLEDGE.md 未掲載: $base"
  done
else
  fail "KNOWLEDGE.md が存在しない: $kidx"
fi

echo "=== 3. MEMORY.md インデックス整合性 ==="
for midx in "$HOME"/.claude/projects/*/memory/MEMORY.md; do
  [ -f "$midx" ] || continue
  dir=$(dirname "$midx")
  short="${dir#"$HOME"/.claude/projects/}"
  while IFS= read -r ref; do
    case "$ref" in http*|/*) continue ;; esac
    [ -e "$dir/$ref" ] || fail "MEMORY.md の参照切れ: $short -> $ref"
  done < <(grep -oE '\]\([^)]+\.md\)' "$midx" | sed -E 's/\]\((.*)\)/\1/')
  for f in "$dir"/*.md; do
    [ -e "$f" ] || continue
    base=$(basename "$f")
    [ "$base" = "MEMORY.md" ] && continue
    grep -q "$base" "$midx" || warn "MEMORY.md 未掲載: $short/$base"
  done
done

echo ""
if [ "$ERRORS" -eq 0 ]; then
  echo "OK: 致命的な不整合なし（⚠ は手動確認を推奨）"
else
  echo "NG: ✗ ${ERRORS}件。修正してから完了とすること"
fi
exit "$ERRORS"
