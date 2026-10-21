# review-pr エージェント起動ロスター

標準モード（単一 PR）の Phase 4・5 で親オーケストレータが spawn する worker / verifier の**起動仕様**を 1 枚に集約したもの。SKILL.md の Phase 4・5 はこのファイルを参照する（SSOT）。

> ⚠️ **このファイルは Claude Code の subagent 機構（`.claude/agents/`）には登録されない。**
> 各カードの `model` / `tools` は review-pr が Agent ツールで spawn する際の **指示用メモ**であり、ハード制約ではない（skills 配下の定義は `subagent_type` にならず、`tools` 制限も効かない）。
> Read 専用をツールレベルで強制したくなったら `~/.claude/agents/` への昇格、またはプラグイン化を検討する（このファイルがその下書きになる）。

## worker 選定原則（Phase 4-1・親が実施）

起動する worker は **PR 内容（差分の性質）に応じて各カードの「起動条件」でピック**する。全 worker 固定起動でも規模ベースの全省略でもない。

- **内容のみで判定** — 規模（ファイル数・行数）は選定に使わない
- **迷ったら起動** — グレーゾーンは spawn 側に倒す。選定ミスは観点の穴に直結し、レビューで最も避けたい失敗
- **選定ゼロ禁止** — 全カードの条件を外れる diff でも、差分に最も近い観点の worker を最低 1 体起動する
- **設計書のみの diff では worker7 を起動する**（該当すれば worker8 も）— worker1 を「最も近い観点」として代用しない（Laravel/DDD の checklist で設計書を読む空振りを防ぐ）
- **選定結果が 6 体を超える場合は 2 波に分けて spawn する** — 読み取り専用サブエージェントの同時上限 6 体（`rules/context-management.md`）
- **verifier は選定対象外** — 指摘件数に関わらず必ず実行する（従来通り）
- **silent skip 禁止** — 起動した worker とスキップした worker（+理由）を Phase 6 出力の概要に必ず記載する

## 全エージェント共通の引き渡し情報

親は各エージェントを spawn する際に以下を渡す。

- **worktree 絶対パス** — `{repo}/.worktrees/review-pr-{PR番号}`。**Read 専用で共有**（Edit / Write / NotebookEdit は使わせない。修正はコード片の提示に留める）
- **担当 reference の絶対パス** — 要約せず本人に Read させる（要約渡しは項目欠落の原因）
- **プロジェクト特性サマリ** — Phase 3 で親が確定した事実（アーキ / 技術スタック / DB 種別 / index 一覧）。これは短い事実なので要約渡し可
- **差分取得方法** — `git -C {worktree} diff origin/{base}...HEAD`（**`cd` と混ぜない**。`cd {worktree} && grep ...` は環境によっては hook でブロックされ、`cd` 混在は権限チェッカーが cwd を追えず承認プロンプトを招く。worktree 内を読むときも `git -C` / 絶対パスで指定する）
- **パスは実在確認してから Read** — worktree 内のファイルパスを推測で組み立てて Read しない。`git diff --name-only` の実パス・Glob・`ls` で実在を確認してから読む（worktree 配下のパスを推測で組み立てた Read の失敗が 3 PR で7回発生、2026-07-24〜08-03）
- **submodule の読み先** — `git worktree add` は submodule を初期化しないため、gitlink のディレクトリは worktree 内で空になる。差分の参照先に submodule が含まれる場合、親は Phase 2 で「初期化済み」か「main checkout を読む（gitlink 同一を確認済み）」のどちらかを確定して渡す。**空ディレクトリを見て「実装を確認不能」で止めない**（2026-08-24 の IaC（CDK）PR で `cdk/common/` が空になり、レビュー対象の Aspect が適用される Lambda 4 個の実装が読めず、worker1 の MUST が誤った前提で立った）
- **base と PR HEAD の時系列** — 親が Phase 3 で渡す「**base 側にのみ存在するファイルの一覧**」を確定事実として扱う。PR ブランチが base より遅れている場合、worktree（= PR HEAD）からは base 側の前例・規約が一切見えないため、**「worktree に無い」を「リポジトリに無い」と断定しない**。base 側の前例を指摘の根拠に使うときは追加日が PR HEAD より前かを確認する（後なら当時の要求として使えない）

