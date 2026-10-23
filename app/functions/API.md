# バックエンド API 契約（Firebase Functions / Firestore / Storage / Web）

アプリ（Flutter）が呼ぶ関数と、保存されるドキュメントの形をまとめる。実装は `app/functions/src/`。仕様の根拠は設計書 5〜9・11〜14 章。

- リージョン: **`asia-northeast1`**（東京）。Flutter では `FirebaseFunctions.instanceFor(region: 'asia-northeast1')`。
- 認証: Firebase **匿名認証**。callable は `request.auth` が必須（匿名でよい）。
- 牌ラベル: `1m`〜`9m` `1p`〜`9p` `1s`〜`9s` `1z`〜`7z`（東南西北白發中）、赤5 は `0m` `0p` `0s`。サーバーは裏 `0b` を拒否する（37 種）。
- 日付は **JST の `YYYY-MM-DD`**。時刻は ISO 8601（UTC）または Firestore Timestamp。

## 0. アプリ側の流れ

```
起動        signInAnonymously → ensureUser({locale}) → 返ってきた referralCode を保存
紹介リンク   Android: Install Referrer の pid / ref → applyReferral({code: ref})。iOS: ユーザーが貼り付けたコード
公開        publishProblem → cardUploadPath に PNG を Storage へ → 共有（QR は url + ?ref=）
回答（アプリ） POST {siteUrl}/api/answer（Authorization: Bearer <ID トークン>、source: "app"）
今日の問題   daily/{今日(JST)} を get → official / picks の ID で problems/{id} を get
通報・削除   reportProblem / deleteMyData
```

`users/{uid}` は **ensureUser が作る**。クライアントは作成できない（Firestore ルール）。購入前・公開前に必ず一度呼ぶ。

## 1. callable

すべて匿名認証でよい。エラーは `FirebaseFunctionsException`（`code`、`details.reason`）。

### 1.1 `ensureUser`

ユーザードキュメントと自分の紹介コードを用意する。何度呼んでも同じ結果。

| | |
| --- | --- |
| リクエスト | `{ "locale": "ja" \| "en" }`（省略時 ja。最初の呼び出しの値だけが保存される） |
| レスポンス | `{ "referralCode": "ABCD2345", "nickname": string \| null, "pro": { "active": bool, "source": "revenuecat" \| "referral" \| null, "until": ISO \| null }, "created": bool }` |
| エラー | `unauthenticated` |

### 1.2 `publishProblem`

問題を公開する。リクエストは **アプリの `HandInput.toJson()` と同じキー**に、`answer` などを足したもの（`v` `dealer` `visible` は無視される）。

```jsonc
{
  "tiles": ["1m","2m","3m","5m","6m","4p","5p","6p","7s","8s","9s","2z","2z","9p"], // HandInput.tiles。副露を除く。長さは 14 − 3×副露数
  "tsumoIndex": 13,        // HandInput.tsumoIndex。指定した牌がツモ牌（サーバーが末尾に移す）。省略・null なら最後の牌
  "melds": [{ "kind": "pon", "tiles": ["5z","5z","5z"] }], // HandInput の MeldInput。kind は chi|pon|minkan|ankan（槓は 4 枚）。最大 4
  "dora": ["3z"],          // ドラ表示牌（ドラそのものではない）。0〜5 枚。カンドラの表示牌も続ける
  "seatWind": "south",     // east|south|west|north。省略時 south
  "roundWind": "east",     // 同上。省略時 east
  "turn": 6,               // 1〜18。省略可
  "nickname": "まじゃおう",  // 省略可。20 文字以内。省略時は前回の値（なければ空）
  "locale": "ja",          // ja|en。省略時 ja
  "answer": {              // アプリのエンジン（NanikiruEngine.analyze）の結果。ラベルは手牌の牌（赤5 は 5 でも 0 でもよい）
    "byAxis": { "speed": ["9p"], "points": ["9p","5m"], "balance": ["9p"] },  // 軸ごとの 1 位（同順位は複数）。各 1〜14 個、重複なし
    "ukeire": { "kinds": 8, "total": 24 },   // バランス軸の解を切った後の受け入れ（種類数 0〜34、枚数 0〜136）
    "shanten": 1,                            // -1〜8（バランス軸の解を切った後）
    "engineVersion": "1.1.0" // 1〜40 文字 [A-Za-z0-9._+/:@-]
  }
}
```

