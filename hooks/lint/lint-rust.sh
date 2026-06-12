#!/bin/bash
# lint-rust.sh — Rust handler
#
# 責務: Rust ファイルがステージされている時に cargo clippy を実行する。
# 注意: clippy はクレート単位でしか動かないため、引数のファイル一覧は無視して
#       リポジトリルートで「全体 clippy」を実行する（他言語の「差分のみ」方針とは異なる）。
# Cargo.toml が見つからない / cargo 未インストールの場合は no-op。

[[ $# -eq 0 ]] && exit 0

ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)

if [[ ! -f "$ROOT/Cargo.toml" ]]; then
  exit 0
fi

if ! command -v cargo >/dev/null 2>&1; then
  exit 0
fi

(cd "$ROOT" && cargo clippy --all-targets --quiet -- -D warnings)
