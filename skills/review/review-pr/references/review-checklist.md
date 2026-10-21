# PRレビューチェックリスト

層構成・命名・禁止イディオム・例外クラスなどの具体値は、導入元の Laravel/DDD プロジェクトの規約を例にしている。対象プロジェクトに固有の規約がある場合はそちらに読み替える。

## 1. アーキテクチャ（DDD階層）

### レイヤ依存の原則

**以降の層別チェックは、すべてこの原則の具体例。** 原則に反する構造は、層別項目に明記がなくても指摘対象になる（項目の列挙は網羅ではない）。

```
Http/Controller ──┐
Console/Command ──┼─→ UseCase ─┬─→ Service ─→ Model / Domain / ValueObject
Jobs ─────────────┘            └─→ Infrastructure（S3・外部API）
```

| 層 | 責務 | 呼んでよい先 |
|---|---|---|
| Controller / Command / Job | 入口。入力の受け取りと UseCase の起動のみ | UseCase |
| UseCase | ユースケースの手続き。**トランザクション境界の所有者** | Service, Infrastructure, Model |
| Service | ドメインロジックの実体。**再利用の単位** | Model, Domain, ValueObject |
| Infrastructure | 外部 I/O（S3・外部API）の境界 | 外部のみ |
| Model / Domain / ValueObject | 状態と不変条件 | — |

- [ ] **同一層の水平呼び出しをしていないか** — UseCase が別 UseCase（`*Action` / `*Task`）を、Service が別 Service を呼んでいないか。共通処理は**一段下の層に切り出し**、各呼び出し元がそれを呼ぶ形にする
  - Why: 水平呼び出しは依存を横に伸ばし、トランザクション境界を入れ子にし、ドメインロジックの所在を曖昧にする
  - 判定: コンストラクタインジェクションの型／`use` 文が**同一層のクラス**を指していないか（`App\UseCases\...` を使う `App\UseCases\...`、`App\Services\...` を使う `App\Services\...`）
- [ ] **依存が逆流していないか** — Service / Infrastructure / Model から UseCase を呼んでいないか
- [ ] **トランザクション境界が UseCase にあるか** — UseCase は DB 更新が1つでもあれば必ず張る。Service で張るのは禁止
- [ ] **ドメインロジックが Service に居るか** — UseCase / Controller に業務判断（条件分岐・集計・状態判定）が書かれていないか。同じ判断が複数の UseCase に重複していたら Service 未切り出しのサイン

**既存起因の扱い（重要）**: この原則に反する既存コードが多数あるプロジェクトは珍しくない（導入元の Laravel リポジトリでも、UseCase → UseCase の水平呼び出し・Service → Infrastructure の層飛ばし・Model 等から UseCase への逆流が、いずれも既存コードに残っていた）。

そのため、`git diff origin/{base}...HEAD` で**当該行が今回の変更行に含まれる場合のみ MUST / SHOULD** とし、既存の慣習に追随しただけの箇所は `scope: existing` の QUESTION に留める。既存の大量指摘でレビューを埋めない。

### Controller / Command / Job（入口層）
- [ ] 1APIに対してControllerが定義されているか
- [ ] DTO(FormRequest経由)をUsecaseに渡しているか
- [ ] 引数が1つでもDTO化されているか（直接値を渡していないか）
- [ ] UseCaseから返されたDTOをResourceに渡しているか
- [ ] Resourceでレスポンスを生成しているか
- [ ] 入口に業務ロジックが漏れていないか（Command の場合、対象抽出のクエリまで Command に書いていないか）

### FormRequest
- [ ] バリデーションがあれば1APIに対して1つ定義されているか
- [ ] `createParam()`メソッドでDTOを生成しているか
- [ ] ヘッダパラメータ（user_idなど）もDTOに含めているか
- [ ] `$this->validated()`を使用しているか（`$this->input()`は禁止）

### UseCase
- [ ] 1API / 1バッチに対して1つ定義されているか
- [ ] `__invoke`を使用しているか
- [ ] 特別な場合を除きService経由で処理しているか
- [ ] Controller用のResultDTOを返しているか（ParamDTOとは別定義）

### Service
- [ ] 返り値が連想配列でないか（Eloquent、Domain、またはプリミティブ型を返す）
- [ ] 1メソッドがドメイン上の1操作に対応しているか（複数ユースケース分の手続きを1メソッドに詰めていないか）

