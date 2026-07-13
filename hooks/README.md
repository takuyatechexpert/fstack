# fstack hooks

実戦投入済みの hook を配布する。利用者は **opt-in** で `~/.claude/settings.json` に組み込む。

`setup` スクリプトでは hook の自動インストールはしない。利用者が必要なものだけ選んで wire up する設計。

例外として `skill-log.sh` のみ、`setup --global` の Crystallize セットアップ（ログ収集）を有効にしたときに `~/.claude/hooks/skill-log.sh` へリンクされる。`/crystallize` のログ導線として全 SKILL.md が参照するパスを実在させるため。

## 同梱フック

### セキュリティ系

| ファイル | イベント | 用途 |
|---|---|---|
| `validate-bash.sh` | `PreToolUse` (Bash) | パイプ経由のシェル実行・eval・シークレット参照・curl 詳細トレース・set -x 等の危険パターンをブロック |
| `check-secret-patterns.sh` | `PreToolUse` (Bash) | `git commit/push` 時に、プロジェクト直下の `.claude/secret-patterns.txt` で定義された正規表現にマッチする内容があればブロック。スキャン対象は working tree でなく git の内容（commit=index `:0:file`／push=`HEAD` ツリー `HEAD:file`。**push でも全履歴は遡らない** — それは gitleaks 等の領域で本 hook の射程外）。deny 理由は `<file>:<line> (pattern #<n>)`（n はパターン定義の 1 始まり番号）のみで、マッチしたシークレット値も pattern 文字列もトランスクリプトに出力しない。`git` にオプションが挟まる形（`git -c x=y commit` 等）も検出し、コマンド先頭の `cd <path> &&` と最初の `git -C <path>` を作業起点として解釈する（サブシェル・変数展開等の複雑形は `.cwd` 起点で続行）。jq 不在・stdin JSON の parse 失敗・**commit/push を検出したのに作業ディレクトリ/git root が解決できない場合（空 CWD 含む）**は exit 2 で fail-closed（従来の exit 0 素通りは廃止） |
| `validate-file-write.sh` | `PreToolUse` (Edit/Write) | `.env` / SSH 鍵 / 証明書 / settings.json / crontab 等の機密ファイル書き込みを deny/ask |
| `mask-secrets.sh` | パイプ経由（補助） | API キー・トークン・JWT・AWS キー・OAuth 等のリテラル値を `[MASKED]` に置換。JSON（`"key": "value"`）は引用符構造を保持して値だけを置換する |
| `mask-mcp-output.sh` | `PostToolUse` (MCP) | MCP ツール出力に混入したシークレットを LLM コンテキスト到達前にマスク。fail-closed（マスカー不在時はレスポンスを秘匿） |

### コンテキスト管理系

| ファイル | イベント | 用途 |
|---|---|---|
| `bootstrap-env.sh` | `SessionStart` | DB / 主要言語 / フレームワーク / Makefile ターゲット等を `additionalContext` で注入。24時間キャッシュ |
| `pre-compact-handover.sh` | `PreCompact` | 自動圧縮直前に handover スキル実行を強く指示 |
| `post-compact-warning.sh` | `PostCompact` | 自動圧縮後に handover スキル実行を強く指示。圧縮ログ記録 |

### コード品質系

| ファイル | イベント | 用途 |
|---|---|---|
| `check-debug-code.sh` | `PostToolUse` (Edit/Write) | JS/TS の `console.log` / `debugger` 残存検出。検出時は stderr に警告 + exit 2 で Claude に通知（ブロックはしない）。警告は `WARNING: debug code found in <file> (lines: 3, 7)` の形式で、行番号のみを出し**マッチした行の内容は出さない** |
| `pre-commit-lint.sh` + `lint/` | `PreToolUse` (Bash) | `git commit` 時に多言語 lint を dispatcher で実行。`lint/lint-{js,php,python,rust}.sh` の SRP 分離 + `lint/config.json` でプロジェクト別 override。lint 失敗時は `permissionDecision: "deny"` + exit 0 でコミットをブロック。symlink 経由で起動しても POSIX ポータブルな追跡ループで実体位置から `lint/` を解決する。作業起点は check-secret-patterns と同様に `cd <path> &&` / `git -C <path>` を解釈する。jq 不在・parse 失敗・**作業ディレクトリ/git root が解決できない場合**・**symlink 実体解決に失敗して `lint/` が見つからない場合**はいずれも exit 2 で fail-closed（サイレント no-op・exit 0 素通りは廃止） |
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

