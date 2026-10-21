# アーキテクチャ

## ディレクトリ構成

```
fstack/
├── setup                  # インストールスクリプト（bash、外部依存なし）
├── README.md              # プロジェクト概要・クイックスタート
├── ARCHITECTURE.md        # このファイル
├── LICENSE                # MIT License
├── skills/
│   ├── core/
│   │   ├── handover/
│   │   │   └── SKILL.md   # セッション引き継ぎスキル
│   │   └── crystallize/
│   │       ├── SKILL.md   # ナレッジ蒸留スキル
│   │       ├── references/   # report-format / nfd-architecture
│   │       └── scripts/      # verify-integrity.sh
│   ├── review/
│   │   ├── review-pr/
│   │   │   └── SKILL.md   # PR レビュースキル
│   │   ├── pending-reviews/
│   │   │   └── SKILL.md   # レビュー待ち一覧スキル
│   │   └── review-all-pending/
│   │       ├── SKILL.md   # レビュー待ち PR 一括レビュースキル
│   │       ├── evals/
│   │       └── references/
│   ├── test/
│   │   └── spec-driven-test/
│   │       └── SKILL.md   # 仕様駆動テストスキル
│   ├── build/
│   │   ├── build-planner/
│   │   │   ├── SKILL.md   # 実装着手前の設計・計画書作成・粒度判定スキル
│   │   │   └── references/
│   │   │       └── plan-template.md  # 計画書テンプレート
│   │   ├── orchestra-of-agents/
│   │   │   ├── SKILL.md   # 並列実装スキル
│   │   │   └── references/
│   │   │       └── *.md   # オーケストレーション用参照ドキュメント
│   │   └── solo-with-verifier/
│   │       ├── SKILL.md   # 軽量実装スキル（Generator-Verifier パターン）
│   │       └── references/
│   │           └── *.md   # Implementer / Verifier プロンプト・rules チェックリスト
│   └── meta/              # スキル開発を支援するスキル群
│       ├── my-skill-creator/   # スキル新規作成・更新・ベンチマーク
│       │   ├── SKILL.md
│       │   ├── references/     # skill-standards / skill-patterns / ptc-pattern 等
│       │   └── scripts/        # count-tokens.sh
│       ├── skill-auditor/      # 既存スキルの健康診断・改善計画
│       │   ├── SKILL.md
│       │   └── references/     # audit-checklist / improvement-plan-template / step-patterns
│       ├── agent-creator/      # カスタムエージェント作成・リント
│       │   ├── SKILL.md
│       │   ├── references/     # agent-patterns / lint-rules
│       │   └── scripts/        # lint-agent.py
│       └── review-hooks/       # hooks 設定レビュー・最適化
│           ├── SKILL.md
│           └── references/     # hook-events / jq-conventions
├── rules/
│   ├── design-principles.md
│   ├── git-workflow.md
│   ├── testing.md
│   ├── implementation-flow.md  # 規模別の進め方・スコープとテストの範囲・検証体制を足す判断
│   ├── work-discipline.md  # バグ修正の3ステップなど作業規律
│   ├── security.md
│   ├── context-management.md
│   ├── memory.md          # Auto Memory 4種運用
│   ├── plan-mode.md       # Plan Mode の発動基準・ワークフロー
│   ├── document-writing.md # 人が読む文書の構成原則・取捨選択・発見可能性の担保
│   └── file-operations.md # 破壊的操作の取扱い原則
├── agents/
│   ├── architect.md       # 読み取り専用の設計分析エージェント
│   └── db-schema-investigator.md  # 読み取り専用の DB スキーマ調査エージェント（create＋後続変更を追い実DBで裏取り）
│                          # ※ eval 系エージェントは Anthropic 公式 skill-creator plugin を利用
├── hooks/                 # オプションの hook (opt-in)
│   ├── validate-bash.sh           # 危険 Bash パターン検知
│   ├── check-secret-patterns.sh   # コミット時シークレット検査
│   ├── validate-file-write.sh     # 機密ファイル書き込み deny/ask
│   ├── mask-secrets.sh            # シークレットマスク（補助）
│   ├── mask-mcp-output.sh         # MCP 出力マスク
│   ├── bootstrap-env.sh           # SessionStart 環境注入
│   ├── pre-compact-handover.sh    # 自動圧縮直前に handover 強制
│   ├── post-compact-warning.sh    # 自動圧縮後に handover 強制
│   ├── check-debug-code.sh        # JS/TS デバッグコード検出
│   ├── check-implementation-routing.sh  # 変更ファイル数が 5 の倍数に達した編集で solo/orchestra の起動痕跡を advisory 確認
│   ├── log-knowledge-read.sh      # ナレッジディレクトリ配下の Read をログ記録
│   ├── pre-commit-lint.sh         # 多言語 lint dispatcher
│   ├── lib/                       # hooks 共通ライブラリ
│   │   └── common.sh              # jq 解決・deny/ask JSON 発行・GNU/BSD 差の吸収
│   ├── lint/                      # 言語別 handler + 設定テンプレ
│   │   ├── lint-js.sh
│   │   ├── lint-php.sh
│   │   ├── lint-python.sh
│   │   ├── lint-rust.sh
│   │   └── config.example.json
│   ├── skill-log.sh               # スキル使用ログ追記
│   └── README.md                  # 設定方法・カスタマイズ手順
├── docs/
│   ├── claude5-migration-guide.md # Opus 4.7 → Claude 5 系のプロンプト・スキル調整ガイド
│   └── prompt-migration-guide.md  # モデルバージョンアップ時のプロンプト再調整ガイド
└── templates/
    ├── CLAUDE.md.template              # グローバル CLAUDE.md テンプレート
    ├── project-claude.md.template      # プロジェクト固有 CLAUDE.md テンプレート
    └── knowledge/                      # crystallize 連動のナレッジテンプレ
```

