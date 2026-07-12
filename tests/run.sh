#!/bin/bash
# hooks 再現テストランナー
#
# tests/test-*.sh を列挙実行し、pass/fail を集計する。失敗が1件でもあれば exit 1。
#
# 使い方:
#   bash tests/run.sh
#   HOOKS_DIR_UNDER_TEST=/path/to/hooks bash tests/run.sh   # 対象ディレクトリ差し替え
#
# 各テストは hook スクリプトに stdin で JSON payload を流し、
# stdout / stderr / exit code をアサートする。

DIR="$(cd "$(dirname "$0")" && pwd)"

total_files=0
failed_files=0

for t in "$DIR"/test-*.sh; do
  [ -f "$t" ] || continue
  total_files=$((total_files + 1))
  printf '==== %s ====\n' "$(basename "$t")"
  bash "$t"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    failed_files=$((failed_files + 1))
  fi
  printf '\n'
done

printf '======================================\n'
if [ "$failed_files" -eq 0 ]; then
  printf 'ALL GREEN: %d ファイル全て成功\n' "$total_files"
  exit 0
else
  printf 'RED: %d ファイル中 %d ファイルに失敗あり\n' "$total_files" "$failed_files"
  exit 1
fi
