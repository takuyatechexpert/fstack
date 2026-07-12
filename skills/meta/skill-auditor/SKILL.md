---
name: skill-auditor
description: "既存スキルの健康診断と改善計画策定スキル。my-skill-creatorの基準と照合して改善余地を洗い出し、evalでベースライン取得→Step化→劣化検出しながら改善→design/棚卸しまでを一貫して進める。スキルが肥大化してきた時のチェックにも使える。ユーザーが「スキル監査」「skill-auditor」「〇〇スキルの改善」「このスキル肥大化してる」「スキルの健康診断」「スキルを見直したい」「スキル棚卸し」「スキルのリファクタリング」と言ったときに使用する。以下では起動しない: スキル新規作成（my-skill-creator領域）、スキル自体の使い方質問、単一ファイルの軽微な修正。"
---

# Skill Auditor

既存スキルを「健康診断 → 改善計画 → Step 単位で実行 → クローズ」まで一貫して進めるスキル。大規模スキル（500行超）の段階的な改善運用をテンプレート化したもの。

## 基準の原典

- **スキル構築の基準は `~/.claude/skills/my-skill-creator/references/skill-standards.md` を単一の真実のソースとする**。本スキルは基準に対して「計測・差分検出・改善計画策定」を担当する
- 基準を変更する必要が出た場合は `skill-standards.md` を編集する（本スキル側には基準を書かず、参照のみ）

## 参照ファイル

各 Phase の冒頭で該当ファイルを **Read で毎回読み込んで一次情報として扱う**（要約・過去会話からの再現ではなく、現ファイルを正とする）。

| 参照ファイル | 読むタイミング |
|---|---|
| `~/.claude/skills/my-skill-creator/references/skill-standards.md` | Phase 0 で対象確認後・Phase 1 冒頭 |
| `~/.claude/skills/skill-auditor/references/audit-checklist.md` — 基準の**計測方法**（コマンド・判定閾値・出力フォーマット） | Phase 1 冒頭 |
| `~/.claude/skills/skill-auditor/references/improvement-plan-template.md` — IMPROVEMENT-PLAN.md テンプレート | Phase 2 冒頭 |
| `~/.claude/skills/skill-auditor/references/step-patterns.md` — 典型的な Step パターン集 | Phase 2 の Step 設計時 |

## 前提

- 対象スキル名は **ユーザーが明示指定する**（「review-pr の監査して」等）。未指定なら Phase 0 冒頭で質問する
- 対象スキルは原則 `~/.claude/skills/{name}/` 配下に存在する（dotfiles 等で別管理している場合は実体パスを変更先として使う）

---

## ワークフロー

### Phase 0: 対象スキル読み込み

1. ユーザーに対象スキル名を確認（未指定なら聞く）
2. 以下を **同一メッセージ内で Read を並列発行** して取得:
   - `~/.claude/skills/{name}/SKILL.md`
   - `~/.claude/skills/{name}/references/*.md`（Glob で存在確認してから対象を並列 Read）
   - `~/.claude/skills/{name}/design/*.md`（存在すれば）
   - `~/.claude/skills/{name}/evals/*.json`（存在すれば）
   - `~/.claude/skills/my-skill-creator/SKILL.md` と `references/skill-standards.md`（基準の再確認）
3. ファイル構成を把握する（scripts/ / assets/ の有無、references/ の肥大度）

**作業範囲**: Phase 0 は Read のみ。Edit/Write は Phase 2 の合意後に開始する。

### Phase 1: 基準照合（健康診断）

`references/audit-checklist.md` を Read し、そこに記載の計測コマンドと判定閾値に従って一つずつ判定する（計測コマンドの原典は audit-checklist.md 側に置き、本 SKILL.md では再記述しない）。

結果を以下のフォーマットで出力する。

