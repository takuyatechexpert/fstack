#!/bin/bash
# lint-php.sh — PHP handler
#
# 責務: 引数で渡された PHP ファイルに対して Laravel Pint を実行する。
# --test でチェックのみ（自動整形はしない）。エラーがあれば非ゼロで終了。
# vendor/bin/pint が無い場合は no-op（未設定プロジェクトで誤ブロックしないため）。
# PHPStan 等の追加 linter が必要なら config.json の override で追加する。

[[ $# -eq 0 ]] && exit 0

ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)

PINT="$ROOT/vendor/bin/pint"
if [[ ! -x "$PINT" ]]; then
  exit 0
fi

"$PINT" --test "$@"