## 共通出力スキーマ（worker が返す指摘の配列）

```
- severity: MUST | SHOULD | NITS | QUESTION
  category: arch | perf | logic | test | impact | spec | ui | doc
  scope:    change | existing（change = 今回の PR の変更行・追加行が原因 / existing = base ブランチ由来で元からある潜在問題。判定: `git diff origin/{base}...HEAD` で当該行が変更行に含まれるか）
  summary:  1行要約（コード前提なしで読める／問題そのものを端的に。抽象語禁止）
  location: path:line
  what:     何が起きてる（1〜2文・コード差分の事実のみ）
  why:      なぜまずい（1〜2文・プロジェクトルール/原則名は1つに絞る）
  how:      どう直す（1〜2文・置き換え後の形を具体的に）
  evidence: 根拠（参照ルールの該当行 / 仕様の出典 / grep 結果 のいずれか。MUST は必須）
```

worker は **指摘の発掘**に専念する（採否判定はしない）。指摘ゼロなら空配列を返してよい。

### `category` は 8 値で閉じている（他の語を作らない）

`arch | perf | logic | test | impact | spec | ui | doc` 以外の値を返さない。**逸脱の発生源はカード側の語彙**である。各カードの見出しや観点欄に並ぶ領域名（「バッチ堅牢性」「並行・非同期」など）は**担当範囲の呼称であって `category` の値ではない**。担当領域がどれだけ細かく書かれていても、返す値は上の 8 値のいずれかに寄せる。

**`logic` と `perf` の境目** — 実行結果が**間違う**なら `logic`（条件式・境界・冪等性・二重実行・dispose 漏れ）、実行結果は正しいが**遅い / 重い**なら `perf`（N+1・ウォーターフォール・再レンダー・バンドル）。worker2 はこの 2 値を**指摘ごとに**使い分ける。

親は spawn 時にこのスキーマを渡す際、**その worker の主担当値を明示する**。

| worker | 主担当の `category` |
|---|---|
| worker1 | `arch` |
| worker2 | `perf` / `logic` |
| worker3 | `test` |
| worker4 | `impact` |
| worker5 | `spec` |
| worker6 | `ui` |
| worker7 | `doc` |
| worker8 | `doc` |

主担当値は既定であって固定ではない。1 体が複数観点にまたがる指摘を出した場合は、**指摘ごとに**最も近い enum 値を選ぶ（例: worker2 がテスト不在を併せて指摘したら `test`）。どれにも寄せられないと感じたら、値を作らずに主担当値で返し、その旨を `why` に 1 文添える — **新しい語を作られるより、寄せ先が粗いほうが後段で扱える**。

## 空振り報告（worker の出力末尾に必須・親が Phase 6 で集計する）

各 worker は指摘の配列に続けて、**担当 reference の節ごと**に 1 行で結果を報告する。

```
## 空振り報告
- §N（節タイトル）: hit N件 / 空振り（見たが該当なし） / 未確認（理由）
```

- **空振り** = その節の観点で差分を見たが指摘に至らなかった
- **未確認** = 見ていない。**見ていない節は正直に「未確認」と書かせる**（埋めるための虚偽記載が最も困る）
- 節が箇条書きで細かい reference（`flutter-checklist.md` §2 など）は**箇条項目ごと**に 1 行出させる
- スタック非該当で丸ごと飛ばした節群は **1 行にまとめてよい**（例: 「§1〜7 = スタック非該当（読んでいない）」）

**何のためにあるか**: チェックリストの実効性を測り、`policy` の「観点欄で出なかった領域だけ厚くする」判断に使う。指摘が出せなかった節を正直に空振りと書くことがこの報告の価値であり、hit 件数を稼ぐことではない。

