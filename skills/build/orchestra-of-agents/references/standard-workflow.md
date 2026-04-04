# 標準構成ワークフロー詳細

## Wave 0: 設計契約（leader のみ）

```
leader: インターフェース契約書を作成 → ユーザー承認
```

1. タスクを分析し、以下の4項目を含む契約書を作成:
   - **エンティティ関係図**: 主要構造体/型の関係と ID の流れ
   - **モジュール境界の API**: impl 間の呼び出しインターフェース（関数シグネチャ + 戻り値の意味）
   - **データフロー**: イベントがどの順序でどのモジュールを通るか
   - **共有型の定義場所**: どの型をどのモジュールに置くか、重複定義の禁止ルール
2. 契約書を `/tmp/orchestra-{team-name}/design-contract.md` に保存
3. **architect エージェント** を spawn し、契約書の評価を依頼する
4. architect の指摘を反映して契約書を改善（最大2回のレビューループ）
5. impl への spawn 時に契約書のパスを渡し、参照を義務付ける

## Wave 1: 基盤構築（3並列）

```
impl-1: 基盤（型定義・設定・共通UI・データリーダー）
impl-2: API ルート
tester: 仕様ベーステスト作成（/spec-driven-test）
```

1. `TeamCreate`（team_name: `orchestra-{task-slug}`）
2. `agent-prompts.md` を Read し、各エージェントのプロンプトを取得
3. leader がタスクを分析し `TaskCreate` でタスクリストを作成
4. impl-1, impl-2, tester を**並列 spawn**
5. **spawn 時に `/tmp/orchestra-{team-name}/design-contract.md` を必ず Read するよう指示**
6. impl-1/2 の担当は **ファイルレベルで完全に独立** させること
7. tester は仕様書（SPEC.md 等）を入力とし、テストのアサーション方法は既存テストのパターンを参考にする
8. 全員の完了通知を受けたら Wave 2 へ

## Wave 2: 応用実装 + テスト実行（2並列 + 検証）

```
impl-1: ページ実装 A
impl-2: ページ実装 B
leader: tester のテストを実行し、失敗があれば impl に通知
```

1. impl-1/2 に Wave 2 のタスクを `SendMessage` で割り当て
2. **フェーズ切り替えを明示**: `## PHASE: WAVE 2 — 応用実装` のヘッダーを含め、エージェントにフェーズを強く認識させる
3. impl は Wave 1 の成果物（型・API）を参照して実装
4. impl は tester が作成したテストを **仕様のガイド** として参照可能
5. leader はテストを実行し、結果を確認
6. 全 impl の完了 + テスト全通過で Wave 2.5 へ

## Wave 2.5: 統合スモークテスト（leader のみ）

```
leader: ビルド確認 + 起動テスト
```

1. ビルド確認（タイムアウト: 5分）
2. 可能であればアプリを起動し、主要フローを1回通す（タイムアウト: 30秒）
3. **リトライ上限: 最大2回**。2回失敗したらスキップしてレビューに進む
4. 環境問題（依存解決失敗等）はログに記録し起動テストをスキップ
5. 発見した問題があれば修正してから Wave 3 へ。修正不要なら Wave 3 へ

## Wave 3: レビュー（3並列）

```
impl-1: impl-2 の担当ファイルをクロスレビュー
impl-2: impl-1 の担当ファイルをクロスレビュー
reviewer-c: 全体の横断レビュー + テスト品質確認
```

1. impl-1/2 に相互のレビュー指示を `SendMessage` で送信
2. **フェーズ切り替えを明示**: `## PHASE: WAVE 3 — クロスレビュー` のヘッダーを含める
3. reviewer-c を spawn（`agent-prompts.md` の Reviewer-C Prompt 参照）
4. レビュー結果は `/tmp/orchestra-{team-name}/review-*.md` に保存
5. 全員の完了通知を受けたら Wave 4 へ

## Wave 4: 最終判断

1. leader が reviewer-c の結果ファイルを Read し判断
2. **OK** → クリーンアップへ
3. **要修正** → 修正指示を impl に送り Wave 2 に戻る（**最大3回**。超えたら人間にエスカレーション）
