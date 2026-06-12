# PTC（Programmatic Tool Calling）

複数の独立したデータソースからの取得を並列化したい場合、Python スクリプトで ThreadPoolExecutor を使い Bash から呼び出すパターン。
Claude のツール呼び出しラウンドトリップを減らし、レイテンシとトークン消費を大幅に削減できる。

## いつ使うか

- 3つ以上の独立した外部API呼び出し（GitHub・課題管理ツール・ファイル読み込み等）を並列実行したい
- Claude のコンテキストにはフィルタ・集約済みの結果だけ入れたい
- サブエージェント起動のオーバーヘッドを避けたい

## いつ使わないか

- 外部呼び出しが1〜2個 → Bash/ツールで直接呼べば十分
- 結果に対して Claude の判断が必要 → サブエージェントの方が適切
- 主観的な変換（要約・文体変更）が含まれる → Claude に任せる

## パターン

```
scripts/{script-name}.py
├── Tool implementations  （各データソースの取得関数）
├── Parallel execution    （ThreadPoolExecutor で並列実行）
└── JSON output           （stdout に構造化データを出力）
```

SKILL.md からの呼び出し:
```bash
python3 ${CLAUDE_SKILL_DIR}/scripts/{script-name}.py [args]
```

## 設計ポイント

- 各取得関数は独立・冪等にする（他の関数の結果に依存しない）
- エラーは握りつぶさず `{"error": "..."}` として返す（スキル側で判断させる）
- `max_workers` はAPI先の負荷を考慮して設定（目安: 4〜5）
- 出力は JSON。Claude が解釈しやすい構造にする
- Anthropic SDK は不要（`subprocess` + `gh`/`curl` で十分なケースが多い）

## 実装例

ダッシュボード系スキル `dashboard/scripts/gather.py` — TODO・GitHub PR・マイルストーン・課題管理ツールの未読を 4並列で取得し JSON で返す（4並列で 10〜15s → 2〜3s に短縮）