**実測で効いた例**（2026-08-24 の Flutter アプリ PR で初導入）:
- `flutter-checklist.md` §5 の「文字スケール（`TextScaler`）」が in-repo 原典の「対応しない」と衝突していると判明 → 本ファイル群を修正
- §4-1 Figma 突合が 2 レビュー連続で「突合元はあるが開けない」で停止していると判明 → 設計書の記述で代替する方針に変更
- `impact-check-rules.md` が Flutter PR で 15 節中 7 節を定義上空振りさせていると判明 → 技術スタック別の適用範囲を明記
- worker3 が「Presentation 層のテスト不在は原典が対象外と明記」を根拠に**空振りへ落とした**うえで Domain Model 層に絞り込んだ（正しい空振り判断の実例）

## エージェントカード

reference パスは `~/.claude/skills/review-pr/references/` を基準とする絶対パスで渡す。

### worker1 — アーキテクチャ・コーディングルール
- **model**: sonnet / **tools**: Read, Grep, Glob, Bash（Read 専用方針）
- **起動条件**: プロダクションコード（アプリ本体・ライブラリコード）または設定値・定数クラスの追加・変更がある。IaC（`cdk/` / `.tf` / `ansible/` / `.github/workflows/`）またはネイティブ（`.swift` / `.kt` / `.gradle` / `.gradle.kts` / `AndroidManifest.xml` / `Info.plist` / `pubspec.yaml`）の差分も対象。スキップ例: ドキュメント・テストのみの diff
- **観点**: **レイヤ依存の原則**（同一層の水平呼び出し / 依存の逆流 / トランザクション境界の所在 / ドメインロジックの置き場）を最初に通す — `review-checklist.md` §1 冒頭。層別チェック項目は原則の具体例であり、**項目に明記がなくても原則に反する構造は指摘する**。
  続けて 責務分離・命名規則（例: `*Action` = API 起点 / `*Task` = バッチ起点）・ディレクトリ配置・コーディングルール・抽象化/間接層の妥当性（新しい層・置き場の導入に便益があるか、既存慣習と揃っているか）
- **手順**: worktree の静的解析スクリプトが定義されていれば差分ファイルに実行し、出力を evidence にする — PHP は composer スクリプト（PHPStan / Larastan / Pint / phpcs）、**JS/TS は `package.json` の `lint` / `format:check` / `tsc --noEmit`**。未定義・実行失敗時はスキップして親に報告する。**依存が未インストールで実行できないことがある** — worktree には `node_modules` / `vendor` が無く、`npm ci` もロックファイルの不整合で落ちうる。その場合は**インストールを試みず**（他 worker が同じ worktree を読んでいる最中に依存やロックファイルを書き換えない）、CI の結果に委ねて実行不能だった旨を親に報告する（2026-08-24 の React フロントエンド PR で `npm ci` が `package-lock.json` の欠落エントリにより EUSAGE エラーになり、worker1 が自制して報告した）
- **reference**: Laravel/DDD → `review-checklist.md`（§1〜3, §5, §6, §8, §10, §11） / React・Next.js → **worktree の in-repo 規約**（`.cursor/rules/*.mdc` / `CLAUDE.md` / `AGENTS.md` / `.github/copilot-instructions.md` のうち Phase 3 で親が実在を確定して渡したもの）+ **既存コードの慣習との比較**（同ディレクトリ・同型ファイルを Read し、レイヤ配置・命名・責務の置き方が揃っているかを見る）。**`/vercel-react-best-practices` は読まない** — 同スキルの 8 カテゴリはすべて性能観点で、本カードの担当観点（レイヤ依存・責務分離・命名規則・ディレクトリ配置・抽象化の妥当性）に対応する節が存在しない（2026-08-24 の React フロントエンド PR で worker1 が実測し「対応する節が無い」と報告。同 PR で拾えた 2 件はいずれも性能由来で、うち 1 件は verifier に棄却された） / Flutter・Dart → `flutter-checklist.md`（§1・§3） / IaC → `iac-checklist.md`（**担当は §1〜§4 のうち差分に該当する節**。§1 の「合成時ロジックの正当性」「合成結果が実行時に効くか」の 2 項目は worker2 の担当なので重複指摘しない。適用範囲は同ファイル冒頭の表）