| | |
| --- | --- |
| レスポンス | `{ "problemId": "AbC12345", "existing": bool, "url": "https://<site>/p/AbC12345", "cardUploadPath": "cards/AbC12345/1x1.png" \| null }` |

- `problemId`: 8 文字の base62。QR・共有 URL は `url` に `?ref=<自分の紹介コード>` を付ける。
- **重複**: 手牌（並び順を無視、ツモ牌は区別）・副露・ドラ表示牌・自風・場風が同じ公開済み問題があれば、新規作成せず既存の ID を返す（`existing: true`、1 日の上限は消費しない）。他人の問題なら `cardUploadPath` は `null`（カードは上げない）。
- `cardUploadPath`: ここへ **PNG（1080×1080、900KB 以下、`contentType: image/png`）** を Storage SDK で置く（`putData`）。出題者本人だけが書ける（Storage ルール）。上書きは可、削除は不可。
- 1 ユーザー 1 日（JST）20 問まで。
- **`answer` は公開ドキュメント `problems/{id}` には保存されない**。`problems/{id}/private/answer`（Functions 専用、クライアントは読み書き不可）に書かれる。問題を Firestore から直接読んでも正解は分からない（3.2、3.4）。

| エラー | `code` | `details.reason` |
| --- | --- | --- |
| 未ログイン | `unauthenticated` | `unauthenticated` |
| 形式・値の誤り | `invalid-argument` | `invalid_request` `invalid_tiles`（枚数・ラベル・`tsumoIndex`）、`too_many_same_tile`（同種 5 枚以上。ドラ表示牌・副露も数える）、`too_many_red`（各色の赤 5 は 1 枚）、`invalid_meld`、`invalid_dora`、`invalid_wind`、`invalid_turn`、`invalid_answer`（解が手牌にない等）、`invalid_nickname`（長さ・制御文字）、`ng_word`。`details.field` に項目名 |
| 1 日の上限 | `resource-exhausted` | `daily_limit`（`details.limit` `details.used`） |

### 1.3 `reportProblem`

| | |
| --- | --- |
| リクエスト | `{ "problemId": "AbC12345", "reason": "spam" \| "offensive" \| "wrong_answer" \| "other" }`（reason 省略時 other） |
| レスポンス | `{ "reported": true, "alreadyReported": bool, "hidden": bool }` |
| エラー | `unauthenticated`、`invalid-argument`（`invalid_problem_id` `invalid_reason`）、`not-found`（`not_found`）、`permission-denied`（`own_problem`） |

同じ uid の通報は 1 件。数えられた通報が 3 件になると `hidden = true`（一般の読み取りから消える）。

**荒らし対策**: `users/{uid}.createdAt` から **24 時間未満**の uid、または `users/{uid}` が無い uid（`ensureUser` 未実行）の通報は、`reports/{uid}` に `counted: false` で記録するだけで、`problems.reports` には加算しない。レスポンスは通常の通報と同じ形（`counted` は返さない）。その uid が 24 時間後にもう一度通報しても、1 uid 1 件なので数えられない。閾値（3 件、24 時間）は `functions/src/config.ts` の `REPORT_HIDE_THRESHOLD` と `REPORTER_MIN_ACCOUNT_AGE_MS`。

### 1.4 `applyReferral`

| | |
| --- | --- |
| リクエスト | `{ "code": "ABCD2345" }`（大文字小文字・空白・ハイフンは問わない） |
| レスポンス | `{ "applied": true, "proUntil": ISO, "referrerRewarded": bool }` |
| エラー | `invalid-argument`（`invalid_code`: 形式が違う）、`not-found`（`invalid_code`: 存在しない）、`already-exists`（`already_applied`: 1 人 1 回）、`failed-precondition`（`self_referral`、`no_user`） |

両者に Pro 7 日（`users.pro.source = "referral"`）。紹介した側が特典を受けられるのは 10 人まで（`referrerRewarded` が false になる）。

### 1.5 `deleteMyData`

| | |
| --- | --- |
| リクエスト | なし（`{}`） |
| レスポンス | `{ "deleted": true, "problems": n, "answers": n, "reports": n }` |
| エラー | `unauthenticated` |

本人の `users`・紹介コード・回答/通報の記録を削除。本人の問題は `hidden = true`、`authorNickname = ""`、`authorUid = "deleted"` にし、カード画像を削除。最後に **Auth アカウントを削除**する。成功後、クライアントはサインアウトして新しい匿名アカウントから始める。集計済みの `stats` と、問題に付く `private/answer`（手牌から計算した解で、個人情報を含まない）は残る。

