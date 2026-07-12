#!/bin/bash
# T4: mask-secrets.sh の再現テスト
#
# 契約（design-contract §4 T4 / §7 正規語彙）:
#   - JSON 入力をマスクしても JSON 構造を壊さない（マスク後も jq empty が通る）
#   - 値が [MASKED] に置換され、元のシークレット値が消えること
#   - プレーンテキストの既存マスク（Bearer / JWT / ghp_ / xoxb / AKIA）が退行しないこと
#   - マスクトークンは [MASKED] / [MASKED_JWT] / [MASKED_AWS_KEY] を維持
#
# 基準版 (46938a3) は "key": "value" 形式で引用符構造を食い、
#   {"api_key": "..."} → {"api_key"=[MASKED]"} のように JSON を破壊する。

TEST_NAME="mask-secrets"
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

HOOK="$HOOKS_DIR/mask-secrets.sh"
mask() { printf '%s' "$1" | bash "$HOOK"; }
is_valid_json() { printf '%s' "$1" | jq empty >/dev/null 2>&1 && echo yes || echo no; }

# --- ケース1: JSON( api_key ) → マスク後も jq empty が通る ---
OUT=$(mask '{"api_key": "SECRETVALUE1234567890"}')
assert_eq "yes" "$(is_valid_json "$OUT")" "JSON api_key: マスク後も妥当な JSON（基準版は構造破壊 → RED）"
assert_contains "$OUT" "[MASKED]" "JSON api_key: [MASKED] に置換される"
assert_not_contains "$OUT" "SECRETVALUE1234567890" "JSON api_key: 元の値が消える"

# --- ケース2: JSON( password ) → マスク後も jq empty が通る ---
OUT=$(mask '{"password": "hunter2secretvalue"}')
assert_eq "yes" "$(is_valid_json "$OUT")" "JSON password: マスク後も妥当な JSON（基準版は構造破壊 → RED）"
assert_not_contains "$OUT" "hunter2secretvalue" "JSON password: 元の値が消える"

# --- ケース3: ネストを含む代表的な JSON オブジェクト ---
OUT=$(mask '{"api_key":"AKEYVALUE1234567890","data":{"access_token":"ATOKVALUE1234567890"},"msg":"hello world"}')
assert_eq "yes" "$(is_valid_json "$OUT")" "JSON nested: マスク後も妥当な JSON（基準版は構造破壊 → RED）"
assert_not_contains "$OUT" "AKEYVALUE1234567890" "JSON nested: api_key の値が消える"
assert_not_contains "$OUT" "ATOKVALUE1234567890" "JSON nested: access_token の値が消える"
assert_contains "$OUT" "hello world" "JSON nested: 非シークレット値は保持される"

# --- ケース4: シークレットを含まない JSON は素通り（妥当なまま）---
OUT=$(mask '{"status":"ok","count":3}')
assert_eq "yes" "$(is_valid_json "$OUT")" "JSON clean: 妥当なまま"
assert_contains "$OUT" "ok" "JSON clean: 中身が保持される"

# --- ケース5〜9: プレーンテキストの既存マスク（退行防止・基準版でも GREEN）---
OUT=$(mask 'header: Bearer abcdefghijklmnop1234 end')
assert_contains "$OUT" "Bearer [MASKED]" "plain Bearer: マスクされる"
assert_not_contains "$OUT" "abcdefghijklmnop1234" "plain Bearer: 元トークンが消える"

OUT=$(mask 'token=eyJAAAAAAAAAAAAAAAAAAAAAAAA.BBBBBBBBBBBBBBBBBBBBBBBB.CCCCCCCCCCCCCCCCCCCCCCCC end')
assert_contains "$OUT" "[MASKED_JWT]" "plain JWT: [MASKED_JWT] に置換"
assert_not_contains "$OUT" "BBBBBBBBBBBBBBBBBBBBBBBB" "plain JWT: 元セグメントが消える"

OUT=$(mask 'gh: ghp_TESTDUMMYAAAABBBBCCCCDDDDEEEEFFFF end')
assert_contains "$OUT" "ghp_[MASKED]" "plain ghp_: マスクされる"
assert_not_contains "$OUT" "TESTDUMMYAAAABBBBCCCCDDDDEEEEFFFF" "plain ghp_: 元トークンが消える"

OUT=$(mask 'slack: xoxb-TESTDUMMY1234567890 end')
assert_contains "$OUT" "xoxb-[MASKED]" "plain xoxb: マスクされる"

OUT=$(mask 'aws: AKIATESTDUMMY0000ABC end')
assert_contains "$OUT" "AKIA[MASKED_AWS_KEY]" "plain AKIA: [MASKED_AWS_KEY] に置換"

# --- C1-1: エスケープ引用符入り password JSON → 断片リークなし（B2: ([^"\\]|\\.) 文字クラス）---
# 値は PWSEGA"PWSEGB"PWSEGC12345（JSON 内で \" エスケープ）。
# 素朴な [^"]* ルールだと最初の \" で止まり PWSEGB 以降が露出する。
esc_json='{"password": "PWSEGA\"PWSEGB\"PWSEGC12345"}'
OUT=$(mask "$esc_json")
assert_eq "yes" "$(is_valid_json "$OUT")" "C1-1: エスケープ引用符入りでもマスク後は妥当な JSON"
assert_not_contains "$OUT" "PWSEGB" "C1-1: エスケープ引用符後の断片が残らない"
assert_not_contains "$OUT" "PWSEGC12345" "C1-1: 値末尾の断片が残らない"
assert_contains "$OUT" "[MASKED]" "C1-1: 値が [MASKED] に置換される"

# --- L7-3: エスケープ JSON 形式（content[].text にシリアライズ済み JSON）をマスク（L3）---
# MCP の content[].text 標準形: 外側 JSON の文字列値に \"api_key\":\"...\" が入る（1段ネスト）
esc_nested='{"text":"{\"api_key\":\"DUMMYSECRETVALUE123456\"}"}'
OUT=$(mask "$esc_nested")
assert_eq "yes" "$(is_valid_json "$OUT")" "L7-3: マスク後も外側 JSON が妥当"
assert_not_contains "$OUT" "DUMMYSECRETVALUE123456" "L7-3: エスケープ JSON 内の api_key 値が残らない"
assert_contains "$OUT" "[MASKED]" "L7-3: エスケープ JSON 内の値が [MASKED] に置換される"

# --- M4-1: 値内に \" / \\ を含むエスケープ JSON（content[].text の1段ネスト）→ 全体マスク（M1）---
# 最深の password 値 = PWHEADzz"SEKTAIL99（"を含む）。外側 JSON では \\\" として二重エスケープされる。
# 素朴に \" で値を終端すると PWHEADzz で切れて SEKTAIL99 が露出する。M1 は値全体をマスクする。
esc_deep='{"text":"{\"password\":\"PWHEADzz\\\"SEKTAIL99\"}"}'
assert_eq "yes" "$(is_valid_json "$esc_deep")" "M4-1: 入力フィクスチャ自体が妥当な JSON（前提）"
OUT=$(mask "$esc_deep")
assert_eq "yes" "$(is_valid_json "$OUT")" "M4-1: マスク後も外側 JSON が妥当"
assert_not_contains "$OUT" "PWHEADzz" "M4-1: 値先頭の断片が残らない"
assert_not_contains "$OUT" "SEKTAIL99" "M4-1: エスケープ引用符後の断片が残らない"
assert_contains "$OUT" "[MASKED]" "M4-1: 値全体が [MASKED] に置換される"

finish
