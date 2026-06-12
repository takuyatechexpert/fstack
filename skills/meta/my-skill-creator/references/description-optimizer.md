# 説明文自動最適化

スキルのフロントマター `description` は Claude がスキルを使うかどうかを決める主要な仕組み。
スキルが完成したら、この最適化を実施することを提案する。

公式スクリプトパス:
```
SKILL_CREATOR=~/.claude/plugins/marketplaces/claude-plugins-official/plugins/skill-creator/skills/skill-creator
```

---

## Step 1: Trigger eval クエリを生成

20件のクエリを作成し JSON に保存する:

```json
[
  {"query": "ユーザーが実際に入力する具体的なプロンプト", "should_trigger": true},
  {"query": "スキルを使わないべき別のプロンプト", "should_trigger": false}
]
```

### 良いクエリの書き方

**悪い例（NG）:**
```
"Format this data"
"Extract text from PDF"
```

**良い例（OK）:**
```
"ok so my boss just sent me this xlsx file (its in my downloads, called something like
'Q4 sales final FINAL v2.xlsx') and she wants me to add a column that shows the profit
margin as a percentage. The revenue is in column C and costs are in column D i think"
```

良いクエリの特徴:
- 具体的（ファイルパス・列名・会社名・URL を含む）
- 個人的な背景がある
- 小文字・略語・カジュアルな話し方が混じる
- 長さのバリエーションがある
- **エッジケースに集中する**（明確なケースではなく紛らわしいケース）

### should_trigger（8〜10件）
- 同じ意図の異なる言い回し（フォーマルとカジュアルの両方）
- スキル名や形式を明示しないが明らかに必要なケース
- 珍しいユースケース
- 他スキルと競合するが本スキルが勝つべきケース

### should_not_trigger（8〜10件）
- **最も重要: near-miss**（キーワードは重なるが別のスキルが適切なケース）
- 曖昧な言い回しでキーワードマッチするが実際は違うケース
- 「Write a fibonacci function」のような明らかに無関係なケースは避ける（テストにならない）

---

## Step 2: ユーザーに確認・編集させる

HTML テンプレートを使ってクエリをレビューしてもらう:

1. `$SKILL_CREATOR/assets/eval_review.html` を読み込む
2. プレースホルダーを置換:
   - `__EVAL_DATA_PLACEHOLDER__` → JSON配列（クォートなし）
   - `__SKILL_NAME_PLACEHOLDER__` → スキル名
   - `__SKILL_DESCRIPTION_PLACEHOLDER__` → 現在の description
3. `/tmp/eval_review_<skill-name>.html` に書き込んで開く: `open /tmp/eval_review_<skill-name>.html`
4. ユーザーが編集・追加・削除後「Export Eval Set」をクリック
5. `~/Downloads/eval_set.json` をダウンロード（複数ある場合は最新版）

**このステップは重要。クエリの質が最終的な説明文の質を決める。**

---

## Step 3: 最適化ループの実行

```bash
cd $SKILL_CREATOR
python -m scripts.run_loop \
  --eval-set <path-to-trigger-eval.json> \
  --skill-path <path-to-skill> \
  --model <現在のセッションのモデルID> \
  --max-iterations 5 \
  --verbose
```

`--model` には現在のセッションで使用しているモデルID（システムプロンプトに記載）を指定。
バックグラウンド実行し、定期的に tail で進捗をユーザーに伝える。

### 内部処理

1. eval set を 60% train / 40% test に分割
2. 現在の description を各クエリで**3回**実行（統計的信頼性のため）
3. Claude（拡張思考）が失敗パターンから改善案を提案
4. 新しい description を train + test の両方で再評価
5. 最大5イテレーション繰り返す
6. **test スコアが最も高いものを選択**（train スコアではない → 過学習防止）

---

## Step 4: 結果を適用

スクリプト完了後、出力 JSON の `best_description` を取得:

```json
{
  "best_description": "最適化された説明文テキスト",
  "best_score": 0.92,
  ...
}
```

SKILL.md のフロントマターを更新し、ユーザーに before/after とスコアを報告する。

---

## トリガーの仕組みについて

Claude はスキルリストの name + description を見てスキルを使うか判断する。
**重要:** 単純な1ステップのタスク（「このPDFを読んで」）では、Claudeが基本ツールで直接処理できるためスキルをトリガーしない場合がある。

→ eval クエリは複数ステップを要する実質的な依頼にする。

---

## APIキーがない場合の手動最適化

`run_loop.py`（Step 3）は Anthropic API を直接呼び出すため、`ANTHROPIC_API_KEY` が必要。
APIキーがない環境では、Step 1〜2 のクエリ作成・レビューまでを行い、以下の手動フローで代替する:

1. Step 1〜2 で eval クエリセットを作成・レビュー
2. `run_loop.py` を **1イテレーションだけ実行**し、train/test の失敗パターンを取得（APIキーがあれば）
   - APIキーがなければ、クエリを見ながら「この表現でトリガーするか？」を自分で判断する
3. 失敗パターンから description を手動で改善:
   - recall が低い → トリガーフレーズの追加、冒頭をユーザー視点の説明に変更、広く捕捉する文言を追加
   - precision が低い → near-miss スキルとの差別化文言を追加、NOT トリガーの条件を明記
4. 改善後、実際のセッションで試して効果を確認
