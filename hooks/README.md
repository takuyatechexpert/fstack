# fstack hooks

オプションのセキュリティ hook を配布する。利用者は **opt-in** で `~/.claude/settings.json` に組み込む。

`setup` スクリプトでは hook の自動インストールはしない。利用者が必要なものだけ選んで wire up する設計。

## 同梱フック

| ファイル | イベント | 用途 |
|---|---|---|
| `validate-bash.sh` | `PreToolUse` (Bash) | パイプ経由のシェル実行・eval・シークレット参照・curl 詳細トレース・set -x 等の危険パターンをブロック |
| `check-secret-patterns.sh` | `PreToolUse` (Bash) | `git commit/push` 時に、プロジェクト直下の `.claude/secret-patterns.txt` で定義された正規表現にマッチする内容があればブロック |
| `mask-secrets.sh` | パイプ経由（hook の出力をマスクする補助） | API キー・トークン・JWT・AWS キー・OAuth 等のリテラル値を `[MASKED]` に置換 |

## opt-in 手順

### 1. インストール（任意の方法）

#### Option A: 直接参照（推奨・更新が反映される）

そのまま fstack のパスを参照する。

#### Option B: `~/.claude/hooks/` に手動でシンボリックリンク

```bash
mkdir -p ~/.claude/hooks
ln -s "$(pwd)/hooks/validate-bash.sh"        ~/.claude/hooks/fstack-validate-bash.sh
ln -s "$(pwd)/hooks/check-secret-patterns.sh" ~/.claude/hooks/fstack-check-secret-patterns.sh
ln -s "$(pwd)/hooks/mask-secrets.sh"          ~/.claude/hooks/fstack-mask-secrets.sh
chmod +x hooks/*.sh
```

### 2. `~/.claude/settings.json` に追加

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/hooks/fstack-validate-bash.sh",
            "timeout": 5
          }
        ]
      },
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/hooks/fstack-check-secret-patterns.sh",
            "timeout": 10
          }
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

## カスタマイズ

- `validate-bash.sh` の禁止パターンを増やしたい → fork してプロジェクト独自の hook を作る
- 言語別の lint を hook に追加したい → 別ファイルとして追加し、settings.json に並列で wire up
- マスキングのパターンを増やしたい → `mask-secrets.sh` の sed 行を追加

## 参考: 関連ルール

- `rules/security.md` の「スキル開発時の認証情報ハンドリング」が、これらの hook が想定する運用前提