## 2. HTTPS

### 2.1 `answerProblem` — `POST /api/answer`

Web とアプリ共通。Hosting の rewrite（`/api/answer`）経由で呼ぶ（アプリも `https://<site>/api/answer`）。CORS 全許可、`Cache-Control: no-store`。

```jsonc
// Web
{ "problemId": "AbC12345", "tile": "9p", "source": "web", "fingerprint": "<端末ごとのランダム ID。[A-Za-z0-9_-]{16,64}>" }
// アプリ（ヘッダ Authorization: Bearer <Firebase ID トークン>。fingerprint は不要、uid が使われる）
{ "problemId": "AbC12345", "tile": "9p", "source": "app", "selfRank": 3 }   // selfRank は任意（1〜14。自分のエンジンでの順位）
```

`tile` は **その問題の手牌（副露を除く）にある牌ラベルそのもの**（赤5 が手牌にあれば `0m`）。

正解（`answer`）は Firestore の公開ドキュメントにはないので、**回答後のこのレスポンスだけが返す**（Functions が `problems/{id}/private/answer` から読む）。アプリで他人の問題を解くときも、このレスポンスか、手元のエンジンでの再計算で正誤を判定する。

レスポンス `200`:

```jsonc
{
  "ok": true,
  "alreadyAnswered": false,            // true: 同じ端末/uid の 2 回目。集計は増えず、最初の回答が返る
  "yourTile": "9p",
  "correct": true,                     // バランス軸の解と一致（stats.correct に数える基準）
  "judgement": { "speed": true, "points": false, "balance": true },   // 各軸の解と一致したか（赤5 は 5 と同一視）
  "stats": { "total": 12, "correct": 7, "byTile": { "9p": 7, "5m": 5 } },
  "answer": { "byAxis": { ... }, "ukeire": { "kinds": 8, "total": 24 }, "shanten": 1, "engineVersion": "..." }
}
```

| HTTP | `error.code` | 意味 |
| --- | --- | --- |
| 400 | `invalid_request` `invalid_problem_id` `invalid_tile`（牌ラベル不正、または手牌にない牌）`invalid_source` `invalid_fingerprint` `invalid_self_rank` | 入力の誤り |
| 401 | `unauthenticated` | source=app で ID トークンが無い・無効 |
| 404 | `not_found` | 問題が無い・hidden |
| 405 | `method_not_allowed` | POST 以外 |
| 500 | `internal` | |

エラー本文は `{ "error": { "code": "...", "message": "..." } }`。10・50・100 人目の回答で出題者へ FCM（`data.type = "answer_milestone"`、`problemId`、`count`）。

### 2.2 `renderProblemPage` — `GET /p/{problemId}`

SSR の HTML（OGP 付き）。クエリ: `ref`（紹介コード、ストアのリンクに入る）、`lang`（`ja`|`en`、省略時は `Accept-Language`）。`og:image` は `cards/{id}/1x1.png`（無ければ `/assets/og-default.png`）。問題が無い・hidden は 404。答えと統計は HTML に含めない（回答後に `/api/answer` が返す）。

### 2.3 `revenuecatWebhook`

RevenueCat → サーバー。`Authorization` ヘッダ（ダッシュボードの Authorization header value と同じ値、`Bearer ` 付きも可）で検証。`users/{uid}.pro` を更新する（uid = RevenueCat の App User ID = Firebase uid。`purchases_flutter` は `appUserID: firebaseUid` で `configure` する）。権利 ID は **`pro`**。

- 401: 認証ヘッダが違う / 400: 本文が不正 / 405: POST 以外 / 5xx: 内部エラー（RevenueCat が再送）。
- それ以外は 200（`{ ok, status: "applied" \| "ignored" \| "unknown_user", ... }`）。再送（同じ `event.id`）や古いイベントは無視。
- CANCELLATION（解約）は期限まで有効のまま。返金（`cancel_reason = CUSTOMER_SUPPORT`）と EXPIRATION で無効。BILLING_ISSUE は猶予期間の終わりまで有効。

### 2.4 スケジュール

