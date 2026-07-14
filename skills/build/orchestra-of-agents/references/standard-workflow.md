# 標準構成ワークフロー詳細

## Wave 0: 設計契約（conductor のみ）

```
conductor: 検証環境健全性ゲート → インターフェース契約書を作成 → ユーザー承認
```

0. **検証環境健全性ゲート**: 既存テストスイート・依存サービス（テストDB、localstack 等）が緑であることを確認する。壊れていたら実装に着手せず、復旧またはユーザー相談を先に行う
1. タスクを分析し、`design-contract.md`「契約書に含める内容」の全項目を含む契約書を作成:
   - **Base commit SHA**: 作業起点の commit hash
   - **エンティティ関係図**: 主要構造体/型の関係と ID の流れ
   - **モジュール境界の API**: impl 間の呼び出しインターフェース（関数シグネチャ + 戻り値の意味）
   - **データフロー**: イベントがどの順序でどのモジュールを通るか
   - **共有型の定義場所**: どの型をどのモジュールに置くか、重複定義の禁止ルール（消費側の型から逆算）
   - **呼び出し元・消費者の網羅リスト**: ast パース or 複数行対応 grep で全列挙。CLI verb 変更時は workflow スクリプト等のコード外消費者も含める。ガード・述語は呼び出し側で強制されているかを確認
   - **文字列トークンの正規語彙**: モジュール間トークンを値レベルで固定
   - **コミット順序**: 担当ファイル間の import グラフを矢印で図示し、「依存される側が先」で機械的に導出
2. 契約書を `/tmp/orchestra-{team-name}/design-contract.md` に保存
3. **architect エージェント** を spawn し、契約書の評価を依頼する。spawn 時のプロンプトは `agent-prompts.md` の **Architect Review Prompt** を使用する（内部整合性観点——擬似コード順序・型定義・宣言と実装の一致・テスト方針の実行可能性——を含む）
4. architect の指摘を反映して契約書を改善（最大2回のレビューループ）
5. impl への spawn 時に契約書のパスを渡し、参照を義務付ける

## Wave 1: 基盤構築（3並列）

```
impl-1: 基盤（型定義・設定・共通UI・データリーダー）
impl-2: API ルート
tester: 仕様ベーステスト作成（/spec-driven-test）
```

1. `TeamCreate`（team_name: `orchestra-{task-slug}`）。**Agent Teams API が無い harness では省略**し、name 付き Agent spawn + SendMessage に読み替える（`conductor-playbook.md`「harness 適応」参照。teammate は永続するため Wave 跨ぎの再 spawn はしない）
2. `agent-prompts.md` を Read し、各エージェントのプロンプトを取得
3. conductor がタスクを分析し `TaskCreate` でタスクリストを作成
4. impl-1, impl-2, tester を**並列 spawn**
5. **spawn 時に `/tmp/orchestra-{team-name}/design-contract.md` を必ず Read するよう指示**
6. impl-1/2 の担当は **ファイルレベルで完全に独立** させること
7. tester は仕様書（SPEC.md 等）を入力とし、テストのアサーション方法は既存テストのパターンを参考にする
8. **ストール監視開始**: TaskList を定期確認し、pending のまま（owner なし）のタスクがあれば該当メンバーに SendMessage で催促する（継続監視は定期ポーリングより Bash の `sleep` ループが実効的）
9. 全員の完了通知を受けたら**監視を停止**し、Wave 2 へ

## Wave 2: 応用実装（2並列）

```
impl-1: ページ実装 A
impl-2: ページ実装 B
```

1. impl-1/2 に Wave 2 のタスクを `SendMessage` で割り当て
2. **フェーズ切り替えを明示**: `## PHASE: WAVE 2 — 応用実装` のヘッダーを含め、エージェントにフェーズを強く認識させる
3. **ストール監視開始**: TaskList を定期確認し、in_progress のまま長時間動きがないタスクや pending のタスクがあれば催促する
4. impl は Wave 1 の成果物（型・API）を参照して実装
5. impl は tester が作成したテストを **仕様のガイド** として参照可能
6. 全 impl の完了で**監視を停止**し、Wave 2.5 へ

## Wave 2.5: 統合スモークテスト（tester）

```
tester: ビルド確認 + テスト実行 + 起動テスト → conductor に報告
```

