---
name: crystallize
description: "経験の結晶化とナレッジ蒸留スキル。ログと memory を分析し、繰り返すパターンを memory・skills・ナレッジベースに昇華させ、蒸留済み・陳腐化したメモリを退避してクリーンに保つ。週次の振り返りに使用する。ユーザーが「結晶化」「crystallize」「振り返り」「週次レビュー」「知識の棚卸し」「記憶の棚卸し」「memoryを整理して」「蒸留」「distill」「ナレッジ同期」「ナレッジに昇華」と言ったときに使用する。以下では起動しない: セッション引き継ぎ（handover が担当）、スキル自体の棚卸し・改善（skill-auditor が担当）。"
---

# Crystallize（結晶化・蒸留）

ログと記憶を分析し、繰り返すパターンを memory・skills・ナレッジベースに昇華させるワークフロー。蒸留済み・陳腐化したメモリは `~/.claude/projects/*/memory/` から退避してクリーンに保つ。

## 参照ファイル

必要になった時点で Read で最新内容を読み込む（要約・記憶からの再現は禁止）。

| ファイル | 読むタイミング |
|---|---|
| `~/.claude/skills/crystallize/references/report-format.md` | Phase 3 のレポート出力前（必須） |
| `~/.claude/skills/crystallize/references/nfd-architecture.md` | 配置先（憲法層/技能層/経験層）の判断に迷ったとき |

## ナレッジベース

場所は `~/.claude/knowledge/`。ファイル構成は `KNOWLEDGE.md`（インデックス）を SSOT とし、実行時に Read して現構成を把握する（スキル側にファイル名を固定列挙すると実態とドリフトするため）。

**サイズ規律:**

- 常時読み込み3ファイル（user-profile / work-patterns / collaboration）: 合計 120 行以内
- 遅延読み込み: 1ファイル 100 行以内（ファイル数は KNOWLEDGE.md で管理）
- 超過しそうな場合は追記より先に、既存エントリの圧縮・淘汰を提案する

## 受け入れ基準（1回の実行で守ること）

- 作成・更新・skills 追記は合計 5 件まで。淘汰（退避）のみ 20 件まで可（バックログ解消を優先）
- 削除は直接の `rm` を避け、`rules/file-operations.md` に従って退避する（git rm / システムのゴミ箱 / 退避ディレクトリへの mv）
- 昇格・淘汰したメモリは `MEMORY.md` インデックスからも除去する
- ナレッジには環境非依存の表現を書く（ハードコードパスはプレースホルダ化）。プロジェクトの「今」の情報（期限・未完タスク等）は memory 側に留める
- ファイル変更（memory 作成・更新・退避、ナレッジ追記、skills 追記）はすべて Phase 4 のユーザー確認後に実行する
- 変更はステージまでで止め、`commit` / `push` はユーザーに委ねる

## ワークフロー

### Phase 1: 収集・分析（サブエージェント並列委譲）

ログ（1〜4MB）と memory（100件超）はメインコンテキストで直接 Read しない。以下のサブエージェント（general-purpose）を**同一メッセージ内で並列起動**し、構造化サマリだけを受け取る。各エージェントには意図・対象パス・抽出コマンド・返却形式を明示して渡す。

#### 1-A. ログ分析エージェント（1体）

**渡すもの**: 下記コマンド、返却形式。

```bash
SINCE=$(date -v-7d +%Y-%m-%d)
for f in skills.log tool-failures.log prompts.log; do
  echo "=== $f ==="
  awk -v s="$SINCE" '/^\[20[0-9][0-9]-/{cur=substr($0,2,10)} cur>=s' ~/.claude/logs/$f
done
```

（タイムスタンプ行で現在日付を更新する awk なので、prompts.log の複数行エントリも正しく拾える。ログは追記型で直近分は末尾にある）

**返却形式**: ①繰り返しパターン候補（同一エラー2回以上・同種の修正指示・繰り返された判断） ②件数サマリ（スキル実行 / エラー / プロンプト）

#### 1-B. memory 棚卸しエージェント（1〜3体）

まず件数を把握し、60件以下なら1体、超えるならプロジェクト dir 単位で分割して最大3体に委譲する。

```bash
find ~/.claude/projects/ -path "*/memory/*.md" ! -name "MEMORY.md" | wc -l
```

**渡すもの**: 担当ファイル一覧、frontmatter の読み方、返却形式。

- frontmatter の type は top-level `type:` と `metadata.type` の**両形式が実在する**ため両対応で読む
- 現在の `$HOME` と一致しないパス形式のプロジェクト dir（旧ユーザー名由来のパス形式等）は**旧環境フラグ**を付ける（昇格・淘汰の優先候補）

**返却形式**: `| パス | name | type | 要旨(1行) | 旧環境 | 提案(維持/昇格/更新/淘汰) |` のテーブル

#### 1-C. メインで直接 Read するもの（小さいファイルのみ）

