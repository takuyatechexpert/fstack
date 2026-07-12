---
name: my-skill-creator
description: "Claude Code用スキルの新規作成・既存スキル更新・テスト・説明文最適化を支援するガイドスキル。スキルのディレクトリ構成、SKILL.mdの書き方、eval実行、ベンチマーク、説明文の自動最適化まで一貫してサポートする。ユーザーが「スキル作成」「スキル作って」「skill-creator」「新しいスキル」「スキル更新」「スキルをテストしたい」「説明文を最適化したい」と言ったときに使用する。以下では起動しない: 既存スキルの健康診断・改善計画・肥大化対応・棚卸し・リファクタリング（skill-auditor が担当）、サブエージェント（.claude/agents/*.md）の作成・更新・リント（agent-creator が担当）、スキル発見・他に使えるスキルがないかの確認（find-skills が担当）、スキル本体ではなく Claude Code の hooks 設定変更（review-hooks が担当）。"
---

# Skill Creator

Claude Code 用スキルの作成・更新・改善を一貫してサポートする。

## 参照ファイル

各 Phase の冒頭で、該当する参照ファイルを **Read で毎回読み込んで一次情報として扱う**（要約・過去会話・メモリからの再現ではなく、現ファイルの内容を正とする）。

| 参照ファイル | 読むタイミング |
|---|---|
| `${CLAUDE_SKILL_DIR}/references/skill-standards.md` — スキル構築の基準（単一の真実のソース）。配置先・ディレクトリ構成・SKILL.md の構造・設計原則・検証チェックリストを含む。基準を変更するときはこのファイルのみを更新する（skill-auditor も同ファイルを参照する） | Phase 1 冒頭（必須） |
| `${CLAUDE_SKILL_DIR}/references/skill-patterns.md` — 既存スキルパターン・リファクタリング | Phase 1・2（既存との関連整理時） |
| `${CLAUDE_SKILL_DIR}/references/ptc-pattern.md` — PTC（並列実行）パターン | Phase 2（PTC 要否判断時） |
| `${CLAUDE_SKILL_DIR}/references/eval-workflow.md` — テスト・ベンチマーク | Phase 4 冒頭（必須） |
| `${CLAUDE_SKILL_DIR}/references/description-optimizer.md` — 説明文最適化 | Phase 5 冒頭（必須） |

---

## スキル作成ワークフロー

### Phase 1: 要件理解

まず **以下 4 点をユーザーに一括質問する**（1問ずつ往復せず、まとめて提示してから回答を受け取る）。

1. **スキルの用途**: 何を自動化・支援したいか
2. **トリガー発話**: ユーザーが発する典型フレーズ 3〜5 例
3. **具体的な使用例**: 入力と期待出力のサンプル 1〜2 件
4. **ドメイン固有の落とし穴**: AI がハマりそうな暗黙知・ID 体系の不一致・特殊な仕様

回答が揃ったら:

- 既存スキルとの関連・依存を `references/skill-patterns.md` を Read したうえで整理する
- eval の要否を下記 3 条件すべて「はい」なら eval あり、1 つでも「いいえ」なら eval なしと判定する:
  - [ ] 出力が決定的か（同じ入力で毎回同じ結果を期待できる）
  - [ ] 入力を固定できるか（テストプロンプトを再現可能な形で書ける）
  - [ ] 失敗を自動検知できるか（grader または assertion で合否を数値化できる）

### Phase 2: 設計

`references/skill-patterns.md` を必要に応じて再度 Read し、以下を設計する。

- ファイル構成（SKILL.md のみ / references/ を持たせるか）
- Phase 構成（番号と役割を明示）
- 外部連携（GitHub / Slack / ファイル操作 等）
- **PTC（並列実行）の要否**: 独立した外部呼び出しが 3 つ以上 → `scripts/` に並列実行スクリプトを検討（`references/ptc-pattern.md` を Read）
- ログ記録方式（PostToolUse hook 任せか、skill-log.sh 併用か）

### Phase 3: 実装

1. スキルディレクトリを作成:
   ```bash
   mkdir -p ~/.claude/skills/{skill-name}
   ```
   dotfiles 等で別管理している場合は実体パスに作成し、`~/.claude/skills/{skill-name}` がシンボリックリンクで指す形にする。