### Infrastructure
- [ ] `App/Infrastructures/`下に配置されているか
- [ ] S3や外部APIの呼び出しをUsecase経由で行っているか（Service 経由は規約上 NG。ただし既存の違反が多いプロジェクトでは**新規追加分のみ**指摘する）
- [ ] 外部APIレスポンスをInfra層のDomainとして定義しているか

### Model / Domain / ValueObject
- [ ] ドメインの不変条件がModel / ValueObject側で守られているか（呼び出し側の`if`で担保していないか）
- [ ] 状態遷移が`StateMachines/`・Enumで表現されているか（生文字列・生数値の比較になっていないか）
- [ ] 業務上の識別子・区分値が`ValueObjects/`・`Enums/`として型を持っているか（`string`のまま引き回していないか）

### その他
- [ ] Repositoryパターンを使用していないか（プロジェクト規約で使用禁止としている場合。既存の使用箇所があっても新規追加は指摘対象）

### 抽象化・間接層の妥当性

新しい層・置き場の導入は、それ自体がレビュー対象。重複（DRY）ではなく **間接層のコストと値の所有権の分散** を見る。

- [ ] 新しく導入された層（ラッパー・定数クラス・ヘルパー・インターフェース）が解決している問題を specific に言えるか。言えなければ **QUESTION で意図を問う**（MUST で否定しない — 間接層には正当な理由があることも多い）
- [ ] 委譲するだけで自身の責務がない中間層になっていないか（Middle Man）
- [ ] 既に慣習的な置き場がある値・ロジックに、新たな置き場を作っていないか（置き場が増える＝次に触る人が探す場所が増える）
  - 判定材料: 同じ書き方が既存コードに何件あるか grep する。**0件＝リポジトリ初のパターン導入**なので、意図と標準化の是非を QUESTION で問う（grep 結果を evidence にする）
- [ ] 「将来のため」の抽象は、その将来が PR / Issue に根拠を持つか（YAGNI）

## 2. 命名規則

| 対象 | 規則 | 例 |
|------|------|-----|
| Controller | 単数形、APIエンドポイントのprefix | `SearchSuggestionController` |
| Controllerメソッド名 | 適切な動詞（index, store, destroyなど） | `index` |
| UseCase（API起点） | 「メソッド名」+Action | `IndexAction` |
| UseCase（バッチ / Job起点） | 「処理内容」+Task | `CancelTask`, `UpdateTask` |
| FormRequest | 「メソッド名」+Request | `IndexRequest` |
| ParamDTO | 「メソッド名」+ActionParamDTO | `IndexActionParamDTO` |
| Resource | 「メソッド名」+Resource | `IndexResource` |
| ResultDTO | 「メソッド名」+ActionResultDTO | `IndexActionResultDTO` |
| ResultDTO(配列) | 「メソッド名」+ActionResult+「配列名」+DTO | `IndexActionResultCategoryDTO` |
| パッケージ | Controller名の接頭辞 | `SearchSuggestion/` |

### 識別子の記法

- [ ] 変数・プロパティ・配列キーは snake_case、関数・メソッドは lowerCamelCase か（原典: プロジェクトのコーディング規約の命名ルール）
- [ ] 定数は UPPER_SNAKE か（明文規約なし・既存慣習と実指摘に基づく）
- [ ] 名前の意味が実体と一致するか — 単数/複数、真偽メソッドの向き（`is`/`has` が肯定を返すか）、略語・タイポ・全角文字の混入

## 3. コーディングルール

- [ ] `===`を使用しているか（`==`は禁止）
- [ ] 日時クラスがプロジェクト規約に沿っているか（導入元の例: `Carbon`を使用し`CarbonImmutable`は禁止）
- [ ] FormRequestで`$this->validated()`を使用しているか（`$this->input()`は禁止）
- [ ] 連想配列ではなくオブジェクトに詰め込んでいるか
- [ ] `DB::raw`/`selectRaw`等の生SQLの返り値型がPHP側の厳密比較と整合しているか
  - レビュー時にプロジェクトのDB種別を確認すること（`config/database.php`の`default`、または`.env`の`DB_CONNECTION`）
  - PDOドライバごとに数値カラムの返り値型が異なる（例: `pdo_pgsql`はstring型で返すことがある）
  - `withCount`等のEloquent機能は内部で`(int)`キャストするが、`DB::raw`経由ではキャストされない
  - 生SQLで取得したカラムを`=== 0`等で厳密比較する場合、モデルの`$casts`に`'integer'`を定義するか、明示的にキャストすること