1. conductor が tester にスモークテスト実行を `SendMessage` で指示
2. **フェーズ切り替えを明示**: `## PHASE: WAVE 2.5 — 統合スモークテスト` のヘッダーを含める
3. **報告監視開始**: tester から報告フォーマット付きの SendMessage が届いたか定期確認する。届いていなければ tester に催促する。**報告が空・summary のみならフォーマット指定で再要求する**（conductor 二重チェック）
4. tester がビルド確認（タイムアウト: 5分）
5. テストスイートを実行し、全通過するか確認
6. 可能であればアプリを起動し、主要フローを1回通す（タイムアウト: 30秒）
7. **リトライ上限: 最大2回**。2回失敗したらスキップしてレビューに進む
8. 環境問題（依存解決失敗等）はログに記録し起動テストをスキップ
9. **失敗時**: tester は生の stdout/stderr を `/tmp/orchestra-{team-name}/raw/` に保存する（フォーマット・手順は agent-prompts.md の tester prompt 参照）
10. tester が結果を conductor に報告（節目報告。報告フォーマットは agent-prompts.md 参照）
11. 報告受領後、監視を停止
12. **問題発見時**: conductor が impl に差し戻す（tester は実装コードを修正しない）
13. 問題なし or 修正完了で Wave 3 へ

## Wave 3: レビュー（3並列）

```
impl-1: impl-2 の担当ファイルをクロスレビュー
impl-2: impl-1 の担当ファイルをクロスレビュー
reviewer-c: 全体の横断レビュー + テスト品質確認
```

1. impl-1/2 に相互のレビュー指示を `SendMessage` で送信（**依頼先 reviewer が spawn 済みであることを確認してから**）
2. **フェーズ切り替えを明示**: `## PHASE: WAVE 3 — クロスレビュー` のヘッダーを含める
3. reviewer-c を spawn（`agent-prompts.md` の Reviewer-C Prompt 参照。**allowed_tools: Read, Glob, Grep, SendMessage, Write**）
4. **レビュー監視開始**: review-*.md ファイルの存在を定期確認し、全員のレビューが揃ったか監視する
5. レビュー結果は `/tmp/orchestra-{team-name}/review-*.md` に保存
6. **別モデルレビュー（条件付き必須）**: 変更が状態機械・ガード/権限・セキュリティ敏感・CLI/API 外部契約に該当する場合、別モデルによるレビューが可能な MCP/CLI があればそれで別モデルレビューを依頼する（SKILL.md「Wave 3 判定基準」条件4参照）。MUST 指摘は impl に差し戻して解消する
7. 全員の完了通知を受けたら**監視を停止**し、Wave 4 へ

## Wave 4: 最終判断

1. conductor が reviewer-c の結果ファイルを Read し判断
2. **conductor 実体検証**: 判定前に `git status` で成果物の実在を確認し、検証コマンド（test / typecheck / lint）を conductor 自身が直接実行して green を裏取りする（報告の鵜呑み禁止。`conductor-playbook.md`「実体検証」参照）
3. **OK** → クリーンアップへ
4. **要修正** → conductor が修正指示を impl に送り Wave 2 に戻る（**最大3回**。超えたら人間にエスカレーション）

## Wave 4.5: 改善提案の拾い上げ（ユーザー確認制）

Wave 4 で判定 OK になった後、クリーンアップ前に conductor が実行する。非ブロッキング指摘を永続化し、後続タスクとして残す。

1. `/tmp/orchestra-{team-name}/review-final.md` を Read する
2. 「改善提案」「軽微な指摘」セクションに非ブロッキング項目があるか確認
3. **契約書 §ベースライン（既知問題）で除外した既存負債を必ず改善提案リストに含める**（除外判定が正しくても永続化しないと同じ除外を毎回繰り返し、負債が雪だるまになる）
4. **1件以上ある場合**: ユーザーに件数と要約を提示し、「Issue 化しますか？」と確認する
5. 承認を得たら、各提案を GitHub Issue として作成する（対象リポジトリは現在の作業対象。`gh issue create` または GitHub MCP を使用）
6. 却下または「該当なし」ならスキップ
7. 作成した Issue 番号は最終レポートに追記する

**原則**: 自動で Issue を立てない。ユーザー承認が必須（実行されるアクションは外部可視）。

## クリーンアップ: 集中コミットと生トレースの保全

1. **集中コミット**: conductor が `conductor-playbook.md`「コミットルール」に従って commit する — `git branch --show-current` で push 禁止ブランチ判定 → `git status` で stray ファイル点検 → diff 確認 → コミットメッセージをユーザーに提示し承認後に commit（コミット順序は契約書の import グラフに従う）
2. 実行ログ（run-log-template.md）を `/tmp/orchestra-{team-name}/{YYYY-MM-DD}-{task-slug}.md` に保存する。`/tmp/orchestra-{team-name}/raw/` の生トレースはそのまま同ディレクトリに残す
