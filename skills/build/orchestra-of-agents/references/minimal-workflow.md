# 最小構成ワークフロー詳細

## impl 数の判断基準

最小構成でも impl を追加できる。判断基準は**タスク数ではなく並列実行可能性**:

- Wave 1 で並列実行可能な独立タスクが **3つ以上** かつ各タスクが **50行超の実装量** → impl-2 を Wave 1 から追加
- それ以外 → impl-1 のみ。待ち時間が発生しても spawn コストより小さい

（タスク数だけで判断すると実態と合わない。依存関係と実装量で判断する）

## Wave 1: 実装 + テスト作成（2並列）

```
impl-1: 実装
tester: 仕様ベーステスト作成（/spec-driven-test）
```

0. **検証環境健全性ゲート**: Wave 0 で既存テストスイート・依存サービスが緑であることを確認してから着手する（`design-contract.md` 手順 0 参照）
1. `TeamCreate`（team_name: `orchestra-{task-slug}`）。**Agent Teams API が無い harness では省略**し、name 付き Agent spawn + SendMessage に読み替える（`conductor-playbook.md`「harness 適応」参照。teammate は永続するため Wave 跨ぎの再 spawn はしない）
2. `agent-prompts.md` を Read し、各エージェントのプロンプトを取得
3. conductor がタスクを分析し `TaskCreate` でタスクリストを作成
4. impl-1, tester を**並列 spawn**（spawn 時に設計契約書の参照を義務付ける）
5. tester への指示には、テストのアサーション方法の参考として**同ディレクトリの既存テストファイルパス**を含める
6. **ストール監視開始**: TaskList を定期確認し、pending のまま（owner なし）のタスクがあれば該当メンバーに SendMessage で催促する（継続監視は定期ポーリングより Bash の `sleep` ループが実効的）
7. 全員の完了通知を受けたら**監視を停止**し、Wave 2 へ

## Wave 2: レビュー — 直接引き渡し（2並列）

```
impl-1 → reviewer-a (レビュー依頼)   ← 直接引き渡し
tester → reviewer-b (レビュー依頼)    ← 直接引き渡し
reviewer-a ↔ impl-1 (不明点は直接質問)
reviewer-b ↔ tester (不明点は直接質問)
reviewer-a/b → conductor (レビュー完了報告) ← 節目報告
```

0. **reviewer spawn 確認**: conductor は reviewer-a / reviewer-b の **spawn 完了を確認してから**、impl-1 / tester に「レビュー依頼を送ってよい」と指示する（未 spawn の宛先に送られたメッセージは消失する）
1. Wave 1 完了時、impl-1 は reviewer-a に直接レビュー依頼を送る（conductor は spawn のみ担当）
2. tester は reviewer-b に直接レビュー依頼を送る
3. reviewer-a（**allowed_tools: Read, Glob, Grep, SendMessage, Write**）は impl-1 の変更ファイルを全て Read しレビュー。**不明点は impl-1 に直接質問**する
4. reviewer-b（**allowed_tools: Read, Glob, Grep, SendMessage, Write**）は tester のテストファイルを Read しレビュー + テスト実行。**不明点は tester に直接質問**する
5. レビュー結果は `/tmp/orchestra-{team-name}/review-*.md` に保存
6. **reviewer-a/b は conductor にレビュー完了を報告**（節目報告）
7. 全員の完了通知を受けたら Wave 2.5 へ

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

## Wave 3: 総合判断 — 直接引き渡し

```
reviewer-a → reviewer-leader (総合判断依頼)  ← 直接引き渡し
reviewer-leader → conductor (最終判断報告)    ← 節目報告
reviewer-leader → impl-1 (要修正の場合)       ← 直接差し戻し
impl-1 → conductor (修正完了報告)             ← 節目報告
```

1. reviewer-leader を spawn（`agent-prompts.md` の Reviewer-Leader Prompt 参照。**allowed_tools: Read, Glob, Grep, SendMessage, Write**）
2. reviewer-leader が reviewer-a/b のレポートを Read し、統合的に判断
3. **別モデルレビュー（条件付き必須）**: 変更が状態機械・ガード/権限・セキュリティ敏感・CLI/API 外部契約に該当する場合、conductor が別モデルによるレビューが可能な MCP/CLI があればそれで別モデルレビューを依頼し、MUST 指摘を解消する（SKILL.md「Wave 3 判定基準」条件4参照）
4. **reviewer-leader は conductor に最終判断（OK / 要修正）を報告**（節目報告）
5. **conductor 実体検証**: 判定確定前に `git status` で成果物の実在を確認し、検証コマンド（test / typecheck / lint）を conductor 自身が直接実行して green を裏取りする（`conductor-playbook.md`「実体検証」参照）
6. **OK** → クリーンアップへ
7. **要修正** → reviewer-leader が修正指示を **impl-1 に直接送信**。impl-1 は修正後 **conductor に修正完了を報告**（節目報告）。**impl の修正でテストが壊れた場合、テスト修正は tester が行う**（impl がテストを直接修正することは禁止。テストは仕様の番人であり、tester が仕様と照合して修正することで、修正の正しさを検証するゲートとして機能する）。Wave 2 に戻る（**最大3回**。超えたら人間にエスカレーション）

### reviewer-b と reviewer-leader の引き渡しについて

reviewer-b は reviewer-leader に直接 SendMessage を送らない。reviewer-b のレポートは `/tmp/orchestra-{team-name}/review-reviewer-b.md` にファイル保存され、reviewer-leader がそれを Read して参照する。これは reviewer-a が直接引き渡しするのと非対称だが、reviewer-b のレビュー対象（テスト）は reviewer-leader の判断材料としてファイル経由で十分であるため。

## Wave 3.5: 改善提案の拾い上げ（ユーザー確認制）

Wave 3 で判定 OK になった後、クリーンアップ前に conductor が実行する。非ブロッキング指摘を永続化し、後続タスクとして残す。

1. `/tmp/orchestra-{team-name}/review-final.md` を Read する
2. 「改善提案」「軽微な指摘」セクションに非ブロッキング項目があるか確認
3. **契約書 §ベースライン（既知問題）で除外した既存負債を必ず改善提案リストに含める**（除外判定が正しくても永続化しないと同じ除外を毎回繰り返し、負債が雪だるまになる）
4. **1件以上ある場合**: ユーザーに件数と要約を提示し、「Issue 化しますか？」と確認する
5. 承認を得たら、各提案を GitHub Issue として作成する（対象リポジトリは現在の作業対象。`gh issue create` または GitHub MCP を使用）
6. 却下または「該当なし」ならスキップ
7. 作成した Issue 番号は最終レポートに追記する

**原則**: 自動で Issue を立てない。ユーザー承認が必須（実行されるアクションは外部可視）。

## クリーンアップ: 集中コミットと生トレースの保全

1. **集中コミット**: conductor が `conductor-playbook.md`「コミットルール」に従って commit する — `git branch --show-current` で push 禁止ブランチ判定 → `git status` で stray ファイル点検 → diff 確認 → コミットメッセージをユーザーに提示し承認後に commit
2. 実行ログ（run-log-template.md）を `/tmp/orchestra-{team-name}/{YYYY-MM-DD}-{task-slug}.md` に保存する。`/tmp/orchestra-{team-name}/raw/` の生トレースはそのまま同ディレクトリに残す