### worker2 — 実行時挙動（パフォーマンス・SQL・ロジック・バッチ・並行）
- **model**: sonnet / **tools**: Read, Grep, Glob, Bash
- **起動条件**: SQL・クエリビルダ・Eloquent・リポジトリ・マイグレーション・index、ループ内 I/O、データフェッチ・レンダリング、`Console/Commands/` / `Jobs/` / `UseCases/**/*Task.php` / `config/queue.php`、`chunk(` / `Http::pool` / `Utils::all`、Dart の `async` / `await` / `Future` / `Stream` / `Completer` / `StreamController` / `dispose` / `initState` / hooks（`use*`）のいずれかに触れる変更がある。**IaC では次のいずれか** — CDK の `Aspect` / `visit()` / construct 内の条件分岐・ループ・状態キャッシュ・型キャスト、環境別の分岐、Lambda ハンドラ実装（`cdk/lambda/` 配下等）、GitHub Actions の `if:` / matrix / `run:` スクリプト。スキップ例: ドキュメント・テストのみの diff
- **観点**: N+1 / count+get / EXISTS 多段 / 両側 LIKE / 関数式 WHERE / バンドル・ウォーターフォール・再レンダー。
  加えて ①**ロジック正当性**（条件式の真偽表展開・空/1件/境界の 3 ケース手流し・Collection のオブジェクト比較・配列キー保護・ループ脱出条件）②**バッチ堅牢性**（冪等性・中断再開の粒度・チャンクとメモリ・キュー二重実行・0 件時の外部送信抑止）③**並行・非同期・ライフサイクル**（多重実行防止・完了保証・dispose 対称性・mounted ガード）④**マイグレーション**（`review-checklist.md` §7-2 参照）。
  **IaC では ① を「合成時ロジック」と「合成結果の実行時意味」の 2 段に適用する** — 前者は Aspect / construct の分岐・ループ・状態キャッシュによる取りこぼし・二重適用・上書き、後者は設定した環境変数・レイヤー・IAM が実行時に効くか（no-op・後段での上書き・自動計装との重複）
- **reference**: Laravel/DDD → `review-checklist.md`（§7・§7-2）+ `impact-check-rules.md`（SQL 連鎖） / React・Next.js → `/vercel-react-best-practices`（別途導入が必要な外部スキル。未導入ならその観点を silent skip せず、理由付きで Phase 6 の概要に記載する。**本カードの専任 reference**。8 カテゴリすべてが性能観点のため worker1・worker3 は読まない。担当は差分に該当する節で、2026-08-24 の React フロントエンド PR では §1 Eliminating Waterfalls と §4 Client-Side Data Fetching が該当した。§3 Server-Side Performance・§6 Rendering Performance・§8 Advanced Patterns はクライアント hooks のみの diff では観点が当たるコードが存在しない） / Flutter・Dart → `flutter-checklist.md`（§2） / IaC → `iac-checklist.md`（**担当節は同ファイル冒頭の表を参照** = §1 の合成時ロジック 2 項目・§2 のトリガー条件と並行制御・§5。構成・規約・セキュリティの項目は worker1 の担当なので重複指摘しない）
- **備考**: バグ主張の指摘は「この入力でこの結果になる」形の再現手順を evidence に付ける。**パーティション表・関数式WHERE・両側ワイルドLIKE・型不一致の比較に触れたら `review-checklist.md`「実行計画の実測（EXPLAIN）」に従い、severity を決める前に実行計画を取る**（取れない場合は「EXPLAIN 未実測」と evidence に明記して SHOULD 以下に留める）