```markdown
## 健康診断レポート: {skill-name}

### メトリクス
| 項目 | 基準 | 実測 | 判定 | 計測コマンド |
|---|---|---|---|---|
| SKILL.md 行数 | ≤500 | {N} | ✓/⚠/✗ | `wc -l {path}` |
| SKILL.md トークン | ≤5000 | {N} | ✓/⚠/✗ | `python scripts/count_tokens.py {path}` |
| description 1文化 | 可能 | {可否} | ✓/✗ | frontmatter 手動確認 |
| Pitfalls セクション | あり | {有無} | ✓/✗ | `grep -c "^## Pitfalls" {path}` |
| eval 基盤 | あり | {有無} | ✓/✗ | `ls {skill}/evals/` |
| references 最大行数 | ≤500 | {N} | ✓/⚠/✗ | `wc -l {skill}/references/*.md` |
| 責務混在 | なし | {観察} | ✓/⚠/✗ | SKILL.md 目視 + description 精査 |

### 所見
- {具体的な問題点を箇条書き。Why 込みで}

### 推奨 Step
- Step 1: ...
- Step 2: ...
```

**作業範囲**: Phase 1 の出力は診断レポートのみ。実装（Edit/Write）は Phase 2 で計画合意後に開始する。

**再現性の担保**: 同じスキルに対して Phase 1 を再実行したとき判定が一致するよう、各メトリクスは必ず上表の「計測コマンド」で得た値を使用する（目視による推定値は使用しない）。

### Phase 2: 改善計画策定

1. `references/improvement-plan-template.md` を Read し、`{target}/design/IMPROVEMENT-PLAN.md` をドラフト
2. `references/step-patterns.md` を Read し、該当パターンを選んで Step 化
3. 各 Step に以下を付与: 目的 / 手順 / 完了条件 / 想定工数 / 優先度（🔴🟡🟢）
4. **Step 1 は常に eval 基盤構築とする**（eval なしでは後続 Step の劣化検出が不可能なため）
5. ユーザーに計画を提示し、優先度・工数・スコープの合意を取る
6. 合意後に `{target}/design/IMPROVEMENT-PLAN.md` を Write

### Phase 3: Step 単位の実行

Step を **1 つずつ** 進める。各 Step で:

1. 実施内容をユーザーに提示 → 承認を取る
2. 実装（Edit/Write）
3. eval 再計測（Step 1 完了後のみ）:
   - コマンド例: `python ~/.claude/skills/{name}/evals/run_eval.py --baseline evals/baseline.json --out evals/step-{N}.json`
   - ベースライン（Step 1 で取得した `evals/baseline.json`）と比較し、劣化がないことを確認
4. `IMPROVEMENT-PLAN.md` の `## Done` セクションに **数値で** 記録する:
   - 変更点 / Why / pass_rate 差分（baseline vs 現在） / tokens 差分 / duration 差分 / 残課題
5. 次 Step へ

**劣化検出時**: `pass_rate` が下がったら即ロールバックを提案する。

**`run_loop.py`（description 自動最適化）の扱い**:
- 前提: `run_loop.py` は公式 skill-creator プラグイン（`~/.claude/plugins/marketplaces/claude-plugins-official/plugins/skill-creator/skills/skill-creator`）側の eval 実行機構。導入されていない環境ではスキップし、下記の手動最適化に切り替える
- 公式プラグイン導入済み かつ `ANTHROPIC_API_KEY` が環境にある場合: `SKILL_CREATOR` ディレクトリで `scripts/run_loop.py` を実行する（対象スキル名・イテレーション数などの引数は導入した公式 skill-creator プラグインの `--help` / README に従う）
- 未導入 または APIキー未設定の場合: 手動最適化に切り替え、`~/.claude/skills/my-skill-creator/references/description-optimizer.md` の「APIキーがない場合の手動最適化」を Read して手順に従う

### Phase 4: クローズ

全 Step 完了後に以下を実施する。

1. **design/ 棚卸しの合意フロー**:
   - (a) `{target}/design/` を Glob し、IMPROVEMENT-PLAN.md 以外のファイル（SPEC / 古いメモ）をリストアップ
   - (b) 各ファイルを SKILL.md / references と突合し、内容が反映済みか判定
   - (c) **「削除対象 SPEC リスト」としてユーザーに提示し承認を得る**
   - (d) 承認後に削除（破壊的操作は `rules/file-operations.md` の運用方針に従う）
2. 残タスクを **ブロック解除トリガー表** に整理:
   ```markdown
   | 項目 | ブロック解除トリガー |
   |---|---|
   | 実動作検証 | 次回の実セッション起動時 |
   | 自動最適化 | ANTHROPIC_API_KEY セット時 |
   | Pitfalls 追加 | 実事故発生時 |
   ```
3. `Skill(skill="handover")` で引き継ぎ文書を生成（現セッションの Step 履歴・残タスクを渡す）
4. ログ記録

---

## ログ記録

- 開始時: `~/.claude/hooks/skill-log.sh skill-auditor START "{target-skill}"`
- Phase 1 完了時: `~/.claude/hooks/skill-log.sh skill-auditor DIAGNOSED "{target} score:{pass}/{total}"`
- Step 完了時: `~/.claude/hooks/skill-log.sh skill-auditor STEP_DONE "{target} step:{N} pass_rate:{X}"`
- クローズ時: `~/.claude/hooks/skill-log.sh skill-auditor CLOSED "{target} steps:{N}完了"`
- エラー時: `~/.claude/hooks/skill-log.sh skill-auditor ERROR "{エラー内容}"`

## 運用上の原則

- 対象スキルが my-skill-creator 本体の場合は「基準の妥当性自体を問う」視点に切り替える（自己言及の回避）
- 大規模リファクタ（責務分割など）は iteration workspace で eval を回してから本体反映する（`{skill-name}-workspace/iteration-N/` の運用パターン）
- `description` 変更時は Recall / Precision の予測値を併記して提示する（`trigger-eval.json` の手動運用）

## Pitfalls（ハマりどころ）

### 1. eval pass_rate が天井（1.0）に張り付いた後の改善判定

**症状**: iteration-2 以降で 29/29=1.0 等の天井に達すると、description や本体を変えても改善を数値で検出できなくなる。

**Why**: アサーションが「セクション見出しの存在」など粗い粒度だと trivially pass しやすく、実データ品質を測れない。

**ルール**: 天井到達時はアサーションの粒度を上げる（負のアサーション・実データ内容・境界条件を追加）。それでも天井なら eval 設計自体を見直す。

### 2. design/ の SPEC は実装後に棚卸しする

**症状**: 実装済みの SPEC が `design/` に残り続け、次の監査時に「まだ未反映か？」と誤認される。

**Why**: SPEC は実装前の設計書。実装完了後は SKILL.md / references が真実のソースになり、SPEC は二重管理の温床になる。

**ルール**: Phase 4 の棚卸しで必ず SPEC を SKILL.md と突合 → 全反映済みなら削除対象リストに載せ、ユーザー承認を得てから退避する。`design/` に原則残すのは `IMPROVEMENT-PLAN.md` のみ。

### 3. Pitfalls は実事故ベースのみ採用する

**症状**: 一般論で「ハマりそう」な項目を Pitfalls に詰め込むと冗長化し、本当に重要な罠が埋もれる。

**Why**: Claude が既知の一般論を書いても行動は変わらない。実事故ベースの Why があって初めて判断材料になる。

**ルール**: Phase 3 で Pitfalls 追加 Step を設けた場合は、ユーザーに「過去にハマった実例」をヒアリングし、得られた応答のみを本文採用する。未発生の候補はクローズ時の引き継ぎ文書に「候補」として記載する。