| 関数 | 時刻（JST） | 内容 |
| --- | --- | --- |
| `pickDaily` | 毎日 00:00 | `daily/{今日}` を作る（公式 1 問 + ユーザー投稿 2 問）。再実行しても二重に選ばない |
| `notifyDaily` | 毎日 07:30 | FCM トピック `daily` に「今日の問題」通知（0:00 に鳴らさないため `pickDaily` から分離） |
| `autoPost` | 毎日 19:00 | 今日の問題をカード PNG 付きで Bluesky・Threads・Discord（X は設定で有効化）へ投稿し、昨日の投稿に答え合わせを返信 |
| `weeklyDigest` | 日曜 20:00 | 今週の難問 TOP3 と「速さ派 vs 打点派」を投稿、FCM トピック `weekly` に通知 |

## 3. Firestore（クライアントから見える形）

読み取りのルール: `problems` は `hidden == false` のものを誰でも（**一覧は `where('hidden', isEqualTo: false)` が必要**）。出題者本人は自分の問題を `where('authorUid', isEqualTo: uid)` で一覧できる（hidden 含む）。書き込みはクライアントから不可（ユーザー設定の一部を除く）。

### 3.1 `users/{uid}`（本人だけ get 可。一覧・作成・削除は不可）

| フィールド | 型 | 書き手 | 内容 |
| --- | --- | --- | --- |
| `locale` | `"ja"\|"en"` | クライアント可 | |
| `fcmTokens` | string[]（10 個まで） | クライアント可 | FCM トークン |
| `notify` | map | クライアント可 | `{ daily?: bool, weekly?: bool, milestone?: bool }`。`milestone == false` で回答到達通知を止める |
| `streak` | map | クライアント可 | `{ current, best, lastAnsweredDate }` |
| `createdAt` | Timestamp | サーバー | |
| `nickname` | string \| null | サーバー | 直近に公開した問題のニックネーム（検査済み） |
| `referralCode` | string | サーバー | 自分の紹介コード（8 文字、I O 0 1 を除く） |
| `referredBy` | string? | サーバー | 適用した紹介コード |
| `problemCount` | int | サーバー | 公開した問題の数 |
| `publishQuota` | `{date, count}` | サーバー | 1 日の公開数 |
| `pro` | map | サーバー | 下記 |

`pro`: `{ active: bool, source: "revenuecat"\|"referral"\|null, until: Timestamp\|null, revenuecat?: {...}, referral?: { until } }`。`active`/`until` は **書き込み時点の要約**。クライアントは「`until` が null（期限なし）または現在時刻より後」を Pro とし、**端末側の RevenueCat の `CustomerInfo` との OR**（設計書 9 章）で判定する。

### 3.2 `problems/{problemId}`

```jsonc
{
  "tiles": ["1m", ..., "9p"],   // 手牌（副露を除く）。ツモ牌が最後
  "tsumo": "9p",                // = tiles の最後
  "tsumoIndex": 13,             // = tiles.length - 1。HandInput.fromJson にそのまま渡せる
  "melds": [{ "kind": "pon", "tiles": ["5z","5z","5z"] }],
  "dora": ["3z"],               // ドラ表示牌
  "seatWind": "south", "roundWind": "east", "turn": 6,   // turn は null あり。dealer は seatWind == "east" で求める
  "authorUid": "...", "authorNickname": "まじゃおう",     // 削除済みユーザーは authorUid = "deleted"、nickname = ""
  "createdAt": Timestamp, "locale": "ja",
  "stats": { "total": 0, "correct": 0, "byTile": { "9p": 0 } },
  "featured": { "daily": "2026-10-21" | null, "posted": false },
  "reports": 0, "hidden": false,
  "cardPath": "cards/AbC12345/1x1.png",
  "contentKey": "..."           // 重複判定用（クライアントは使わない）
}
```

- `problems/{id}/answers/*` と `problems/{id}/reports/*` は **クライアントから読めない**（Functions のみ）。
- 作者名・回答数・正解率は `problems` から読む。**`problems` に `answer` フィールドは無い**（以前の設計書 5.2 にあった `answer` は `problems/{id}/private/answer` に移した）。
- `problems/{id}/private/*` も **クライアントから読めない**（出題者本人も不可、コレクショングループクエリも不可）。
- 正解の判定: Web とカードではバランス軸を正解、他の軸を別解として表示する。アプリは `answerProblem` のレスポンス（`answer.byAxis`）か、手元のエンジンの結果を使う。

### 3.3 `daily/{YYYY-MM-DD}`（誰でも get 可）

`{ official: problemId \| null, picks: problemId[0..2], generatedAt, postedProblemId?, posts?, answerReplies? }`。今日の問題は `official` と `picks`。

### 3.4 サーバー専用（クライアントは読み書き不可）

