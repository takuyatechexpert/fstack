# fstack hooks

実戦投入済みの hook を配布する。利用者は **opt-in** で `~/.claude/settings.json` に組み込む。

`setup` スクリプトでは hook の自動インストールはしない。利用者が必要なものだけ選んで wire up する設計。

## 同梱フック

### セキュリティ系

| ファイル | イベント | 用途 |
|---|---|---|
| `validate-bash.sh` | `PreToolUse` (Bash) | パイプ経由のシェル実行・eval・シークレット参照・curl 詳細トレース・set -x 等の危険パターンをブロック |
| `check-secret-patterns.sh` | `PreToolUse` (Bash) | `git commit/push` 時に、プロジェクト直下の `.claude/secret-patterns.txt` で定義された正規表現にマッチする内容があればブロック |
| `validate-file-write.sh` | `PreToolUse` (Edit/Write) | `.env` / SSH 鍵 / 証明書 / settings.json / crontab 等の機密ファイル書き込みを deny/ask |
| `mask-secrets.sh` | パイプ経由（補助） | API キー・トークン・JWT・AWS キー・OAuth 等のリテラル値を `[MASKED]` に置換 |
| `mask-mcp-output.sh` | `PostToolUse` (MCP) | MCP ツール出力に混入したシークレットを LLM コンテキスト到達前にマスク |

### コンテキスト管理系

| ファイル | イベント | 用途 |
|---|---|---|
| `bootstrap-env.sh` | `SessionStart` | DB / 主要言語 / フレームワーク / Makefile ターゲット等を `additionalContext` で注入。24時間キャッシュ |
| `pre-compact-handover.sh` | `PreCompact` | 自動圧縮直前に handover スキル実行を強く指示 |
| `post-compact-warning.sh` | `PostCompact` | 自動圧縮後に handover スキル実行を強く指示。圧縮ログ記録 |

### コード品質系

| ファイル | イベント | 用途 |
|---|---|---|
| `check-debug-code.sh` | `PostToolUse` (Edit/Write) | JS/TS の `console.log` / `debugger` 残存検出 |
| `pre-commit-lint.sh` + `lint/` | `PreToolUse` (Bash) | `git commit` 時に多言語 lint を dispatcher で実行。`lint/lint-{js,php,python,rust}.sh` の SRP 分離 + `lint/config.json` でプロジェクト別 override |
| `check-implementation-routing.sh` | `PreToolUse` (Edit/Write/NotebookEdit) | コードファイル編集前に、直近30分以内に実装オーケストレーション系スキル（solo-with-verifier / orchestra-of-agents）の起動痕跡が `skills.log` にあるか確認し、無ければ stderr で reminder（blocking しない）。メタ系・設定系・ドキュメント系のパスは除外 |

### ログ系

| ファイル | イベント | 用途 |
|---|---|---|
| `skill-log.sh` | スキルから手動呼び出し | スキル使用ログを `~/.claude/logs/skills.log` に追記する簡易ユーティリティ |
| `log-knowledge-read.sh` | `PostToolUse` (Read) | ナレッジディレクトリ配下のファイル読み込みを `~/.claude/logs/knowledge.log` に記録。マッチ対象は環境変数 `CLAUDE_KNOWLEDGE_DIR`（デフォルト `~/knowledge`）で設定 |

## opt-in 手順

### 1. 配置

#### Option A: 直接参照（推奨・更新が反映される）

そのまま fstack のパスを参照する。

#### Option B: `~/.claude/hooks/` に手動でシンボリックリンク

```bash
mkdir -p ~/.claude/hooks
ln -s "$(pwd)/hooks/validate-bash.sh"         ~/.claude/hooks/fstack-validate-bash.sh
ln -s "$(pwd)/hooks/check-secret-patterns.sh"  ~/.claude/hooks/fstack-check-secret-patterns.sh
ln -s "$(pwd)/hooks/mask-secrets.sh"           ~/.claude/hooks/fstack-mask-secrets.sh
ln -s "$(pwd)/hooks/validate-file-write.sh"    ~/.claude/hooks/fstack-validate-file-write.sh
ln -s "$(pwd)/hooks/mask-mcp-output.sh"        ~/.claude/hooks/fstack-mask-mcp-output.sh
ln -s "$(pwd)/hooks/bootstrap-env.sh"          ~/.claude/hooks/fstack-bootstrap-env.sh
ln -s "$(pwd)/hooks/pre-compact-handover.sh"   ~/.claude/hooks/fstack-pre-compact-handover.sh
ln -s "$(pwd)/hooks/post-compact-warning.sh"   ~/.claude/hooks/fstack-post-compact-warning.sh
ln -s "$(pwd)/hooks/check-debug-code.sh"       ~/.claude/hooks/fstack-check-debug-code.sh
ln -s "$(pwd)/hooks/pre-commit-lint.sh"        ~/.claude/hooks/fstack-pre-commit-lint.sh
ln -s "$(pwd)/hooks/check-implementation-routing.sh" ~/.claude/hooks/fstack-check-implementation-routing.sh
ln -s "$(pwd)/hooks/log-knowledge-read.sh"     ~/.claude/hooks/fstack-log-knowledge-read.sh
chmod +x hooks/*.sh hooks/lint/*.sh
```