### 既存資産・標準機能の重複実装

- [ ] 差分で手書きした処理の役割語（処理名の動詞・対象ドメイン名）で既存資産（Service メソッド・`scopeXxx`・Enum・Rule・共通 trait・Util）と Laravel 標準機能（`SoftDeletes`・`Rule::enum`・Collection の `firstWhere`/`keyBy` 等・`??`・`?->`）を Grep し、ヒットしたら**その実体を Read して差分の処理と同等か確認したうえで、同等なら置き換えを指摘する**（ヒットしただけで使わせない — 名前が近くても責務・戻り値・副作用が違うことがある）
- [ ] プロジェクト禁止イディオムを使っていないか: `empty()` / `DB::table` / `whereNull('deleted_at')` / `==`（明文規約なし・実指摘に基づく）

## 4. テスト

### テスト方針
- テストピラミッドを意識（Usecase/Serviceのテストを増やし、Featureテストを減らす）
- UnitテストとFeatureテストで同じ検証は不要

### テスト種別と観点

| テスト対象 | 種別 | チェック観点 |
|-----------|------|-------------|
| APIモジュール貫通 | Feature | 正常系1パターン以上、API特有の異常系全パターン |
| API I/F網羅 | Feature | 貫通で網羅できない場合にUsecaseモックで正常系網羅、バリデーション全パターン |
| ミドルウェア | Feature | 共通の異常系、モック対象: 外部API（モックする）/ DB操作（モックしない） |
| Service/Infrastructure | Unit | 正常系1パターン以上、外部APIモック、DB操作モックしない |
| Usecase | Unit | 貫通で網羅済みなら不要、トランザクション/ロールバックテスト |

### アサーション
- [ ] `assertExactJson`を使用しているか（`assertJson`ではなく）
  - エラーレスポンスなど全フィールド指定が困難な場合のみ`assertJson`可
- [ ] `createParam()`テスト時に`validateResolved()`を事前に呼び出しているか
- [ ] 外部APIをモックしているか
- [ ] DB操作をモックしていないか

### テストクラスの規約

原典: プロジェクトのテストコード規約（annotation・テストメソッドの英語命名・FormRequest=Feature テストの原典）。**注意**: 規約文書の OK 例に旧い命名が残存し、命名節と矛盾していることがある（導入元では旧・日本語メソッド名の例が残存していた。現行は英語 lowerCamel + `@testdox` 日本語）。以下 4 点は原典に無く直書き（実態・実指摘に基づく）:

- [ ] attribute 記法（`#[CoversClass]` / `#[Test]` / `#[TestDox]`）を使っているか（実態が文書に先行している）
- [ ] Controller テストは 1 メソッド 1 ファイルか。FormRequest のバリデーションテストは `tests/Feature/Http/Requests/` に単体で置かれているか（エンドポイント経由にしない）
- [ ] 入力だけ違う同型ケースは dataProvider に統合されているか
- [ ] **検証成立性**: テストが通る＝検証できているではない。対象実装を 1 行削っても通るテスト（アサーション不足・モックが本体を素通し）は網羅に数えない

## 5. ルーティング

- [ ] APIの種別に応じた適切なルーティングファイルに定義されているか
- [ ] 適切なミドルウェア（認証・認可等）が設定されているか
- [ ] エンドポイントのURL設計が既存のパターンと一貫しているか

## 6. バリデーション

- [ ] 適切なレイヤーでバリデーションが実施されているか
- [ ] 自サービスの責務範囲を超えたバリデーション（他サービスのデータ存在チェック等）が混入していないか

## 7. パフォーマンス・SQL分析

### 事前確認（レビュー開始時に1回）

- [ ] **DB種別を特定**: `config/database.php` の `default`、または `.env.example` の `DB_CONNECTION` を確認（`mysql` / `pgsql` / `sqlite`）。以降の最適化提案はDB種別に依存するため必須
- [ ] **対象テーブルのindex棚卸し**: 差分で触れるModelの `protected $table` を確認 → `database/migrations/` を `create_{table}_table` および `*add*index*`, `*add*unique*`, `$table->index(`, `$table->unique(`, `$table->foreign(` で grep → 既存index / UNIQUE / FK を一覧化
- [ ] **既存の検索専用カラムの有無**: `search_*_id`, `denormalized_*`, `*_cache` 等、検索用に正規化されたカラムが既に用意されていないか確認（あれば最適化案の根拠になる）

