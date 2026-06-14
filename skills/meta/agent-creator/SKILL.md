---
name: agent-creator
description: "Claude Code用カスタムエージェント（.claude/agents/*.md）の新規作成・更新・バリデーションを支援するスキル。対話的なウィザードでYAMLフロントマターとシステムプロンプトを構築し、リントで設定ミス（サイレント失敗・タイプミス・構文エラー）を検出する。ユーザーが「エージェント作成」「エージェント作って」「agent-creator」「新しいエージェント」「エージェント更新」「エージェントのリント」「サブエージェント作成」「エージェント検証」「agentファイル作成」と言ったときに使用する。"
---

# Agent Creator

Claude Code カスタムエージェント（`.claude/agents/*.md`）の作成・更新・検証を支援する。

## 基本原則

1. **参照ファイルは毎回 Read で読み込む**（要約・メモリから再現しない）
2. **不足情報は最初のターンで一括ヒアリング**（往復を減らす。以降はデフォルト値で即走）
3. **バリデーションは `lint-agent.py` の exit code が 0 かつ警告ゼロになるまで修正する**
4. **動作確認は Agent 起動を含めて実施する**（`/agents` 露出 / ツール制限 / 自動委任）

## 参照ファイル

- `${CLAUDE_SKILL_DIR}/references/agent-patterns.md` — デザインパターン・テンプレート
- `${CLAUDE_SKILL_DIR}/references/lint-rules.md` — リント検出項目の詳細

**Phase 2 冒頭で上記 2 ファイルを Read（同一メッセージ内で並列発行）。**

## エージェント配置先

- ユーザースコープ: `~/.claude/agents/{name}.md`（dotfiles 等で別管理している場合は実体パスへ）
- プロジェクトスコープ: `.claude/agents/{name}.md`

## ワークフロー（Phase 1-5）

### Phase 1. 要件ヒアリング（一括）

**最初のターンで以下 6 項目をまとめて質問する**。回答後はデフォルト値で即実行し、次のユーザー確認は Phase 4 の動作確認で取る。

| 項目 | デフォルト / 推奨 |
|---|---|
| 1. 目的 | （必須） |
| 2. スコープ | ユーザー / プロジェクト |
| 3. ツール権限 | 読み取り専用 / 編集可 |
| 4. モデル | 推論系（分析・レビュー・実装・オーケストレーション）は inherit（行を書かない） / 機械的処理（検索・単純分析・定型チェック）は `haiku` or `sonnet` 固定 / 評価系は固定維持。特定モデルのピン留めは最小限に。判断軸は `references/agent-patterns.md`「model 選定ポリシー」参照 |
| 5. `maxTurns` | 読み取り専用: 15 / 実装: 30 / オーケストレーター: 20 |
| 6. 追加機能 | `memory` / `hooks` / `mcpServers` / `skills` の要否 |

### Phase 2. 設計・生成

1. `references/agent-patterns.md` + `references/lint-rules.md` を **並列 Read**
2. 最適なデザインパターンを選択
3. YAML フロントマターを組み立てる（description にコロン `:` を含む場合はクオートで囲む）
4. 本文を以下の構造で作成:

```markdown
{役割定義: 1〜2文}

## 責務
- ...

## 分析・実行の観点
### {観点1}
- ...

## 出力フォーマット（必要に応じて）
...

## 制約
- ...
```

**設計の原則:**
- description は意図しないトリガーを避けるため、「以下では起動しない」節で境界を示す
- サブエージェントは別のサブエージェントを spawn できない（ネスト不可）
- 親のスキルは継承されない（必要なら `skills` フィールドで明示指定）

### Phase 3. バリデーション（リント）

```bash
python3 ${CLAUDE_SKILL_DIR}/scripts/lint-agent.py <agent-file-path>
```

**受け入れ基準:**
- exit code = 0
- 警告 0 件
- 警告が出た場合は修正し、再度リントを実行

検出項目の詳細は `references/lint-rules.md` を参照。

### Phase 4. 動作確認（受け入れ基準）

以下 3 点を **全て満たす** ことを確認してから Phase 5 へ進む。

- [ ] `ls ~/.claude/agents/ | grep {name}` で定義ファイルが存在する（stow 反映済み）
- [ ] Agent ツールで spawn（タイムアウト 30 秒目安）し、簡単なタスクが完了する
- [ ] description のキーワードで Skill/Agent ルーターが反応する（ドライラン用プロンプトは `references/agent-patterns.md` の末尾「動作確認プロンプト例」節を参照）

失敗した場合は Phase 2 に戻り、YAML またはシステムプロンプトを修正する。

### Phase 5. 配置・ログ記録

1. 配置先（Phase 1 のスコープ選択に従う）に書き込む
2. ログ記録（起動ログは PostToolUse hook が自動記録。完了のみ手動）

```bash
# 新規作成
~/.claude/hooks/skill-log.sh agent-creator CREATE "{name}"
# 更新
~/.claude/hooks/skill-log.sh agent-creator UPDATE "{name}"
# リント単体実行
~/.claude/hooks/skill-log.sh agent-creator LINT "{name} passed|{N} warnings"
# エラー
~/.claude/hooks/skill-log.sh agent-creator ERROR "{内容}"
```

## 更新モード

既存エージェントを更新する場合:

1. 対象ファイルを Read
2. 変更点を 1 メッセージでユーザーに提示・承認を取る
3. Edit ツールで修正
4. Phase 3（リント）を実行
5. Phase 5（配置・ログ）

## リント単体実行

1. 対象ファイルパスを確認
2. `lint-agent.py` を実行
3. 結果と修正提案を報告

## 自己検証チェックリスト（完了前に全て Yes）

- [ ] Phase 2 で 2 ファイルを並列 Read したか
- [ ] Phase 3 のリントが exit 0 / 警告 0 件で通ったか
- [ ] Phase 4 の 3 点（ファイル存在 / spawn 成功 / ルーター反応）が全て Yes か
- [ ] Phase 5 で CREATE / UPDATE / LINT いずれかのログを記録したか
