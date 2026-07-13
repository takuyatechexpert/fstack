# コントリビューションガイド

fstack はシンボリックリンクとマークダウンとシェルスクリプトだけで動く、外部依存ゼロのコレクションです。このガイドは、変更を安全に試し、壊さずに提案するための最小限の手順をまとめます。ビルド工程はなく、必要なのは bash と Python 3、そして shellcheck だけです。

## 開発環境をセットアップする

まず `--dry-run` で何が起きるかを確認してから、本実行します。dry-run は一切ファイルを変更せず、作成予定のリンクと既存との衝突だけを表示するので、自分の `~/.claude/` に何が入るかを事前に把握できます。

```bash
./setup --dry-run   # 実行内容のプレビュー（変更なし）
./setup             # 実際にシンボリックリンクを作成
```

既存のリンクを張り替えたい場合は `--force` を使います。`--force` は既存の実体ファイルを削除せずタイムスタンプ付きでバックアップしてから上書きするため、元に戻せます。

## 変更を検証する

変更の種類ごとに対応する検証を行い、すべて通ることを確認してから提案してください。これらは CI（`.github/workflows/ci.yml`）でも実行されるので、手元で通しておけば CI で落ちません。

シェルスクリプトを変更したら、構文チェックと静的解析の両方をかけます。shellcheck は CI と同じ `-S warning` でゲートしています。

```bash
for f in setup hooks/*.sh hooks/lib/*.sh hooks/lint/*.sh; do bash -n "$f"; done
shellcheck -S warning setup hooks/*.sh hooks/lib/*.sh hooks/lint/*.sh
```

hooks や setup の挙動を変えたら、同梱のテストスイートを実行します。

```bash
bash tests/run.sh
```

## スキル・ルール・エージェントを追加する

**スキル** は `skills/<カテゴリ>/<スキル名>/SKILL.md` を作成します。フロントマターは strict YAML でパースできる必要があるため、`description` にコロンや `#` を含むときは値全体をクォートしてください。全 SKILL.md の一括検証は次のコマンドです。

```bash
python3 -c "import yaml,glob; [yaml.safe_load(open(f).read().split('---',2)[1]) for f in glob.glob('skills/**/SKILL.md',recursive=True)]"
```

**ルール** は `rules/*.md` に置くだけで、インストール時に `fstack-` プレフィックス付きで `~/.claude/rules/` へリンクされます。特定の環境や組織に固有の値（人数・固定のブランチ運用など）は持ち込まず、汎用的な規約にとどめてください。

**エージェント** は `agents/*.md` に置き、フロントマターを lint で検証します。lint は ERROR があると終了コード 1 で失敗し、CI もそこで止まります。

```bash
python3 skills/meta/agent-creator/scripts/lint-agent.py agents/<name>.md
```

構成やインストールの仕組みの詳細は [ARCHITECTURE.md](ARCHITECTURE.md) を参照してください。

## コミットする

コミットメッセージの形式（プレフィックスと書き方）は同梱の [rules/git-workflow.md](rules/git-workflow.md) に従います。コミット前に `git status` と `git diff --cached` で、意図しないファイルや秘匿情報が含まれていないことを必ず確認してください。