`~/.claude/knowledge/KNOWLEDGE.md` と、そこに列挙された各ナレッジファイル（合計300行程度）。

### Phase 2: 結晶化判定

Phase 1 の返却を突合し、各候補の段階を判定する。

| 段階 | 条件 | アクション |
|---|---|---|
| 観察 | 初回の気づき | レポート記載のみ（memory には入れない） |
| 記憶化 | 2回以上発生 or ユーザーが明示 | memory を作成 |
| ナレッジ昇格 | プロジェクト横断で汎用的 | ナレッジへ蒸留し、元 memory は退避 |
| 結晶化 | 1ヶ月以上安定 | `skills/*/references/` に移植 |
| 淘汰 | 陳腐化・不要 | `rules/file-operations.md` に従って退避 |

**type → ナレッジファイル対応**（昇格時の出力先）

| メモリ type | 内容 | 出力先 |
|---|---|---|
| `user` | 役割・専門性 | user-profile.md |
| `user` | Claude との好み | collaboration.md |
| `feedback` | 働き方・習慣 | work-patterns.md |
| `feedback` | Claude への指示 | collaboration.md |
| `feedback` | 技術的判断 | tech-decisions.md |
| `project` / `reference` | プロジェクト文脈・外部参照 | project-context.md ほか（KNOWLEDGE.md の現構成に従う） |

**蒸留ルール**: ①環境非依存化 ②重複排除（最も詳しい記述に統合） ③鮮度優先 ④サイズ規律遵守

### Phase 3: レポート出力

`references/report-format.md` を Read し、そのフォーマットで出力する（フォーマットを発明しない）。

### Phase 4: ユーザー確認 → アクション実行

report-format.md の確認フォーマットを提示し、承認された項目のみ実行する:

- **memory 作成/更新** — frontmatter 付き md を作成・Edit し、`MEMORY.md` にポインタを追記/更新する
- **淘汰** — `rules/file-operations.md` に従って退避し（git rm / システムのゴミ箱 / 退避ディレクトリへの mv）、`MEMORY.md` からも除去する
- **skills への追記** — 対象スキルの `references/` または SKILL.md に追記する。既存構造を尊重する
- **ナレッジ昇格** — 環境非依存に書き換えて追記 → `KNOWLEDGE.md` 更新 → サイズ規律確認 → 元 memory を退避し `MEMORY.md` からも除去（複数プロジェクトに同内容があれば全て）

### Phase 5: セルフ検証

```bash
bash ~/.claude/skills/crystallize/scripts/verify-integrity.sh
```

サイズ規律・インデックス整合性（MEMORY.md / KNOWLEDGE.md ⇄ 実ファイルの双方向）を機械判定する。ナレッジの場所が既定（`~/.claude/knowledge/`）と異なる場合は環境変数 `KNOWLEDGE_DIR` または第1引数で渡す。✗ が出たら該当箇所を修正してから完了とする。

## ログ記録

起動ログは PostToolUse (Skill) hook が自動記録する。完了時に分岐タグで記録する:

- 変更実行: `~/.claude/hooks/skill-log.sh crystallize COMPLETED "memory:+{N}/-{M} knowledge:+{P} skills:+{Q}"`
- 変更提案なし: `~/.claude/hooks/skill-log.sh crystallize NO_CHANGES "分析のみ・候補なし"`
- 全スキップ: `~/.claude/hooks/skill-log.sh crystallize SKIPPED_BY_USER "候補{N}件"`
- エラー: `~/.claude/hooks/skill-log.sh crystallize ERROR "{内容}"`

## Pitfalls（実事故ベース）

### 1. ナレッジのパスを記憶で書かない

**症状**: スキル内にハードコードされた誤ったパスへ knowledge が新規作成されうる。環境移行でディレクトリが移動してもスキル内のハードコードパスは追従しない。

**Why**: 退避用など別用途のディレクトリが実在すると、誤パスへの書き込みが成功してしまい気づけない。

**ルール**: 書き込み前に対象ディレクトリの実在と KNOWLEDGE.md の存在を確認する。無ければ作成せず、ユーザーに正しいパスを確認する。

### 2. 巨大ログを Read ツールで読まない

**症状**: ログを「並列 Read」で取ると、skills.log 等は 1〜4MB あり Read は先頭約2000行で打ち切られるため**直近分（ファイル末尾）に一切届かない**まま分析完了に見えてしまう。

**Why**: ログは追記型で新しいエントリほど末尾にある。Read は先頭から読む。

**ルール**: ログは必ず Bash の日付窓抽出（Phase 1-A のコマンド）で取得する。抽出結果が数百行を超えるなら分析ごとサブエージェントに委譲する。

## オペレーション原則

- ファイル変更はユーザー確認ゲート（Phase 4）を経由してのみ実行する
- ログファイルが存在しなくても memory 棚卸し（1-B）は実施する
- skills への追記は対象スキルの設計方針を尊重し、既存構造を保つ
