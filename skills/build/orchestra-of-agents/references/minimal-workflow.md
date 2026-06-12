# 最小構成ワークフロー詳細 (v4.0)

## impl 数の判断基準

最小構成でも impl を追加できる。判断基準は**タスク数ではなく並列実行可能性**:

- Wave 1 で並列実行可能な独立タスクが **3つ以上** かつ各タスクが **50行超の実装量** → impl-2 を Wave 1 から追加
- それ以外 → impl-1 のみ。待ち時間が発生しても spawn コストより小さい

（v3.0 P2: タスク数だけで判断すると実態と合わない。依存関係と実装量で判断する）

## Wave 1: 実装 + テスト作成（2並列）

```
impl-1: 実装
tester: 仕様ベーステスト作成（/spec-driven-test）
```

1. `TeamCreate`（team_name: `orchestra-{task-slug}`）
2. `agent-prompts.md` を Read し、各エージェントのプロンプトを取得
3. leader がタスクを分析し `TaskCreate` でタスクリストを作成
4. impl-1, tester を**並列 spawn**（spawn 時に設計契約書の参照を義務付ける）
5. tester への指示には、テストのアサーション方法の参考として**同ディレクトリの既存テストファイルパス**を含める
6. 全員の完了通知を受けたら Wave 2 へ

## Wave 2: レビュー — 直接引き渡し（2並列）

```
impl-1 → reviewer-a (レビュー依頼)   ← 直接引き渡し
tester → reviewer-b (レビュー依頼)    ← 直接引き渡し
reviewer-a ↔ impl-1 (不明点は直接質問)
reviewer-b ↔ tester (不明点は直接質問)
reviewer-a/b → leader (レビュー完了報告) ← 節目報告
```

1. Wave 1 完了時、impl-1 は reviewer-a に直接レビュー依頼を送る（leader は spawn のみ担当）
2. tester は reviewer-b に直接レビュー依頼を送る
3. reviewer-a は impl-1 の変更ファイルを全て Read しレビュー。**不明点は impl-1 に直接質問**する
4. reviewer-b は tester のテストファイルを Read しレビュー + テスト実行。**不明点は tester に直接質問**する
5. レビュー結果は `/tmp/orchestra-{team-name}/review-*.md` に保存
6. **reviewer-a/b は leader にレビュー完了を報告**（節目報告）
7. 全員の完了通知を受けたら Wave 3 へ

## Wave 3: 総合判断 — 直接引き渡し

```
reviewer-a → reviewer-leader (総合判断依頼)  ← 直接引き渡し
reviewer-leader → leader (最終判断報告)       ← 節目報告
reviewer-leader → impl-1 (要修正の場合)       ← 直接差し戻し
impl-1 → leader (修正完了報告)                ← 節目報告
```

1. reviewer-leader を spawn（`agent-prompts.md` の Reviewer-Leader Prompt 参照）
2. reviewer-leader が reviewer-a/b のレポートを Read し、統合的に判断
3. **reviewer-leader は leader に最終判断（OK / 要修正）を報告**（節目報告）
4. **OK** → クリーンアップへ
5. **要修正** → reviewer-leader が修正指示を **impl-1 に直接送信**。impl-1 は修正後 **leader に修正完了を報告**（節目報告）。**impl の修正でテストが壊れた場合、テスト修正は tester が行う**（impl がテストを直接修正することは禁止。テストは仕様の番人であり、tester が仕様と照合して修正することで、修正の正しさを検証するゲートとして機能する）。Wave 2 に戻る（**最大3回**。超えたら人間にエスカレーション）

### reviewer-b と reviewer-leader の引き渡しについて

reviewer-b は reviewer-leader に直接 SendMessage を送らない。reviewer-b のレポートは `/tmp/orchestra-{team-name}/review-reviewer-b.md` にファイル保存され、reviewer-leader がそれを Read して参照する。これは reviewer-a が直接引き渡しするのと非対称だが、reviewer-b のレビュー対象（テスト）は reviewer-leader の判断材料としてファイル経由で十分であるため。