### 2. `~/.claude/settings.json` に追加

#### セキュリティ + 圧縮系 + lint + コード品質・ログ系の wire-up 例

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          { "type": "command", "command": "~/.claude/hooks/fstack-bootstrap-env.sh", "timeout": 10 }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command", "command": "~/.claude/hooks/fstack-validate-bash.sh", "timeout": 5 },
          { "type": "command", "command": "~/.claude/hooks/fstack-check-secret-patterns.sh", "timeout": 10 },
          { "type": "command", "command": "~/.claude/hooks/fstack-pre-commit-lint.sh", "timeout": 60 }
        ]
      },
      {
        "matcher": "Edit|Write",
        "hooks": [
          { "type": "command", "command": "~/.claude/hooks/fstack-validate-file-write.sh", "timeout": 5 }
        ]
      },
      {
        "matcher": "Edit|Write|NotebookEdit",
        "hooks": [
          { "type": "command", "command": "~/.claude/hooks/fstack-check-implementation-routing.sh", "timeout": 5 }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          { "type": "command", "command": "~/.claude/hooks/fstack-check-debug-code.sh", "timeout": 5 }
        ]
      },
      {
        "matcher": "Read",
        "hooks": [
          { "type": "command", "command": "~/.claude/hooks/fstack-log-knowledge-read.sh", "timeout": 5 }
        ]
      },
      {
        "matcher": "mcp__.*",
        "hooks": [
          { "type": "command", "command": "~/.claude/hooks/fstack-mask-mcp-output.sh", "timeout": 5 }
        ]
      }
    ],
    "PreCompact": [
      {
        "hooks": [
          { "type": "command", "command": "~/.claude/hooks/fstack-pre-compact-handover.sh", "timeout": 5 }
        ]
      }
    ],
    "PostCompact": [
      {
        "hooks": [
          { "type": "command", "command": "~/.claude/hooks/fstack-post-compact-warning.sh", "timeout": 5 }
        ]
      }
    ]
  }
}
```

## `.claude/secret-patterns.txt` の書き方

プロジェクト直下に `.claude/secret-patterns.txt` を作成。1行1パターン、`#` で始まる行はコメント。

```text
# Stripe live keys
sk_live_[A-Za-z0-9]{24,}

# GitHub personal access tokens
ghp_[A-Za-z0-9]{36}

# 自社固有のフォーマット
INTERNAL_API_[A-Z0-9]{20,}
```

`git commit` 時にステージング対象、`git push` 時に追跡ファイル全体に対して `grep` ベースで検査する。

## `hooks/lint/config.json` の書き方

プロジェクトごとに lint コマンドを override したい場合は `hooks/lint/config.example.json` を `config.json` にコピーして使う（`config.json` は環境依存なので gitignore 対象）。

```json
{
  "projects": [
    {
      "path": "/Users/me/projects/my-laravel-app",
      "commands": {
        "php": "vendor/bin/pint --test && vendor/bin/phpstan analyse",
        "js":  "pnpm lint"
      }
    }
  ]
}
```

`path` がリポジトリルートと一致、または `path/` で始まる場合にマッチ。`commands` の言語キー (`js` / `php` / `python` / `rust`) → シェルコマンドで、`$ROOT` で実行される。

## bootstrap-env.sh の注意点

- macOS 前提（`stat -f %m`、`md5`、`/opt/homebrew/bin/jq` フォールバック）
- Linux で使う場合は `stat -c %Y` / `md5sum` への置換が必要
- キャッシュ先: `~/.claude/cache/bootstrap/<md5(cwd)>.md`、24時間有効
- 強制再生成: `bash hooks/bootstrap-env.sh --force < <(echo '{"cwd":"'$PWD'"}')`

## check-implementation-routing.sh の注意点

- macOS 前提（`date -j -f` で skills.log のタイムスタンプを epoch 変換する）。Linux で使う場合は `date -d` への置換が必要
- `skills.log` が存在しない環境では何もせず正常終了する（reminder を出すには `skill-log.sh` 等でスキル起動を記録している前提）
- blocking しない reminder のみ。極小スコープ（typo・1行修正）の編集では無視して続行可能

## log-knowledge-read.sh の注意点

- 記録対象パスは環境変数 `CLAUDE_KNOWLEDGE_DIR` で指定する（未設定時のデフォルトは `~/knowledge`）。自分のナレッジ置き場に合わせて設定する
- 対象外パスの Read は何も記録せず正常終了する
- ログ先: `~/.claude/logs/knowledge.log`（`[YYYY-MM-DD HH:MM:SS] [KNOWLEDGE] READ <basename>` 形式）

## カスタマイズ

- `validate-bash.sh` の禁止パターンを増やしたい → fork してプロジェクト独自の hook を作る
- 言語別の lint を追加したい → `hooks/lint/lint-<lang>.sh` を追加し、`pre-commit-lint.sh` の `run_lang` 呼び出しに追記
- マスキングのパターンを増やしたい → `mask-secrets.sh` の sed 行を追加

## 参考: 関連ルール

- `rules/security.md` の「スキル開発時の認証情報ハンドリング」が、これらの hook が想定する運用前提
- `rules/context-management.md` の「セッション運用ルール」が `bootstrap-env.sh` / `pre-compact-handover.sh` 等の前提