### worker3 — テスト品質
- **model**: sonnet / **tools**: Read, Grep, Glob, Bash
- **起動条件**: テストファイルの変更がある、**またはプロダクションコード変更にテスト追随がない**（テスト欠落自体が指摘対象のため）。スキップ例: ドキュメント・設定値のみの diff
- **観点**: テストピラミッド・正常/異常/境界の網羅・アサーション方針・モック方針。**テストが通る＝検証できているとは限らない**（対象実装を 1 行削ったら落ちるかを頭の中で変異させる）
- **reference**: Laravel/DDD → `review-checklist.md`（§4） / React・Next.js → **worktree のテスト規約**（`.cursor/rules/*.mdc` のテスト作成規約等・Phase 3 で親が実在を確定して渡したもの）+ **既存テストの前例**（同ディレクトリまたは同型対象のテストを Read し、アサーション粒度・モック境界・初期状態の検証有無を比較する）。**`/vercel-react-best-practices` は読まない** — 同スキルは実装コードの性能最適化ガイドでテストコードを評価する節が存在しない（2026-08-24 の React フロントエンド PR で worker3 が実測し「対応する節が無い」と報告。同 PR の MUST 3 件はすべて in-repo 規約と変異検証から出た） / Flutter・Dart → worktree のテスト方針文書（`docs/` 配下等・Phase 3 で親が実在を確定して渡したもの） + `flutter-checklist.md`（§6） / IaC → `iac-checklist.md`（**§6「テスト手段」が担当節**。加えて差分に該当する §1〜§5 を「この観点の退行を何が検知するのか」の視点で読む）
- **備考**: 「そのスタックではテストできない」を前提にしない。手段の有無は reference で確認する（CDK は `aws-cdk-lib/assertions` の `Template.fromStack` が標準手段）。**base 側のテストを「前例があるのだから書けるはず」の根拠に使う場合は追加日を確認する** — PR HEAD より後に追加された前例で MUST は立てられない（`iac-checklist.md` §6）

### worker4 — 影響範囲・変更漏れ
- **model**: sonnet / **tools**: Read, Grep, Glob, Bash, mcp__github__search_code（org 内他リポジトリへの波及確認用）
- **起動条件**: 既存ファイルの変更・削除・リネームがある、共通基盤（定数・enum・DB スキーマ・共有コンポーネント）に触れる、または生成物ディレクトリ（`app/Infrastructures/OpenAPI/` / `reference/**/*.yaml` 等のスキーマ由来ファイル）に触れる。スキップ例: 既存参照に一切触れない完全新規ファイル追加のみ・ドキュメントのみの diff（**ただし生成物ディレクトリ・スキーマ由来ファイルの変更は対象**。さらに設計書のみの diff でも、**DB スキーマ・共通定義・API レスポンス項目の意味変更**を含む場合は起動する — 2026-08-23 の設計書 PR で、設計書のみの diff から試験工程の手順書の追随漏れ MUST を拾ったのは worker4 だった）
- **観点**: 変更ファイルから連鎖する関連ファイルの欠落・利用箇所への波及・Grep 0 件判定。
  加えて 逆方向検出（差分で参照 0 になった `use`・変数・メソッド・ファイル、到達不能になった catch/分岐、デバッグ痕 → 削除を指摘）／自動生成物の手編集検出（生成元を直して再生成させる）／org 内他リポジトリへの波及／兄弟 PR・対称箇所（Store と Destroy 等）
- **根拠の時系列確認**（他リポジトリを根拠にする場合は必須）: org 横断検索で見つけた契約・スキーマ・定数を根拠に指摘を立てるときは、`git log` でその根拠が**レビュー対象 PR より前から存在したか**を確認し、確認結果を evidence に書く。他リポジトリの検索結果は常に「現在」の状態であり、当時の要求として扱うと偽陽性になる（2026-08-23 のマージ済み Laravel PR で、別リポジトリ（BFF）の OpenAPI 契約の `required` 項目を根拠にした MUST が「その契約は PR マージの 5 日後に作られ、初版に当該項目は無い」と判明して棄却された）
- **reference**: `impact-check-rules.md` — **§8〜15 が技術スタック共通、§1〜7 は Laravel/DDD 専用**（他スタックでは §1〜7 を飛ばし、相当する連鎖を自分で組み立てる。同ファイル「技術スタック別の適用範囲」参照）

