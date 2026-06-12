# テスト・ベンチマーク ワークフロー

公式スクリプトパス:
```
SKILL_CREATOR=~/.claude/plugins/marketplaces/claude-plugins-official/plugins/skill-creator/skills/skill-creator
```

---

## evals.json の作成

スキルディレクトリ内に `evals/evals.json` を作成する:

```json
{
  "skill_name": "example-skill",
  "evals": [
    {
      "id": 1,
      "prompt": "ユーザーが実際に入力するプロンプト",
      "expected_output": "期待される出力の説明",
      "files": [],
      "expectations": [
        "出力に X が含まれている",
        "スキルのスクリプト Y を使用した"
      ]
    }
  ]
}
```

最初は `expectations` を空にしておき、eval実行中に追記する。

---

## eval の実行（with_skill / without_skill を同一ターンで並列）

ワークスペースを作成:
```
<skill-name>-workspace/
└── iteration-1/
    └── <eval-name>/
        ├── with_skill/outputs/
        ├── without_skill/outputs/   # 新規スキルの場合
        ├── old_skill/outputs/       # 既存スキル改善の場合
        ├── eval_metadata.json
        └── timing.json
```

**重要:** with_skill と without_skill のサブエージェントを**同一ターンで起動**する。
順番に起動すると待ち時間が無駄になる。

各サブエージェントへの指示例:
```
Execute this task:
- Skill path: <path-to-skill>  （なしの場合は省略）
- Task: <eval prompt>
- Input files: <files or "none">
- Save outputs to: <workspace>/iteration-1/<eval-name>/with_skill/outputs/
```

eval_metadata.json:
```json
{
  "eval_id": 0,
  "eval_name": "descriptive-name",
  "prompt": "タスクプロンプト",
  "assertions": []
}
```

サブエージェント完了通知には `total_tokens` と `duration_ms` が含まれる。
**この情報はここでしか取得できない** — 即座に `timing.json` に保存する:

```json
{
  "total_tokens": 84852,
  "duration_ms": 23332,
  "total_duration_seconds": 23.3
}
```

---

## アサーション作成（実行中に並行して行う）

実行完了を待たず、この間にアサーションを考えてユーザーに説明する。
良いアサーションの条件:
- 客観的に検証可能
- スキルが正しく機能したときだけ PASS になる（trivially pass しない）
- 名前を見れば何をチェックするか一目でわかる

主観的なスキル（文体・デザイン等）には無理にアサーションを設けない。

---

## 採点（Grader）

実行完了後、`eval-grader` サブエージェントを起動する（`subagent_type: "eval-grader"`、model: sonnet 固定）:

```
以下の eval のアサーションを採点してください:
- transcript_path: <run-dir>/transcript.md
- outputs_dir: <run-dir>/outputs/
- 結果を <run-dir>/grading.json に保存
```

grading.json のフィールド名は必ず `text`, `passed`, `evidence` を使う（viewerが依存）。

プログラムで検証できるアサーションはスクリプトで行う（目視より高速・再現性あり）。

---

## ベンチマーク集計

```bash
python -m scripts.aggregate_benchmark <workspace>/iteration-N --skill-name <name>
```

`$SKILL_CREATOR` ディレクトリで実行する。`benchmark.json` と `benchmark.md` が生成される。

---

## 評価ビューアの起動

```bash
nohup python $SKILL_CREATOR/eval-viewer/generate_review.py \
  <workspace>/iteration-N \
  --skill-name "my-skill" \
  --benchmark <workspace>/iteration-N/benchmark.json \
  > /dev/null 2>&1 &
VIEWER_PID=$!
```

iteration 2以降は `--previous-workspace <workspace>/iteration-<N-1>` を追加。

ビューアの構成:
- **Outputs タブ**: テストケースごとにプロンプト・出力・フィードバック入力欄
- **Benchmark タブ**: pass率・時間・トークンの定量比較

フィードバック完了後、ユーザーが「Submit All Reviews」を押すと `feedback.json` が保存される。

```bash
kill $VIEWER_PID 2>/dev/null
```

---

## フィードバックの読み取りと改善

```json
{
  "reviews": [
    {"run_id": "eval-0-with_skill", "feedback": "グラフに軸ラベルがない", "timestamp": "..."},
    {"run_id": "eval-1-with_skill", "feedback": "", "timestamp": "..."}
  ],
  "status": "complete"
}
```

空のフィードバック = 問題なし。具体的な指摘があった eval に集中して改善する。

改善後は新しい `iteration-<N+1>/` ディレクトリで再実行。

---

## ブラインドA/B比較（上級オプション）

2バージョンの出力をどちらがどちらか知らせずにエージェントが比較する:

1. `eval-comparator`（`subagent_type: "eval-comparator"`、model: sonnet 固定）でブラインド比較:
   ```
   - output_a_path: <run-dir-a>/outputs/
   - output_b_path: <run-dir-b>/outputs/
   - eval_prompt: <元のタスクプロンプト>
   - expectations: <アサーションリスト（省略可）>
   - 結果を comparison.json に保存
   ```

2. `eval-analyzer`（`subagent_type: "eval-analyzer"`、model: sonnet 固定）で事後分析:
   - **Mode A（事後分析）**: winner/loser のスキルと transcript を比較し、改善提案を生成
   - **Mode B（ベンチマーク分析）**: benchmark.json 全体のパターン・異常値を検出

各エージェントの詳細な入出力仕様は `~/.claude/agents/` の定義ファイルを参照。
