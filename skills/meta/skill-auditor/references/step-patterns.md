# Step Patterns

典型的な改善 Step のパターン集。大規模スキル監査の実運用（Step 1〜7）で実証済みのテンプレート。
Phase 2 の改善計画策定時にカタログとして参照する。

---

## Pattern 1: eval 基盤構築（**必須 Step 1**）

### 適用条件
`evals/` が存在しないスキル全般。例外なし。

### 成果物
- `evals/evals.json`（テストプロンプト 2〜3 件）
- `evals/expectations.json`（アサーション）
- ベースライン pass_rate の記録

### 落とし穴
- **Trivially pass**: 「セクション見出しの存在」だけでアサーションを作ると全件通ってしまう。実データ内容・負のアサーション・境界値を混ぜる
- **ドライラン**: eval サブエージェント環境では Bash 権限制限で実ファイル操作できない。pass_rate 1.0 は「実データを収集していない」可能性を疑う

### 実績例
大規模スキルで iteration-1 が 18/18=1.0（trivially pass）→ 強化版アサーションで 25/29=0.862 に正規化。改善余地が可視化された。

---

## Pattern 2: 責務分割（肥大化スキルの分離）

### 適用条件
- SKILL.md > 500 行
- description を1文で書けない
- 無関係な責務が混在（例: 情報収集 + アクション実行）

### 手法
A案/B案を比較して選ぶ:

- **A案: references/ に分離（軽量）** — 本体に「該当ファイルを Read して実行」とだけ書く
- **B案: 別スキルに切り出し（本格）** — 親スキルから Skill ツールで invoke

### 完了条件
- SKILL.md が目標行数以内
- description が1文化
- eval pass_rate が**劣化していない**（改善方向は期待）

### 実績例
B案採用で本体 169 → 106 行に縮小し、付随アクションを別スキルに新設。iteration-2 pass_rate 25/29 → 29/29（劣化なし、むしろ改善）。

---

## Pattern 3: description 最適化（Recall/Precision）

### 適用条件
- 誤発火・取りこぼしの報告がある
- description がキーワード列挙のみでカジュアル言い換えが不足
- NOT 条件が書かれていない

### 手法
1. `evals/trigger-eval.json` 作成: should_trigger 20 / should_not_trigger 20
2. near-miss（誤発火しやすいクエリ）を重点的に入れる
3. `run_loop.py` または手動最適化
4. before/after の Recall/Precision を予測値として記録

### 完了条件
Recall / Precision 双方 ≥ 90%

### 実績例
手動最適化で Recall 65%→100% / Precision 59%→94%。意図明示 + カジュアル言い換え + NOT 条件の3点が効いた。

---

## Pattern 4: Pitfalls 追加（**実体験ベースのみ**）

### 適用条件
ドメイン固有の罠が SKILL.md に書かれていない。

### 手法
1. ユーザーに「過去にハマった事例」をヒアリング
2. 各項目を **症状 / Why / ルール** 形式で記述
3. 一般論・未発生の候補は追加せず、引き継ぎに残すのみ

### 実績例
実事故ベースで 2 件採用（loop 再実行時の冪等性違反 / コマンド引数の誤用パターン）。候補リストから 6 件は実体験ベースでないため保留。

---

## Pattern 5: ログ粒度の改善

### 適用条件
`skill-log.sh` 呼び出しが単一タグで雑に済まされている。

### 手法
各分岐に独立タグを割り当てる:

- Before: `TAG: posted|skipped` の2値
- After: `TAG: skipped:weekend` / `TAG: skipped:already_posted` / `TAG: posted` / `TAG: failed:{reason}` の4分岐

### 完了条件
`grep` だけで事後分析・集計できる粒度

### 実例
ダッシュボード系スキルで `MODE_A / MODE_B / MODE_C / ...` を分岐ごとにタグ化。事後分析が ndjson 集計のみで可能になり、grep で「どの条件で skip されたか」「どこで failed したか」が即座に追えるようになる。

---

## Pattern 6: references/ の棚卸し

### 適用条件
- references/ の個別ファイルが 500 行超
- モード別・機能別で読む必要のある部分が混在

### 手法
モード別に独立ファイルに分割:

- Before: `agent-prompts.md`（586 行、全モード混在）
- After: `agent-prompts-mode-a.md`（290 行）+ `agent-prompts-mode-b.md`（300 行）

SKILL.md の参照箇所もモード別に分岐記述。

### 実績例
朝/夕など実行モードで共有部分がほぼなく、モードごとに片方しか読まないため独立ファイル化。実行時のコンテキスト負荷が約半減。

---

## Pattern 7: design/ の整理（クローズ時）

### 適用条件
- `design/SPEC-*.md` 等の実装前仕様書が残っている
- IMPROVEMENT-PLAN.md 以外のドキュメントが design/ にある

### 手法
1. SPEC の各項目を SKILL.md / references と突合
2. 反映済みチェック表を作る（項目 / 反映先 / 状態）
3. 全項目反映済みなら削除、未反映があれば他 Step に統合
4. design/ は `IMPROVEMENT-PLAN.md` のみ保持する方針に

### 実績例
`SPEC-safety-improvements.md` を削除。3 項目（ターン制限 / 構造化メタデータ / フォールバック）が全て現行 SKILL.md / references/agent-prompts-*.md に反映済みであることを突合で確認。

---

## Step 選択フローチャート

```
Phase 1 の健康診断結果から:

eval なし? → Step 1 必須
SKILL.md > 500行 or 責務混在? → Step 2（責務分割）
description の Recall/Precision 予測 < 90%? → Step 3
Pitfalls セクションなし + 実事故あり? → Step 4
ログが単一タグ? → Step 5
references 500行超? → Step 6
design/ に実装済み SPEC 残存? → Step 7（クローズ時）
```

優先度: 🔴 = Step 1,2 / 🟡 = Step 3,4,5 / 🟢 = Step 6,7