Option B（symlink）でも各 hook は実体位置を基準に解決するため正しく動く。symlink は fstack の実体を指すため、共通ライブラリ `hooks/lib/common.sh` も実体位置から source される（別途コピー不要）:

- 全 hook — POSIX ポータブルな symlink 追跡ループ（plain `readlink` + `cd -P`。`readlink -f` 非依存で旧 macOS でも動く）で実体を辿り、実体と同階層の `lib/common.sh` を source する
- `pre-commit-lint.sh` — 同じ追跡で実体と同階層の `lint/` を見つける。循環 symlink はガードで検知し exit 2
- `mask-mcp-output.sh` — 同じ追跡で実体位置から `mask-secrets.sh`（不在時は `fstack-mask-secrets.sh`）を解決する

なお hook を fstack 外へ**物理コピー**して使う場合は、同階層の `lib/`（および `pre-commit-lint.sh` は `lint/`、`mask-mcp-output.sh` は `mask-secrets.sh`）も一緒にコピーすること（未同梱時の挙動は「共通ライブラリの公開契約」を参照）。

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

## 共通ライブラリ `lib/common.sh` と公開契約

各 hook は自身の実体ディレクトリの `lib/common.sh` を source して、jq のパス解決（`command -v` へ統一）・GNU/BSD コマンド差（`md5`/`md5sum`・`stat -f`/`stat -c`・`date -j -f`/`date -d`）の吸収・deny/ask JSON 発行を共通化する。OS 判定（`uname`）ではなくコマンドの成否で分岐する feature-detect のため、**macOS / Linux 双方で置換なしに動く**（従来の「Linux では stat/md5/date を置換」という注意書きは lib が吸収したため不要になった）。

利用時の前提（公開契約）:

- **コピー運用では `lib/common.sh` も同梱必須**。hook を別の場所へ物理コピーして使う場合、同階層に `lib/common.sh` が無いと、安全系（`validate-bash` / `validate-file-write` / `check-secret-patterns` / `pre-commit-lint`）は fail-closed で `exit 2`（恒久ブロック）になる。Option A（直接参照）・Option B（fstack の実体を指す symlink）はいずれも実体位置の `lib/` を辿るため同梱不要
- **安全系 hook は jq 必須**。jq が PATH に無い場合、安全系はブロック（`exit 2` の fail-closed）に倒す（従来の素通りから挙動変更）。非安全系（`check-implementation-routing` / `log-knowledge-read` / `check-debug-code` / `bootstrap-env` / `mask-mcp-output`）は役割に応じて best-effort continue または秘匿にフォールバックする

## 環境変数 override

| 環境変数 | 既定値 | 対象 hook | 用途 |
|---|---|---|---|
| `FSTACK_LOG_DIR` | `~/.claude/logs` | `log-knowledge-read` / `mask-mcp-output` | ログ出力先ディレクトリ |
| `FSTACK_CACHE_DIR` | `~/.claude/cache/bootstrap` | `bootstrap-env` | 環境情報キャッシュの格納先 |
| `FSTACK_ROUTING_WINDOW_SEC` | `1800`（30分） | `check-implementation-routing` | スキル起動痕跡を遡る秒数 |
| `CLAUDE_KNOWLEDGE_DIR` | `~/knowledge` | `log-knowledge-read` | 読み取りを記録するナレッジ置き場 |

いずれも未設定時は既定値で従来どおり動作する（後方互換）。

## bootstrap-env.sh の注意点

