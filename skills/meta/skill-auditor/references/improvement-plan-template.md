# IMPROVEMENT-PLAN.md テンプレート

Phase 2（改善計画策定）で対象スキルの `design/IMPROVEMENT-PLAN.md` を新規作成する際に使うテンプレート。
大規模スキル監査の実運用で作成された IMPROVEMENT-PLAN.md を原型としている。

---

```markdown
# {skill-name} スキル 改善計画書

作成日: {YYYY-MM-DD}
基準: `~/.claude/skills/my-skill-creator/SKILL.md` + `~/.claude/skills/skill-auditor/references/audit-checklist.md`

## 背景

{健康診断レポートのサマリ。なぜ監査に至ったか・主な問題点}

## 完了済み（参考）

- ✅ {既に完了している改善があれば列挙}

---

## Step 1: eval 基盤の構築 🔴 最優先（**必須**）

### 目的
劣化を主観でなく**定量**で判定できる状態にする。後続のすべての改善の効果測定に必須。

### 成果物
- `evals/evals.json` — テストプロンプト 2〜3 件
- `evals/expectations.json` — アサーション（**trivially pass を避ける**）
- with_skill のベンチマーク結果（ベースライン）

### 手順
1. `~/.claude/skills/my-skill-creator/references/eval-workflow.md` を読む
2. テストプロンプト設計（境界値・near-miss を含む）
3. with_skill のみ実行（既存スキル改善のためベースライン取得目的）
4. grader で採点 → ベンチマーク集計
5. ベースライン pass_rate を記録

### 完了条件
- with_skill の pass_rate が baseline として記録される
- 以降のすべての変更でこの数値が**劣化していない**ことを確認できる

### 想定工数
1〜2 セッション

---

## Step 2: {最優先の改善項目} 🔴

### 目的
{健康診断で見つかった最大の問題を解消}

### 現状の問題
{Why 込みで}

### 対応方針
{具体的な変更内容。A案/B案があれば比較表}

### 完了条件
- {定量的な完了条件}
- Step 1 の eval pass_rate が**劣化しない**（改善方向は期待するが最低条件は非劣化）

### 想定工数
{N} セッション

---

## Step 3: description 最適化 🟡

### 前提
- Step 1 の eval 完成
- Step 2 で本体が安定

### 手順
1. `~/.claude/skills/my-skill-creator/references/description-optimizer.md` を読む
2. `evals/trigger-eval.json` を作成: should_trigger 20件 / should_not_trigger 20件（near-miss 重視）
3. `run_loop.py` を実行（API キーあれば）or 手動最適化
4. best_description を SKILL.md に適用

### 完了条件
- should_trigger / should_not_trigger 双方で 90% 以上

---

## Step 4: Pitfalls セクション追加 🟡

### 目的
ドメイン固有の実体験ベースの罠を SKILL.md に明記。

### 手順
1. ユーザーに「過去にハマった事例」をヒアリング（**実体験ベースのみ採用**）
2. 各項目を 症状 / Why / ルール の形式で記述
3. 一般論・未発生の候補は追加しない（引き継ぎに残すのみ）

---

## Step 5: ログ粒度の改善 🟡

### 目的
事後分析可能な粒度に細分化。

### 手順
- 単一タグで済ませている箇所を分岐ごとに細分化
- 各分岐に `skill-log.sh` 呼び出しを追加

---

## Step 6: references/ の棚卸し 🟢

### 確認項目
- 各ファイルの行数（500 行超なら分割）
- モード別・機能別で重複がないか

---

## Step 7: design/ の整理 🟢

### 手順
1. `design/` に残っている SPEC 等を SKILL.md と突合
2. 全項目反映済みなら削除
3. 未反映があれば他 Step に統合

---

## 全体スケジュール

| Step | 優先度 | 工数 | 累計 |
|---|---|---|---|
| 1. eval 基盤 | 🔴 | 2 | 2 |
| 2. {最優先} | 🔴 | {N} | {累計} |
| 3. description | 🟡 | 1 | {累計} |
| 4. Pitfalls | 🟡 | 0.5 | {累計} |
| 5. ログ粒度 | 🟡 | 0.3 | {累計} |
| 6. references | 🟢 | 1 | {累計} |
| 7. design | 🟢 | 0.3 | {累計} |

## 進捗管理

各 Step 完了時に本ファイル末尾に `## Done` セクションで記録する。

## Done

<!-- Step 完了ごとに追記: 変更点 / Why / pass_rate 差分 / 残課題 -->
```