| コレクション | 内容 |
| --- | --- |
| `problems/{id}/private/answer` | 正解 `{ byAxis: {speed, points, balance}, ukeire: {kinds, total}, shanten, engineVersion }`（`publishProblem` に渡した `answer` と同じ形）。`publishProblem` が書き、`answerProblem`・`pickDaily`・`autoPost`（翌日の答え合わせ）・`weeklyDigest` が読む |
| `problems/{id}/answers/{fingerprintHash}` | 回答の記録 `{ tile, source, fingerprint, uid, createdAt, selfRank }` |
| `problems/{id}/reports/{uid}` | 通報の記録 `{ uid, reason, counted, createdAt }`。`counted` が false の通報は件数に数えない（1.3） |
| `referrals/{code}` | `{ uid, uses, createdAt }` |
| `official/{docId}` | 公式問題の待ち行列 `{ problemId, order: number, used: false, usedDate: null }`。運営が追加する（問題自体は `problems` に作っておく） |
| `weekly/{date}` | 週間投稿の記録 |
| `_system/threads` | Threads のアクセストークン更新用 |

## 4. Storage

`cards/{problemId}/1x1.png` — OGP とカード共有用。読み取りは誰でも。書き込みは **その問題の出題者本人だけ**（ルールが `problems/{problemId}.authorUid` を参照）、`image/png`、900KB 以下、ファイル名は `1x1.png` のみ。`publishProblem` の後に置く。公開 URL: `https://firebasestorage.googleapis.com/v0/b/<bucket>/o/cards%2F<id>%2F1x1.png?alt=media`。

## 5. Web・リンク

| URL | 内容 |
| --- | --- |
| `/p/{problemId}?ref={code}` | Web 問題ページ。タップで回答 → 分布と 3 軸の解 → 「解説をアプリで見る」 |
| `/r/{code}` | 紹介コードの着地ページ（静的。コードを表示してストアへ） |
| `/.well-known/apple-app-site-association`、`/.well-known/assetlinks.json` | `/p/*` `/r/*` をアプリに関連付ける（Team ID と署名フィンガープリントは TODO） |
| `/terms` `/privacy` `/tokushoho` | 規約・プライバシー・特商法（`【要記入】` あり） |

- Google Play の `referrer`: `utm_source=share&utm_campaign=problem|referral&pid={problemId}&ref={code}`（URL エンコード済みで付く）。アプリは初回起動で Install Referrer API から `pid` と `ref` を読む。
- App Store: `pt`（プロバイダトークン）と `ct=problem|referral` のみ。iOS は遅延ディープリンクがないので `pid` `ref` は渡らない。
- Universal Links / App Links で開かれたとき、`/p/{id}` は問題画面、`/r/{code}` は紹介コードの適用に使う。

## 6. 設定（デプロイ時）

`functions/.env.<projectId>`（または環境変数）と Secret Manager。`functions/.env.example` を参照。

| 名前 | 種類 | 既定 | 内容 |
| --- | --- | --- | --- |
| `SITE_URL` | param | `https://nanikiru-cam.web.app` | 公開 URL（独自ドメインにしたら変更） |
| `IOS_APP_STORE_ID` `IOS_PROVIDER_TOKEN` | param | 空 | App Store の ID とキャンペーンのプロバイダトークン。空なら Web ページに iOS ボタンを出さない |
| `ANDROID_PACKAGE` | param | `jp.aile.nanikiru_cam` | |
| `GA4_MEASUREMENT_ID` | param | 空 | Web の GA4。空なら読み込まない |
| `ENFORCE_APP_CHECK` | 環境変数 | false | `true` で callable に App Check を必須にする |
| `BLUESKY_HANDLE` `THREADS_USER_ID` `X_ENABLED` | param | 空 / 空 / false | |
| （定数）`REPORT_HIDE_THRESHOLD` `REPORTER_MIN_ACCOUNT_AGE_MS` | `src/config.ts` | 3 件 / 24 時間 | 通報で hidden にする件数と、通報を数える最小のアカウント年齢（1.3） |
| `REVENUECAT_WEBHOOK_SECRET` | secret | — | RevenueCat の Authorization header value |
| `BLUESKY_APP_PASSWORD` `THREADS_ACCESS_TOKEN` `DISCORD_WEBHOOK_URL` `X_CREDENTIALS` | secret | — | 未使用の投稿先は `-` を登録（`-` と空は「使わない」扱い）。`X_CREDENTIALS` は `{"apiKey","apiSecret","accessToken","accessSecret"}` の JSON |