### クエリ構造の検出

Eloquent / Builder の差分で以下を検出する:

- [ ] **count() + get() の2回発行パターン**: `total_count` 等でCOUNTとデータ取得を両方行う場合、同じWHERE句が2回評価される。共通クロージャで `tap()` 化しているケースは特に全WHERE句が漏れなく2回実行される点に注意
- [ ] **N+1**: `with()` の欠落、ループ内での `$model->relation` アクセス、`foreach` 内の `find()` / `where()->get()` 等
- [ ] **EXISTSネスト**: `whereHas('a.b.c', ...)` のドット2段以上は EXISTS の多段ネストになる。中間テーブル経由で1段に減らせないか検討
- [ ] **両側ワイルドLIKE**: `LIKE '%X%'` は通常のBtree indexが効かない。以下の回避策を検討
    - MySQL: FULLTEXT index（ngram parser）、もしくは検索用正規化カラム
    - PostgreSQL: `pg_trgm` 拡張 + GIN index、もしくは検索用正規化カラム
- [ ] **関数式WHERE**: `whereRaw('a + b != 0')` や `WHERE LOWER(x) = ...` のような式は通常のindexが効かない
    - MySQL: 生成カラム + index、または計算結果カラムを事前保持
    - PostgreSQL: 式index（`CREATE INDEX ON t ((a + b))`）、必要なら部分index（`WHERE (a + b) != 0`）で追加
- [ ] **巨大サブクエリの再実行**: `whereIn('col', <重いSubquery>)` が複数クエリで使い回されていないか。されていれば先に `pluck()` で配列化してキャッシュできないか

### 実行計画の実測（EXPLAIN）

**パーティション表 / 関数式WHERE / 両側ワイルドLIKE / 型不一致の比較**のいずれかに触れる差分では、severity を確定する前に実行計画を取りに行く。「indexが効かないはず」という推論だけで MUST を立てない。

- [ ] **パーティション表かを先に判定**: マイグレーション・DDL を `PARTITION BY`、子テーブル命名（`*_y2026m09` 等）、`pg_partman` で grep。パーティション表では関数式WHERE・型不一致でプルーニングが効かず全パーティション走査になり、影響が単表より桁で大きくなる
- [ ] **実測の手段**（上から順に試す）
    1. worktree のローカルDBが**既に起動していれば**（`docker compose ps` で確認）そこで `EXPLAIN`
    2. プロジェクトで使っている読み取り専用の DB クライアントで、対象プロジェクトの**読み取り専用・stg** 接続に `EXPLAIN <SQL>` を投げる。**本番には接続しない**。環境で `psql` / `mysql` の直接実行が禁止されている場合は使わない。**`EXPLAIN ANALYZE` はクエリを実際に実行する**ため SELECT のみに使い、既定は実行を伴わない `EXPLAIN` にする
    3. どちらも取れない場合は **`evidence` に「EXPLAIN 未実測」と明記し、severity は SHOULD 以下に留める**
- [ ] **読む点**: プルーニングが効いているか（走査対象の子テーブル数）、`Seq Scan` / `Filter` に落ちていないか、想定した index が `Index Scan` として現れるか

### DB種別ごとの最適化手段

| 手法 | MySQL | PostgreSQL |
|------|-------|------------|
| `LIKE '%X%'` 高速化 | FULLTEXT + ngram parser | `pg_trgm` + GIN index |
| 関数式WHERE index化 | 生成カラム + index | 式index（部分index併用可） |
| CTE明示マテリアライズ | WITH（8.0+、inline扱い） | `WITH ... AS MATERIALIZED` (12+) |
| 大量IN句の代替 | `JOIN (VALUES ...)` | `= ANY(?::text[])` または TEMP TABLE |
| 準結合の最適化度 | 限定的 | プランナーが積極的にsemi-joinへ書き換え |

### 提案の妥当性セルフチェック（指摘を書き終えたら必ず通す）

指摘に「**○○に置き換えると改善する**」と書いた場合、以下を**指摘本文を書き終えた後に必ず自己検証**する:

- [ ] **`paginate()` / `simplePaginate()` 提案の罠**: Laravel の `paginate()` は内部で `count()` + `get()` を**別々に発行**する。クエリ回数は減らない。`simplePaginate()` は `total_count` を返さない仕様なので「total_countを返す要件」とは両立不可。total_count 追加PRでの改善策として提案しないこと
- [ ] **代替案が本当に問題を解決するか**: 「WHERE句が2回走る」指摘に対して「paginate()を使う」と書いた場合、それは同じ処理を別名で呼んでいるだけではないか。代替案のクエリ構造を自分で1回展開して確認
- [ ] **提案が要件と矛盾しないか**: レスポンス仕様、後方互換、既存クライアント影響との整合
- [ ] **DB種別と手段が整合しているか**: PostgreSQLプロジェクトに対してMySQL固有機能（FULLTEXT、SQL_CALC_FOUND_ROWS）を提案していないか、逆もまた然り
- [ ] **効果の見積もりがあるか**: 「○倍速くなる」「index使えるようになる」などクエリレベルで説明できるか。できないなら重要度を下げる（SHOULD → NITS、または情報共有）

セルフチェックで破綻が見つかったら **指摘を削除または重要度を下げる**、もしくは代替案を記述し直す。

### 7-2. マイグレーション・Seeder

原則: マイグレーション・Seeder は「どの環境で何回・どの順で実行されても安全」でなければならない。以下に明記がなくても原則に反するものは指摘する（列挙は網羅ではない）。

- [ ] `down()` が `up()` の全操作を打ち消しているか（追加した index・カラム・コメントの戻し漏れ）
- [ ] 再実行・途中失敗に対して冪等か（Seeder は upsert / 存在チェック）。デプロイ済みマイグレーションを改変していないか（修正は新規ファイルで行う）
- [ ] DB 方言と整合しているか（例: pgsql に unsigned は無い）。DB 種別は §7 事前確認の結果を使う
- [ ] 型・桁・NULL 可否・default が設計書・既存の同種カラムと整合し、index・シーケンス・カラムコメントの付け方が同種テーブルの既存慣習と揃っているか

## 8. ディレクトリ構造

正しい配置例:
```
app/.
├── Http                          # 入口（API・画面）
│   ├── Controllers/Api/{App|Backend}/
│   ├── Requests/Api/{App|Backend}/{機能名}/
│   └── Resources/Api/{App|Backend}/{機能名}/
├── Console/Commands/             # 入口（バッチ）。UseCase の Task を呼ぶだけに留める
├── Jobs/                         # 入口（非同期）。同上
├── UseCases/{機能名}/
│   ├── DTO/
│   ├── {メソッド名}Action.php     # API 起点
│   └── {処理内容}Task.php         # バッチ / Job 起点
├── Services/                     # ドメインロジック。Interface と実装を対で置く
├── Infrastructures/              # 外部 I/O（S3・外部API）の境界
├── Domain/                       # ドメインオブジェクト（※単数形。`Domains/` ではない）
├── ValueObjects/                 # 業務上の識別子・区分値
├── Enums/
└── StateMachines/                # 状態遷移の定義
```

## 9. セルフレビュー（Phase 6 の出力前に通す）

Phase 6 でレビュー結果のドラフトを書き終えたら、出力前に全指摘を以下の観点で自己検証する。

### 9-1. 根拠の確認

- [ ] **行番号の実在確認**: `ファイルパス:行番号` が worktree 内に実在するか Read。範囲外なら削除/修正
- [ ] **MUST の根拠引用**: 参照ルール（本ファイル等）の該当行を本文に引用する
- [ ] **Grep 0 件の補強**: Phase 5 で 0 件だった指摘は別パターン再検索の結果を「何が起きてる」欄に付記
- [ ] **パフォーマンス提案の妥当性**: 上記「7. 提案の妥当性セルフチェック」を全項目通す（`paginate()` の罠 / DB種別整合 / 代替案クエリの自己展開）

### 9-2. 読みやすさの確認（最重要）

レビュー対象のコードを頭に入れていない人がコールドで読める状態かを検証する。

- [ ] **1行要約だけで問題を把握できるか**: 「責務の不整合」「設計改善の余地」のような抽象語ではなく、「Interface に未使用宣言が残る」のように **問題そのもの** が読み取れるか
- [ ] **本文の4軸が各1〜2文に収まっているか**: 「何が起きてる／なぜまずい／どう直す」が長文化していないか。3文以上になっていたら文を分けるか、内容を「背景」へ追い出す
- [ ] **1指摘 = 1論点になっているか**: 1つの bullet で2つ以上の論点を扱っていないか。2論点あれば指摘を分割する（軽い方は NITS / QUESTION に降格してもよい）
- [ ] **背景セクションが分離できているか**: 前提構造の説明（「Xは Yを継承していて〜」）、中期論点、grep のヒット件数詳細、PR 説明の引用などが**指摘本体に混ざっていないか**。混ざっていれば「背景」ブロックへ移動
- [ ] **密度チェック**: 1文あたりのカッコ書き・コードトークン・引用が3個を超えていないか。超えていれば文を分ける