- GNU/BSD 差（`stat` / `md5`）は lib が吸収するため macOS / Linux 双方で動く。jq は `command -v jq` で解決し、jq 不在時は環境情報生成をスキップして正常終了する（`/opt/homebrew` 等の絶対パス直書きはしない）
- キャッシュ先: `${FSTACK_CACHE_DIR:-~/.claude/cache/bootstrap}/<md5(cwd)>.md`、24時間有効
- lib を解決できない環境（コピー運用で lib 未同梱等）ではキャッシュ鍵を計算できないため、キャッシュを使わず毎回生成にフォールバックする（出力内容は従来どおり、`exit 0`）
- 強制再生成: `bash hooks/bootstrap-env.sh --force < <(echo '{"cwd":"'$PWD'"}')`

## check-implementation-routing.sh の注意点

- skills.log のタイムスタンプ→epoch 変換は lib（`date -j -f` / `date -d` を feature-detect）が吸収するため macOS / Linux 双方で動く
- 遡る時間窓は `FSTACK_ROUTING_WINDOW_SEC`（既定 1800 秒 = 30分）で調整できる
- `skills.log` が存在しない環境では何もせず正常終了する（reminder を出すには `skill-log.sh` 等でスキル起動を記録している前提）
- 非ブロッキング advisory。lib/jq 解決失敗時は reminder を諦めて `exit 0` で継続する（極小スコープの編集でも無視して続行可能）

## log-knowledge-read.sh の注意点

- 記録対象パスは環境変数 `CLAUDE_KNOWLEDGE_DIR` で指定する（未設定時のデフォルトは `~/knowledge`）。自分のナレッジ置き場に合わせて設定する
- 対象外パスの Read は何も記録せず正常終了する
- ログ先: `${FSTACK_LOG_DIR:-~/.claude/logs}/knowledge.log`（`[YYYY-MM-DD HH:MM:SS] [KNOWLEDGE] READ <basename>` 形式）。lib/jq 解決失敗時は記録せず `exit 0`

## mask 系 hook の注意点

- `mask-secrets.sh` は JSON とプレーンテキストの両方に対応する。JSON では `"key": "value"` の引用符構造を保持したまま値だけを `[MASKED]` に置換するため、マスク後も `jq empty` を通る。加えて、JSON 文字列内にシリアライズされた JSON（MCP の `content[].text` 標準形。`\"key\":\"value\"`）の **1 段ネスト**もマスクする（値内のエスケープシーケンスを含む値も終端までまとめて置換。2 段以上のネスト・値が単独バックスラッシュで終わる形は対象外）
- `mask-mcp-output.sh` は自身の**実体位置**から `mask-secrets.sh` を解決する（POSIX ポータブルな symlink 追跡ループ。`readlink -f` 非依存）。直接参照・symlink・コピーのいずれの運用でも動く
  - 探索は2段フォールバック: `<実体ディレクトリ>/mask-secrets.sh` → 不在なら `<実体ディレクトリ>/fstack-mask-secrets.sh`（Option B の `fstack-` プレフィックス付きコピー運用に対応）
  - **全エラー経路で fail-closed**: payload の parse 失敗・masker 不在/異常終了・実体解決失敗・マスク後テキストが不正 JSON・最終 jq 失敗のいずれでも、素通しや部分マスクを渡さず固定秘匿メッセージ（`(reason: masker_missing|masker_failed|invalid_json|internal_error)`）に置換する。マスク前の元レスポンスは絶対に LLM へ返さない
  - ログ（`[MCP_MASK]` / `[MCP_MASK_FALLBACK]`）は best-effort。`HOME` 未設定等でログ不能でも、マスク/秘匿出力の返却は継続する（ログ不能を fail-open にはしない）

## カスタマイズ

- `validate-bash.sh` の禁止パターンを増やしたい → fork してプロジェクト独自の hook を作る
- 言語別の lint を追加したい → `hooks/lint/lint-<lang>.sh` を追加し、`pre-commit-lint.sh` の `run_lang` 呼び出しに追記
- マスキングのパターンを増やしたい → `mask-secrets.sh` の sed 行を追加

## 参考: 関連ルール

- `rules/security.md` の「スキル開発時の認証情報ハンドリング」が、これらの hook が想定する運用前提
- `rules/context-management.md` の「セッション運用ルール」が `bootstrap-env.sh` / `pre-compact-handover.sh` 等の前提