2. SKILL.md を Write ツールで作成（配置先: `~/.claude/skills/{skill-name}/SKILL.md`）
   - フロントマターの `model` / `effort` は `references/skill-standards.md` の「model / effort の判断軸」に従う（推論系は inherit、機械的定型は haiku/sonnet 固定、不要なピン留めは避ける）
3. 必要に応じて `references/` や `assets/` を作成

### Phase 3.5: 構造セルフ検証

Phase 3 完了直後に、作成した SKILL.md に対して以下を **すべて PASS するまで Edit で修正** する。

```bash
# 3.5-1. フロントマターが YAML として valid
head -n 20 {SKILL.md} | grep -E '^name:|^description:'  # name/description が存在すること

# 3.5-2. description の文字数と必須要素
# - 200 文字以内（英数字は 2 バイト換算で OK）
# - Phase 1 で挙げたトリガー発話のうち最低 3 つを含む

# 3.5-3. Phase 番号の欠番チェック
grep -oE '^### Phase [0-9]+' {SKILL.md}  # 連番で欠けがないこと

# 3.5-4. skill-standards.md の検証チェックリスト全項目を Read で再確認
```

PASS 条件:
- [ ] frontmatter に `name` と `description` が存在し、YAML パース可能
- [ ] description は 200 文字以内・トリガー発話 3 つ以上を含む
- [ ] Phase 番号に欠番なし
- [ ] `skill-standards.md` の検証チェックリスト全項目を満たす

### Phase 4: テスト・改善（eval 実行）

Phase 1 で「eval あり」と判定されたスキルは、Phase 4 冒頭で `references/eval-workflow.md` を Read してから以下を実施する。

**前提チェック**: grader / eval-viewer / `run_loop.py` は公式 skill-creator プラグイン（`~/.claude/plugins/marketplaces/claude-plugins-official/plugins/skill-creator/skills/skill-creator`）のスクリプト。未導入の環境ではこれらを起動できないため、着手前に導入有無を確認する。未導入なら公式プラグインの導入を案内し、導入しない場合は手動採点（各アサーションを1件ずつ目視で ○× 判定し `with_skill` の勝率を集計）にフォールバックする。

1. `evals/evals.json` にテストプロンプトを 2〜3 件作成
2. `with_skill` と `without_skill` を **同一ターン内で並列実行** する（Bash ツールを並列発行）
3. アサーション設計 → grader で採点 → ベンチマーク集計 → eval-viewer でレビュー
4. 合否判定: `with_skill` の勝率が **70% 以上** で PASS。下回った場合は SKILL.md を改善して Phase 4 を再実行
5. フィードバックをもとに反復

### Phase 5: 説明文最適化

`references/description-optimizer.md` を Read してから実施する。

1. `should_trigger` / `should_not_trigger` クエリを 20 件作成（near-miss に重点）
2. HTML テンプレートでユーザーに確認・編集させる
3. `run_loop.py` で自動最適化（60/40 split + 拡張思考、最大 5 イテレーション）。`run_loop.py` は公式 skill-creator プラグイン側のスクリプト
   - 公式プラグイン導入済み かつ `ANTHROPIC_API_KEY` が環境にある場合: `run_loop.py` を実行
   - 公式プラグイン未導入 または `ANTHROPIC_API_KEY` が未設定の場合: 手動最適化に切り替え（`references/description-optimizer.md` の「APIキーがない場合の手動最適化」を Read して手順に従う）
4. `best_description` を SKILL.md frontmatter に適用し、Phase 3.5-2 の文字数・トリガー語チェックを再実行

### Phase 6: ログ記録

- 起動ログ: PostToolUse (Skill) hook が自動記録
- 完了時は下記のいずれかを実行:
  - 新規作成: `~/.claude/hooks/skill-log.sh skill-creator CREATE "{スキル名}"`
  - 更新: `~/.claude/hooks/skill-log.sh skill-creator UPDATE "{スキル名}"`
  - エラー: `~/.claude/hooks/skill-log.sh skill-creator ERROR "{エラー内容}"`

---

## 検証チェックリスト

基準および検証チェックリストの原典は `${CLAUDE_SKILL_DIR}/references/skill-standards.md` の「検証チェックリスト」セクション。新規作成・更新の完了前に必ず Read で読み込み、全項目を確認する。