### worker5 — 仕様書・計画書 適合性
- **model**: sonnet / **tools**: Read, Grep, Glob, Bash, WebFetch（WebFetch は仕様ソースの取得用）
- **起動条件**: 次のいずれか — 仕様ソース（Phase 1 で拾ったリンク Issue・課題管理ツールの URL・PR 説明内の要求記述）が存在する / 変更ファイル名や、画面 ID・API 番号などの採番体系があればそれで、プロジェクトの設計書の置き場（docs リポジトリ・docs ディレクトリ・Wiki 等。置き場はリポジトリによって違う）から設計書を逆引きできる / 既存行の削除がある / 計測イベント送信（`FirebaseAnalytics` / `Karte` / `*AnalyticsEvent`）を含む。スキップ例: 上記のいずれにも該当しない diff（根拠のない QUESTION 過多を防ぐ）
- **観点**: 要求充足 / 仕様逸脱 / 過剰実装 / 受け入れ基準 / ドキュメント整合。
  加えて 双方向突合（実装を原典として設計書側の陳腐化も見る）・用語整合（既存表記との Grep 比較）・無関係変更の混入・hotfix の暫定対処の適用範囲
- **原典は PR 当時のスナップショットで突合する**: 設計書は PR マージ後に更新されていることがある。現在の版で読んで「未実装」に見えた項目は、`git log --date=iso` で当該行の追加日を確認し、レビュー対象 PR より後なら指摘として成立しない。当時の版は `git show {当時のコミット}:{パス}` で取得する（2026-08-23 のマージ済み Laravel PR で、未実装に見えた 3 項目すべてが PR の数ヶ月後の追記だった）
- **reference**: `spec-compliance-check.md`（技術スタック共通）
- **追加入力**: Phase 1 で取得した PR 説明本文・リンク Issue 本文 / Phase 3「原典の解決」で解決した設計書の原典パス一覧 / 計測イベントを含む場合は worktree 内の計測イベントの設計文書（あれば） / Flutter PR では `flutter-checklist.md`（§4 突合手順）
- **備考**: 取得不能な原典（SharePoint xlsx / Figma ノード）は突合を試みず、「PR 本文に該当箇所の引用を求める QUESTION」に定型化する

### worker6 — UI・アクセシビリティ（Webインターフェースガイドライン準拠）
- **model**: sonnet / **tools**: Read, Grep, Glob, Bash, WebFetch（WebFetch はガイドライン取得用）
- **起動条件**: **マークアップ・スタイル・aria 属性・フォーカス制御のいずれかに差分がある**（`.tsx` / `.jsx` / `.vue` / `.blade.php` / `.html` / `.css` / `.scss`、Tailwind クラス変更、`.dart`（Widget / テーマ / デザイントークンを含む差分））。スキップ例: バックエンド・API・ドキュメント・テストのみの diff、**および hooks・ロジック・状態管理のみの diff でマークアップに一切触れないもの**。**「クライアントコンポーネントから呼ばれるコード」まで広げない** — 2026-08-24 の React フロントエンド PR では `.ts` のみ 22 ファイル（React hooks 11 + テスト 11）の diff に「迷ったら起動」を適用したが、ガイドライン 12 節中 8 節が未確認、唯一の指摘も verifier で NITS に格下げされ歩留まりが実質ゼロだった（worker6 自身が「深掘りのコストに対して指摘 1 件」と報告）
- **観点**: セマンティック HTML / aria 属性・フォーカス管理 / フォーム・インタラクションパターン / キーボード操作性 などの Web Interface Guidelines 準拠。**コードレベルの静的レビューに限定**するが、視覚デザイン（余白・配色バランス）の判断除外は **Web スタック限定**。
  blade は `old()` による入力保持・二重送信防止・`id` 重複・インライン JS の DOM 参照先の実在・表示ラベルと現行仕様の一致・blade 内でのクエリ発行も対象。
  Flutter は突合元（Figma ノード URL・画面設計書パス）が取得できた場合に限り数値突合を行い、取得できなければ指摘せず「突合元が無い」旨を親に報告する
