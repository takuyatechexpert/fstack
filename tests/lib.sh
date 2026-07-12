#!/bin/bash
# 共通テストヘルパー（bash 3.2 互換）
#
# 各 test-*.sh はこのファイルを source して assert_* を使う。
# 対象 hooks ディレクトリは環境変数 HOOKS_DIR_UNDER_TEST で差し替え可能
# （未設定時はリポジトリの hooks/ を使う）。

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$LIB_DIR/.." && pwd)"
HOOKS_DIR="${HOOKS_DIR_UNDER_TEST:-$REPO_ROOT/hooks}"

TESTS_RUN=0
TESTS_FAILED=0

_pass() {
  TESTS_RUN=$((TESTS_RUN + 1))
  printf '  PASS %s\n' "$1"
}

_fail() {
  TESTS_RUN=$((TESTS_RUN + 1))
  TESTS_FAILED=$((TESTS_FAILED + 1))
  printf '  FAIL %s\n' "$1"
  [ -n "$2" ] && printf '       %s\n' "$2"
}

# assert_eq <expected> <actual> <message>
assert_eq() {
  if [ "$1" = "$2" ]; then
    _pass "$3"
  else
    _fail "$3" "expected [$1] but got [$2]"
  fi
}

# assert_contains <haystack> <needle> <message>
assert_contains() {
  case "$1" in
    *"$2"*) _pass "$3" ;;
    *) _fail "$3" "expected output to contain: $2" ;;
  esac
}

# assert_not_contains <haystack> <needle> <message>
assert_not_contains() {
  case "$1" in
    *"$2"*) _fail "$3" "output unexpectedly contained: $2" ;;
    *) _pass "$3" ;;
  esac
}

# assert_nonempty <value> <message>
assert_nonempty() {
  if [ -n "$1" ]; then
    _pass "$2"
  else
    _fail "$2" "expected non-empty value"
  fi
}

# assert_ne <not-expected> <actual> <message>
assert_ne() {
  if [ "$1" != "$2" ]; then
    _pass "$3"
  else
    _fail "$3" "expected value to differ from [$1]"
  fi
}

# assert_empty <value> <message>
assert_empty() {
  if [ -z "$1" ]; then
    _pass "$2"
  else
    _fail "$2" "expected empty but got [$1]"
  fi
}

# jq だけを除いた PATH 用の shim bin ディレクトリを作って echo する。
# この環境には /usr/bin/jq も存在するため、単純な PATH 制限では jq を除去できない。
# hook が使う他コマンド（cat/grep/git/sed/readlink/dirname/head 等）は実体へ symlink する。
make_jqless_bin() {
  local shim t p
  shim=$(mktemp -d /tmp/fstack-jqless-XXXXXX)
  for t in cat grep egrep sed git dirname basename readlink head tail date tr sort wc env bash sh; do
    p=$(command -v "$t" 2>/dev/null) && ln -s "$p" "$shim/$t" 2>/dev/null
  done
  printf '%s' "$shim"
}

# テスト終了時に呼ぶ。失敗が1件でもあれば exit 1。
finish() {
  printf -- '---- %s: %d 件中 %d 件失敗 ----\n' "${TEST_NAME:-test}" "$TESTS_RUN" "$TESTS_FAILED"
  [ "$TESTS_FAILED" -eq 0 ]
}
