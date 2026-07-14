# Crystallize 出力フォーマット

Phase 3（レポート）・Phase 4（確認）・memory 新規作成で使う定型フォーマット。毎回このファイルを Read し、フォーマットを発明しない。

## 結晶化レポート（Phase 3）

```
## 結晶化レポート（{YYYY-MM-DD}）

### 分析期間
{開始日} 〜 {終了日}

### ログ概要
- スキル実行: {N} 件 / エラー: {M} 件 / プロンプト: {K} 件

### 新規パターン（記憶化候補）
1. **{パターン名}** — {観察内容} → 提案: {memory 内容}

### 既存 memory の評価
| ファイル | 旧環境 | 状態 | 提案 |
|---|---|---|---|
| `feedback_xxx.md` | - | 有効 | 維持 |
| `project_yyy.md` | ✓ | 陳腐化 | 淘汰 |

### ナレッジ昇格候補
| ファイル | プロジェクト | 出力先 | 理由 |
|---|---|---|---|
| `user_profile.md` | project-a, project-b | `user-profile.md` | 複数プロジェクトで重複 |

### ナレッジ サイズ見積もり（実測値を使う。プレースホルダのまま出さない）
| 区分 | 現在 | 追加後 | 上限 |
|---|---|---|---|
| 常時（3ファイル合計） | {n}行 | {n+x}行 | 120行 |
| 遅延 {ファイル名} | {m}行 | {m+y}行 | 100行/ファイル |

### 結晶化候補（skills への昇華）
1. **{ルール名}** — 対象: `skills/{name}/` / 内容: {追記するルール}

### 淘汰候補
- `memory/{file}.md` — 理由: {陳腐化の理由}

### 変更件数サマリ
作成・更新系 {X} 件（上限5） / 淘汰 {Y} 件（上限20）
```

## ユーザー確認フォーマット（Phase 4 冒頭）

```
以下のアクションを実行しますか？
  1. 新規 memory の作成（{N} 件）
  2. 既存 memory の更新（{M} 件）
  3. 陳腐化 memory の淘汰 → rules/file-operations.md に従い退避（{K} 件）
  4. skills への追記（{L} 件）
  5. ナレッジへの昇格（{P} 件）— 元の memory は退避
（y: 全実行 / 番号指定: 個別実行 / n: スキップ）
```

## memory frontmatter（新規作成時）

```markdown
---
name: {kebab-case-slug}
description: {一行の説明}
metadata:
  type: user | feedback | project | reference
---

{ルール・事実の記述}
**Why:** {この判断に至った理由・失敗の経験}
**How to apply:** {いつ・どこで適用するか}
```

既存ファイルには top-level `type:` 形式も残っている。**読む側は両形式に対応**し、新規作成は `metadata.type` 形式（現行ハーネスの標準）で統一する。

## project-context.md のセクション構造（昇格時）

```markdown
## project-a
Web アプリケーション。TypeScript + フレームワーク構成...

## project-b
API サーバー。バックエンド言語 + データベース構成...
```