## スキルの仕組み

スキルは Claude Code の拡張機構です。各スキルは `SKILL.md` ファイルを含むディレクトリで、YAML フロントマターとマークダウンの指示で構成されます。

### SKILL.md のフォーマット

```yaml
---
name: my-skill
description: スキルの説明（一行）。Claude Code のスキルディスカバリで使用される
---

# スキル名

マークダウン本文がスキルのプロンプトとして読み込まれます。
ユーザーが `/my-skill` と入力すると、この内容が実行されます。
```

### スキルの解決順序

Claude Code は `${CLAUDE_SKILL_DIR}`（デフォルト: `~/.claude/skills/`）からスキルを検索します。`SKILL.md` を含む各サブディレクトリが利用可能なスキルとして登録されます。

ユーザーが `/my-skill` と入力すると:
1. `${CLAUDE_SKILL_DIR}/my-skill/SKILL.md` を検索
2. フロントマターからメタデータを読み取り
3. マークダウン本文をスキルプロンプトとして読み込み
4. 現在の会話コンテキストでスキルを実行

### `${CLAUDE_SKILL_DIR}` 変数

スキル内で `${CLAUDE_SKILL_DIR}` を使うと、そのスキルの SKILL.md があるディレクトリへの絶対パスに展開されます。参照ファイルやサブリソースへのパス指定に使います。

```markdown
参照ファイルを Read: `${CLAUDE_SKILL_DIR}/references/checklist.md`
```

## ルールの仕組み

ルールは `~/.claude/rules/` に配置されたマークダウンファイルです。Claude Code はこのディレクトリの全 `*.md` ファイルを自動的に読み込み、すべての会話でシステム指示として適用します。

ルールに適しているもの:
- コーディング規約・スタイルガイド
- ワークフロー要件（コミットメッセージ形式など）
- セキュリティポリシー
- テスト方針

## エージェントの仕組み

エージェントは `~/.claude/agents/` に配置されたマークダウンファイルです。YAML フロントマターで使用できるツールや制約を定義します。

```yaml
---
name: architect
description: 設計分析エージェント
tools: Read, Grep, Glob, Bash
disallowedTools: Write, Edit, NotebookEdit, Agent
model: inherit
effort: high
maxTurns: 30
---

# エージェントへの指示...
```

