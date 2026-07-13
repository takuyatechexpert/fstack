---
name: review-hooks
description: "Claude Code の hooks 設定をレビュー・最適化するスキル。設定確認・ログ動作チェック・未設定イベント提案・settings.json 更新を行う。「hooks確認」「フック見直し」「review-hooks」「フック最適化」で使用する。以下では起動しない: スキル本体の作成・改善（my-skill-creator / skill-auditor）、hook が生成するログの集計。"
---

# review-hooks スキル

`~/.claude/settings.json` の hooks 設定をレビューし、問題検出・未設定イベント提案・settings.json 更新を行う。

## 基本原則

1. **更新前に必ずバックアップ** — `cp ~/.claude/settings.json ~/.claude/settings.json.bak-$(date +%s)` で退避してから編集する
2. **現状確認の 3 コールは並列実行** — Phase 1 の 1-1/1-2/1-3 を**同一メッセージ内で Bash tool を 3 回並列呼び出し**する
3. **settings.json は Edit tool で差分編集** — 既存設定の破壊を防ぐため Write tool は使用しない
4. **更新後に JSON 構文とフックコマンドを再検証** — `jq empty` と jq テスト入力の 2 段階で確認する
5. **反映は次回セッション起動時** — ユーザーに明示する

## 参照ドキュメント

- フックイベント一覧: `references/hook-events.md`
- jq 記法とテンプレート: `references/jq-conventions.md`

## 目的

- **動作確認**: 設定済みフックのログが実際に書き込まれているか確認する
- **網羅性確認**: 利用可能なフックイベントと現在の設定を照合し、追加候補を提案する
- **最適化**: コマンドの問題（jq パス、構文エラー等）を検出して修正案を提示する
- **更新**: ユーザー承認後に settings.json を編集する

## Phase 1: 現状確認（並列実行）

同一メッセージ内で以下 3 コールを Bash tool で並列発行する。

### 1-1. 現在の hooks 設定を読み込む

```bash
/opt/homebrew/bin/jq '.hooks' ~/.claude/settings.json
```

### 1-2. ログファイルの状態確認

```bash
ls -lah ~/.claude/logs/ 2>/dev/null || echo "ディレクトリなし"
```

各ログファイルの以下を評価:

- サイズ（0 バイト = フックが機能していない可能性）
- 最終更新時刻
- 末尾数行の内容（`tail -5 ~/.claude/logs/xxx.log`）

肥大化しきい値（厳密列挙）:

| サイズ | 状態 |
|---|---|
| 0 バイト | `❌ 空（フックが機能していない可能性）` |
| 1MB 未満 | `✅ 正常` |
| 1MB 以上 10MB 未満 | `⚠️ 要注意` |
| 10MB 以上 | `❌ 肥大化` |

### 1-3. jq の動作テスト

各フックコマンドをダミー入力で検証する（`references/jq-conventions.md` 参照）。

## Phase 2: ダッシュボード表示

以下の形式で表示する。

```markdown
## Hooks レビュー結果 (YYYY-MM-DD HH:MM)

### 設定済みフック

| イベント | ログファイル | 状態 | 最終書き込み |
|---|---|---|---|
| UserPromptSubmit | prompts.log | ✅ 正常 / ❌ 空 / ⚠️ 問題あり | YYYY-MM-DD HH:MM |

### ログサイズ

| ファイル | サイズ | 状態 |
|---|---|---|
| prompts.log | XXX KB | ✅ 正常 / ⚠️ 要注意 / ❌ 肥大化 |

### 未設定フック（追加候補）

| イベント | 推奨度 | 理由 |
|---|---|---|
| SessionStart | ★★☆ | セッション開始時のモデル・起動方法を記録できる |

### 検出された問題

- [問題があれば列挙]
- [なければ「問題なし」]
```

状態列は次の 4 種のみ使用する: `✅ 正常` / `❌ 空` / `⚠️ 要注意` / `❌ 肥大化`。

## Phase 3: 改善提案とユーザー確認

問題または追加候補がある場合、番号付きリストで提示し、実行する番号を聞く（複数選択可・skip 可）。

```
次のアクション候補:
  1. [問題] xxx フックのコマンドを修正
  2. [追加] SessionStart フックを追加（セッションログ）
  3. [追加] PostToolUse (MCP 絞り込み) を追加

実行する番号を教えてください（複数選択可 / skip で何もしない）。
```

## Phase 4: settings.json 更新

ユーザー承認後、以下の順で実行する。

### 4-1. バックアップ

```bash
cp ~/.claude/settings.json ~/.claude/settings.json.bak-$(date +%s)
```

### 4-2. Edit tool で差分編集

`references/jq-conventions.md` のテンプレートを参考に、Edit tool で該当箇所を追加・修正する。Write tool は使用しない。

### 4-3. JSON 構文検証

```bash
/opt/homebrew/bin/jq empty ~/.claude/settings.json && echo "JSON OK"
```

exit 0 かつ `JSON OK` を確認する。失敗時は `~/.claude/settings.json.bak-*` からロールバックする。

### 4-4. フックコマンド再テスト

追加した各フックコマンドを Phase 1-3 と同じダミー入力で再実行し、正常出力を確認する（入力例は `references/jq-conventions.md` 参照）。

**受け入れ基準**:

- [ ] バックアップファイルが存在する
- [ ] `jq empty` が exit 0
- [ ] 追加したコマンドのテスト出力がログ行フォーマットに一致する
- [ ] ユーザーへ「変更は次回セッション起動時に反映されます」と明示する

## 補足

- `prompts.log` はユーザー入力全文を記録する。機密情報の扱いに注意する
- `PostToolUse` の全件ログはデータ量が多くなるため matcher で絞り込む
- ログ肥大化対策には `logrotate` もしくは手動ローテーションを別途提案する
