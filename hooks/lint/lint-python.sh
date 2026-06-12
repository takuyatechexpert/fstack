#!/bin/bash
# lint-python.sh — Python handler
#
# 責務: 引数で渡された Python ファイルに対して Ruff を実行する。
# ruff が PATH に無い場合は no-op（未設定環境で誤ブロックしないため）。
# mypy 等の型チェックが必要なら config.json の override で追加する。

[[ $# -eq 0 ]] && exit 0

if ! command -v ruff >/dev/null 2>&1; then
  exit 0
fi

ruff check "$@"