主なフロントマターフィールド:
- **tools** — エージェントが使用可能なツールのホワイトリスト（カンマ区切りの inline 記法）
- **disallowedTools** — 明示的に禁止するツール（カンマ区切りの inline 記法）
- **model** — 使用する Claude モデル（`inherit`, `sonnet`, `opus`, `haiku`, `fable`）。`inherit` は呼び出し元の会話と同じモデルを使う
- **effort** — そのエージェントが動く間のセッション effort を上書きする（`low` / `medium` / `high` / `xhigh` / `max`）。省略時の挙動は公式に明記がないため、効くものは明示する
- **maxTurns** — エージェントの最大ターン数（暴走を防ぐ安全装置。設定推奨）

## シンボリックリンク戦略

`setup` スクリプトはファイルコピーではなくシンボリックリンクで fstack を Claude Code に統合します。そのため fstack を更新すると即座に反映されます。

### スキル: フラット展開

スキルはカテゴリ階層を剥がしてフラットにリンクされます:

```
fstack/skills/core/handover/              → ~/.claude/skills/handover
fstack/skills/review/review-pr/           → ~/.claude/skills/review-pr
fstack/skills/build/orchestra-of-agents/  → ~/.claude/skills/orchestra-of-agents
```

Claude Code がスキルディレクトリをフラットに期待するための設計です。

### ルール: fstack- プレフィックス

ルールはユーザーの既存ルールとの衝突を防ぐため、`fstack-` プレフィックス付きでリンクします:

```
fstack/rules/design-principles.md → ~/.claude/rules/fstack-design-principles.md
fstack/rules/testing.md           → ~/.claude/rules/fstack-testing.md
```

なお、リポジトリ内のスキルプロンプトや docs が参照する素の `rules/xxx.md`（例: `rules/testing.md`）は、インストール後の `~/.claude/rules/fstack-xxx.md`（例: `fstack-testing.md`）に対応する。

ルールを無効化するには、シンボリックリンクを削除するだけです。

### エージェント: 直接リンク

エージェントファイルはそのままリンクします:

```
fstack/agents/architect.md → ~/.claude/agents/architect.md
```

## Hooks の仕組みと配布

Claude Code は hooks（イベントに応じて実行されるシェルコマンド）をサポートしています。hooks を使って fstack にロギングや通知機能を追加できます。

### fstack の hooks ディレクトリ（opt-in）

`fstack/hooks/` に **オプションのセキュリティ hook** を同梱しています。
利用者が `~/.claude/settings.json` で wire up することで有効になります（`setup` スクリプトでは自動インストールしません）。

詳細は [hooks/README.md](hooks/README.md) を参照。

### 例: スキル使用ログ

`~/.claude/settings.json` に追加:

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Skill",
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/hooks/skill-log.sh \"$(jq -r '.tool_input.skill // \"unknown\"')\" START auto"
          }
        ]
      }
    ]
  }
}
```

スキル名は hook の stdin JSON（`.tool_input.skill`）から取得する（`$SKILL_NAME` のような環境変数は存在しない）。ログ形式は `skill-log.sh` に一元化され `[timestamp] [<skill>] [START] auto` で統一される。`setup` の Crystallize セットアップ（`--global`）はこの hook 設定の追加と `~/.claude/hooks/skill-log.sh` へのリンク作成を行う。

### 例: セキュリティ hook（同梱）の wire up

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "/path/to/fstack/hooks/validate-bash.sh",
            "timeout": 5
          }
        ]
      }
    ]
  }
}
```

## スキルのフォーク・カスタマイズ

fstack を直接変更せずにスキルをカスタマイズする方法:

1. スキルディレクトリを別の場所にコピー
2. `SKILL.md` を必要に応じて修正
3. シンボリックリンクを新しい場所に向ける

```bash
cp -r fstack/skills/core/handover ~/.claude/skills/my-handover
# ~/.claude/skills/my-handover/SKILL.md を編集
# 元の handover シンボリックリンクを削除すれば、カスタム版が使われます
```

プロジェクト固有のスキルは、リポジトリ内の `.claude/skills/` に配置することもできます。