### 9-3. 全体粒度の確認

- [ ] **指摘粒度**: パフォーマンス指摘は「現象 / 原因構造 / 影響範囲（PR起因 vs 既存起因）/ 改善手段（短期/中期/長期）」を分けて記述
- [ ] **MUST/SHOULD/NITS の比率が妥当か**: 全部 MUST になっていないか。根拠の強さに応じて段階分けされているか
- [ ] **区分ラベルの網羅**: 全指摘の見出しに区分（🔵 今回の変更 / 🟡 既存の潜在問題）が付いており、verifier が確定した scope と一致しているか
- [ ] **Approve 判定の整合**: 総評に判定（✅/⚠️/❌）と判定理由があり、`output-format.md`「Approve 判定の基準」と矛盾していないか（🔵 の MUST があるのに ✅ になっていないか）

### 9-4. コメント提案の網羅確認（出力ゲート・省略不可）

- [ ] **全指摘にコメント提案が付いているか**: confirmed / downgraded の**全件**に、Phase 6「コメント提案の書き方」準拠の blockquote が1つずつ付いているか。**1件でも欠けていたら出力を差し戻し、付けてから出す**
- [ ] **提案が独立して読めるか**: 各コメント提案が本文の分析を読まなくても単体で成立し、GitHub にそのまま貼れる状態か（場所・問題・直し方・配慮の一言が揃っているか）
- [ ] **インラインレビューでも省略していないか**: worker×5 を省いて親が直接レビューした場合でも、Phase 6 テンプレ（コメント提案を含む）は省略不可。「小さい PR だから」で落とさない

根拠が薄い指摘は削除または重要度を下げる（MUST→SHOULD / SHOULD→NITS）。提案の妥当性で破綻が見つかったら提案部分を削除または代替案を書き直す。**読みにくいまま出すくらいなら指摘を統合または削除する**（量より理解しやすさを優先）。

## 10. 例外・エラーコード・ログ

SSOT: プロジェクトでエラーコードを共有パッケージ（エラーコード定義など）と設計書の異常系仕様書で管理している場合は、その 2 つを正とする（導入元では共有パッケージの `src/Enums/ErrorCode.php` が error_code の管理元で、submodule 管理・追加は関係者合意。異常系仕様書が reasons[].code 一覧 + Sentry 通知要否列を持つ）。下表の値は導入元の共有パッケージ現物（`src/Enums/ErrorCode.php` のステータス対応・`src/Exceptions/Handler.php` の `$dontReport`）で確認した例（2026-08-22）。

| 例外クラス | HTTP | Sentry 通知 |
|---|---|---|
| `ServiceException` | 500 | あり |
| `ClientException` | 400 | あり |
| `ValidationException` | 422 | なし |
| `NotFoundException` | 404 | なし |
| `ForbiddenException` | 403 | なし |

- [ ] 例外クラスを HTTP ステータスと Sentry 通知の要否で選べているか（上表。表に無いクラスは SSOT で確認する）
- [ ] 例外の送出方法がプロジェクト規約に統一されているか（導入元の例: `Exception::throw($e)` に統一・`abort()` は禁止）。`try` の範囲が例外を投げる処理だけに絞られ、二重ラップ・過度に広い catch 型になっていないか
- [ ] エラー理由コードがレスポンスに設定され、理由コード Enum の case 追加が対応する lang ファイル（`resources/lang/ja/` 配下）に追随しているか
- [ ] ログ原則: PII はマスキング登録してから出す / メッセージは検索可能な固定文言＋可変部 / 成功・失敗・タイムアウトを区別できる / ログ出力の失敗が本処理を落とさない

## 11. 未使用・残骸の検出

差分で参照が 0 になった資産（`use`・変数・引数・メソッド・ファイル）・到達不能になった `catch`/分岐・デバッグ痕・コメントアウトの消し残りは、列挙がなくても削除を指摘する（列挙は網羅ではない）。判定は Grep 0 件を根拠にする。今回の差分が原因でない既存の未使用は `scope: existing` に留める。逆方向の連鎖手順は `impact-check-rules.md` §12 を参照。