- **reference**: Web → `/web-design-guidelines` スキル（別途導入が必要な外部スキル。未導入ならその観点を silent skip せず、理由付きで Phase 6 の概要に記載する） / Laravel blade → `/web-design-guidelines` + `review-checklist.md` §1 / Flutter → `flutter-checklist.md`（§4・§5）
- **備考**: ガイドラインはスキルが URL から取得する。取得失敗時は推測でレビューを続けず、指摘ゼロ＋取得失敗の旨を親に報告する

### worker7 — 設計書レビュー
- **model**: sonnet / **tools**: Read, Grep, Glob, Bash, WebFetch, mcp__github__get_file_contents（Read 専用方針。WebFetch は Figma / 課題管理ツール（Jira / Backlog 等） / ベンダー公式仕様、get_file_contents は実装リポジトリとの逆方向突合用）
- **起動条件**: `.md` または OpenAPI `.yaml` の設計書（API設計書・画面設計書・テーブル定義書・機能設計書・異常系仕様書）の追加・変更がある。スキップ例: 設計書を含まない diff・負荷試験ディレクトリの報告書/シナリオ（射程外・2026-08-22 ユーザー決定）
- **観点**: 文章表現・ドキュメント構成・テンプレート適合・リンク整合性（Figma node-id / 相対パス / GitHub URL）・図（sequenceDiagram / flowchart）と本文の整合・取得元欄とステップ番号の自己整合・画面設計書と API 仕様書の照合・用語統一と文字コード正規化・更新履歴・OpenAPI 記法規約・残留記述（旧記述 / TBD / SQL 例）・設計書間の相互整合・既存実装との逆方向突合・アーキテクチャ設計の論点提起（SHOULD/QUESTION 中心）
- **手順**: `markdownlint` / `redocly lint` / リンク実在確認を worktree で実行し、出力を evidence にする。ツール不在・実行失敗時はスキップして親に報告する
- **追加入力**: Phase 3「原典の解決」で解決した設計書の原典パス一覧（同一 API 番号・同一画面 ID の兄弟ファイル、項目名の統一表、異常系仕様書、テーブル定義書）
- **reference**: `design-doc-checklist.md` + `impact-check-rules.md`「設計ドキュメントが変更された場合」
- **備考**: 実装リポジトリの参照はローカルクローンがあればそちらを優先し、無い場合のみ `mcp__github__get_file_contents` で該当ファイルを取得する

### worker8 — 試験工程ドキュメント
- **model**: sonnet / **tools**: Read, Grep, Glob, Bash
- **起動条件**: 試験工程ドキュメント（テスト項目書・テスト実施手順書・機能テスト仕様書・UI テスト仕様書・`*.hurl` 等の API テストシナリオ）の追加・変更がある。スキップ例: 試験工程ドキュメントを含まない diff
- **観点**: 期待値の検証（API 設計書・異常系仕様書・実挙動との 3 点突合／実装バグと記載誤りの切り分け）・試験ケース網羅性（境界値・異常系・失敗時の副作用非発生）・機械的整合（ケース番号の連番・境界値の実測文字数・ケース間の矛盾）
- **reference**: `test-doc-checklist.md` + `review-checklist.md` §4

### verifier — 偽陽性チェック（Phase 5）
- **model**: opus（判定品質がレビュー全体の信頼性を決めるため worker より上位） / **tools**: Read, Grep, Glob, Bash
- **入力**: 起動した全 worker の指摘を集約した 1 つの配列
- **reference**: `false-positive-check.md` + `review-checklist.md`（§7・§9）
- **出力**: 各指摘に `confirmed` / `downgraded` / `rejected` / `merged`（フォーマットは `false-positive-check.md`）
- **備考**: 指摘件数に関わらず**必ず通す**。confirmed / downgraded のみ採用、rejected は出力に含めない。**新規指摘は追加しない**（発掘は worker の役割）
- **`category` の正規化**: worker が 8 値の外の語を返していたら、指摘を棄却せず**値だけ 8 値に寄せて** confirmed / downgraded として通す。寄せた事実は出力に残さない（レビュー本文のノイズになるため、親への報告に 1 行で足りる）
