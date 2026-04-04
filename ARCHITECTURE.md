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
│   │       └── SKILL.md   # ナレッジ蒸留スキル
│   ├── review/
│   │   ├── review-pr/
│   │   │   └── SKILL.md   # PR レビュースキル
│   │   └── pending-reviews/
│   │       └── SKILL.md   # レビュー待ち一覧スキル
│   ├── test/
│   │   └── spec-driven-test/
│   │       └── SKILL.md   # 仕様駆動テストスキル
│   └── build/
│       └── orchestra-of-agents/
│           ├── SKILL.md   # 並列実装スキル
│           └── references/
│               └── *.md   # オーケストレーション用参照ドキュメント
├── rules/
│   ├── design-principles.md
│   ├── git-workflow.md
│   ├── testing.md
│   ├── security.md
│   └── context-management.md
├── agents/
│   └── architect.md       # 読み取り専用の設計分析エージェント
└── templates/
    ├── CLAUDE.md.template              # グローバル CLAUDE.md テンプレート
    └── project-claude.md.template      # プロジェクト固有 CLAUDE.md テンプレート
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
tools:
  - Read
  - Grep
  - Glob
  - Bash
disallowedTools:
  - Edit
  - Write
model: sonnet
---

# エージェントへの指示...
```

主なフロントマターフィールド:
- **tools** — エージェントが使用可能なツールのホワイトリスト
- **disallowedTools** — 明示的に禁止するツール
- **model** — 使用する Claude モデル（`sonnet`, `opus`, `haiku`）

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

ルールを無効化するには、シンボリックリンクを削除するだけです。

### エージェント: 直接リンク

エージェントファイルはそのままリンクします:

```
fstack/agents/architect.md → ~/.claude/agents/architect.md
```

## Hooks によるログ拡張

Claude Code は hooks（イベントに応じて実行されるシェルコマンド）をサポートしています。hooks を使って fstack にロギングや通知機能を追加できます。

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
            "command": "echo \"$(date -u +%Y-%m-%dT%H:%M:%SZ) $SKILL_NAME\" >> ~/.claude/logs/skills.log"
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
