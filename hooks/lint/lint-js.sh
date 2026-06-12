#!/bin/bash
# lint-js.sh — JS/TS handler
#
# 責務: 引数で渡された JS/TS ファイルに対して ESLint を実行する。
# プロジェクト直下の node_modules/.bin/eslint が存在する場合のみ実行。
# 見つからない場合は no-op（成功扱い）— 未設定プロジェクトで誤ブロックしないため。
# サブディレクトリ配置（例: repo/src/node_modules/.bin/eslint）は override で対応する。

[[ $# -eq 0 ]] && exit 0

ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)

ESLINT="$ROOT/node_modules/.bin/eslint"
if [[ ! -x "$ESLINT" ]]; then
  exit 0
fi

"$ESLINT" --no-error-on-unmatched-pattern "$@"
