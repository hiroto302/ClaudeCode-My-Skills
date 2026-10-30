# mirrorsnap-upload

distribution.mirrorsnap.net(社内アプリ配布サイト)へ .ipa をアップロードするスキル。
新規追加・バージョン更新の両方に対応する。

## Trigger

ユーザーが `/mirrorsnap-upload [ipaパス]` と入力した時、または「配布サイトにアップロードして」等と依頼された時に実行する。

## Configuration

`~/.claude/skills/mirrorsnap-upload/config.json`:

| キー | デフォルト | 説明 |
|------|-----------|------|
| `credentialsPath` | `~/.config/mirrorsnap-distribution/env` | `MS_API` / `MS_WEB` / `MS_EMAIL` / `MS_PASSWORD` を export する認証ファイル(chmod 600)。**Unity の Distribution Uploader と同じファイルを共有する。** 無ければ Step 0 で作成する |
| `defaultEnvironment` | `test` | environment の既定値(`test` / `production`) |
| `products` | (キャッシュ) | プロダクト名 → productId の対応表。ここにないプロダクトは `GET /products` で取得して追記する |

## 重要な注意(必読)

> [!CAUTION]
> **`POST /apps` は冪等ではない。** 実行するたびに新しいアプリレコードが作られる。
> アップロード失敗時にスクリプトを頭から再実行してはいけない。
> `upload.sh` はアップロード部分(⑤〜⑦)のみ最大3回リトライし、それでも失敗した場合は
> `--app-id` 付きの再試行コマンドを出力するので、**必ずそのコマンドで再試行する**こと。

> [!IMPORTANT]
> **バージョン更新は `sourceAppId` の指定を忘れないこと。**
> 忘れると新しい QR が発行され、配布済みの QR から新バージョンが取得できなくなる。
> バージョン更新 = 「大元アプリ(`sourceAppId == null` のレコード)を親とした新規作成」。

## 進捗表示ルール

各ステップの実行時に、必ず `### Step {番号}: {ステップ名}` 形式のヘッダーと結果サマリーを表示すること。

| Step | ヘッダー | 表示内容 |
|------|---------|---------|
| 0 | `### Step 0: 設定・認証情報の確認` | credentialsPath の存在確認結果(無ければ作成フローの進捗) |
| 1 | `### Step 1: IPA を特定` | 使用する IPA のパスとサイズ |
| 2 | `### Step 2: モード選択` | AskUserQuestion(新規追加 / バージョン更新) |
| 3 | `### Step 3: 登録内容の決定` | 自動決定した product / title / version / environment / note を箇条書き(質問はしない) |
| 4 | `### Step 4: 最終確認` | AskUserQuestion(実行する / 内容を変更する / キャンセル)。変更時はタブ形式で項目ごとに再質問し、確認に戻る |
| 5 | `### Step 5: アップロード実行` | upload.sh の出力(進捗と結果) |
| 6 | `### Step 6: 結果を報告` | タイトル / バージョン / 環境 / 管理画面 URL をテーブル表示し、管理画面をブラウザで開く |

## Workflow

### 0. 設定・認証情報の確認

1. `config.json` を読み込む(存在しなければデフォルト値)
2. `credentialsPath` のファイルが存在するか確認する(`~` はシェルで展開する)。存在すれば Step 1 へ
3. **存在しない場合(初回)は以下の手順で作成してから Step 1 へ進む:**

   1. AskUserQuestion で配布サイトにログインしているメールアドレスを入力してもらう(Other で入力)。
      API / WEB の URL は既定値を使う:
      - `MS_API`: `https://api.distribution.mirrorsnap.net`
      - `MS_WEB`: `https://distribution.mirrorsnap.net`
   2. Unity の Distribution Uploader(`DistributionCredentials.WriteFile`)と同じ形式でファイルを作る。
      `MS_PASSWORD` は**空のまま**書く(パスワードはチャットに書かせない):
      ```bash
      mkdir -p "$(dirname {credentialsPath})"
      cat > {credentialsPath} << 'EOF'
      # distribution.mirrorsnap.net API 認証情報
      # このファイルは chmod 600 で保護すること。リポジトリにコミットしないこと。
      export MS_API='https://api.distribution.mirrorsnap.net'
      export MS_WEB='https://distribution.mirrorsnap.net'
      export MS_EMAIL='{入力されたメールアドレス}'
      export MS_PASSWORD=''
      EOF
      chmod 600 {credentialsPath}
      open -R {credentialsPath}
      ```
   3. 「Finder に表示したファイルをエディタで開き、`MS_PASSWORD=''` の中にパスワードを記入して保存してください。
      パスワードはチャットに書かないでください」と案内し、AskUserQuestion で記入完了を待つ
      (選択肢: 「記入した」/「中断する」。中断ならスキルを終了する)
   4. ログイン確認を行う。レスポンスは一度ファイルに保存し、トークンの値は表示しない:
      ```bash
      source {credentialsPath}
      curl -sS -o /tmp/ms_login.json -w '%{http_code}\n' -X POST "$MS_API/auth/login" \
        -H 'Content-Type: application/json' \
        -d "$(jq -n --arg e "$MS_EMAIL" --arg p "$MS_PASSWORD" '{email:$e, password:$p}')"
      jq -r 'if .idToken then "LOGIN OK" else "LOGIN FAILED" end' /tmp/ms_login.json
      rm -f /tmp/ms_login.json
      ```
      - `LOGIN OK` なら「認証情報を作成しました: {credentialsPath}」と表示して Step 1 へ
      - 失敗(401 など)なら、パスワードの記入ミスの可能性を伝えて手順 3 に戻る(ファイルは残す)

   このファイルは Unity の Distribution Uploader(`Window → Distribution Uploader` の「認証情報(ローカル)」)と
   共有される。どちらか一方で作れば、もう一方でもそのまま使える。

### 1. IPA を特定

優先順位:
1. スキル引数で渡されたパス
2. 直前の会話で xcode-adhoc-export がエクスポートした IPA
3. 上記がなければ、xcode-adhoc-export の exportBasePath(既定 `~/dev/ipa`)から最新の .ipa を検出して候補提示:
   ```bash
   find ~/dev/ipa -name '*.ipa' -newer /tmp -mtime -30 2>/dev/null | head -5
   # または
   ls -t $(find ~/dev/ipa -name '*.ipa' 2>/dev/null) 2>/dev/null | head -5
   ```
4. 見つからなければ AskUserQuestion でパスを尋ねる

### 2. モード選択

AskUserQuestion で「新規追加」か「バージョン更新」かを選択させる。

- **バージョン更新**の場合: 大元アプリの一覧を取得して対象を選ばせる。
  ```bash
  source {credentialsPath}
  TOKEN=$(curl -sS -X POST "$MS_API/auth/login" -H 'Content-Type: application/json' \
    -d "$(jq -n --arg e "$MS_EMAIL" --arg p "$MS_PASSWORD" '{email:$e, password:$p}')" | jq -r '.idToken')
  curl -sS "$MS_API/apps" -H "Authorization: Bearer $TOKEN" > /tmp/ms_apps.json
  jq -r '.apps[] | select(.sourceAppId == null) | [.id, .environment // "-", .appVersion, (.operationEndDate // "-"), .title] | @tsv' /tmp/ms_apps.json
  ```
  **注意:** レスポンスの note 欄等に制御文字が入ることがあるため、jq へ直接パイプせず必ず一度ファイルに保存してから処理する。
  タイトルや IPA の bundleIdentifier から対象を推測できる場合は候補を絞って AskUserQuestion で提示する
  (説明欄に作成日・環境・運用終了日を添える。例: 「2026-10-30 作成 / test / 運用終了日 2026-11-30」)。
  選択されたアプリの ID を `sourceAppId` とし、**個別取得**で運用終了日と QR 有効期限を読む
  (QR 有効期限 `tokens[].expiresAt` は一覧 `GET /apps` には含まれず、個別 `GET /apps/{id}` でしか取れない):
  ```bash
  curl -sS "$MS_API/apps/{sourceAppId}" -H "Authorization: Bearer $TOKEN" > /tmp/ms_source_app.json
  jq -r '.app | [(.operationEndDate // "-"), ((.tokens // []) | map(.expiresAt // empty) | max // "-")] | @tsv' /tmp/ms_source_app.json
  ```
  1 列目を運用終了日、2 列目を QR 有効期限の既定値とする(`-` なら未設定)。QR トークンが複数ある場合は最も遅い有効期限を採用する。

### 3. 登録内容の決定

**このステップでは質問しない。** 以下の規則で既定値を自動決定し、結果を箇条書きで表示して Step 4 へ進む。
値の変更は Step 4 の「内容を変更する」で受け付ける。

| 項目 | 既定値の決め方 |
|------|---------------|
| **product** | Bundle ID から config.json の `products` を推定する(例: `jp.co.generosity.MirrorSnap` → `MirrorSnap`)。推定できない場合のみ AskUserQuestion で選択させる |
| **title** | 新規追加: **ブランチ名をそのまま**使う(例: `20261029_eventname`、`main`)。バージョン更新: 元アプリの title を引き継ぐ |
| **app_version** | 新規追加: IPA の値 / バージョン更新: next-version API の自動採番(いずれも upload.sh が処理) |
| **environment** | config.json の `defaultEnvironment` |
| **note** | `更新日時: YYYY/MM/DD HH:MM` の形式で実行時刻を付ける(例: `更新日時: 2026/10/29 17:45`) |
| **運用終了日** | 新規追加: **実行日の 1 ヶ月後**(`date -v+1m "+%Y-%m-%d"`)/ バージョン更新: **元アプリの `operationEndDate` を引き継ぐ**(Step 2 で取得。元アプリが未設定なら未設定)。配布サイトの「運用終了日」はレコード単位なので、送らないと新バージョンでは消える。未設定なら常に運用中 |
| **QR 有効期限** | 新規追加: **実行日の 1 ヶ月後**(運用終了日と同じ日)/ バージョン更新: **元アプリの `tokens[].expiresAt` を引き継ぐ**(Step 2 の個別取得で読む。元アプリが未設定なら未設定)。QR トークンはバージョンごとに別発行なので、送らないと新バージョンの QR は無期限になる。設定した日の 23:59 まで使える |

Bundle ID とブランチ名の取得元(優先順):
1. 直前の会話で xcode-adhoc-export が検出した Bundle ID / Git Branch
2. Bundle ID: IPA ファイル名(`MirrorSnap.ipa` → MirrorSnap)。確実に取るなら
   `unzip -p "{IPAパス}" 'Payload/*.app/Info.plist' | plutil -convert xml1 -o - - | grep -A1 CFBundleIdentifier`
3. ブランチ名: カレントディレクトリで `git rev-parse --abbrev-ref HEAD`。Git リポジトリでなければ AskUserQuestion で title を入力してもらう

note の日時は `date "+%Y/%m/%d %H:%M"`、新規追加時の運用終了日・QR 有効期限の既定は `date -v+1m "+%Y-%m-%d"` で取得する
(月末の繰り上がりは date が処理する。例: 01-31 の 1 ヶ月後は 02-28)。

### 4. 最終確認

AskUserQuestion で以下を表示して確認を得る:

- IPA パス / サイズ
- モード(新規追加 / バージョン更新+元アプリ title)
- product / title / version / environment / note
- 運用終了日 / QR 有効期限(未設定なら「未設定」、設定時は `YYYY-MM-DD`。既定値のときは「2026-11-30 (既定: 1 ヶ月後)」「2026-11-30 (既定: 元アプリから引き継ぎ)」のように既定由来であることを両項目とも添える)
- バージョン更新の場合「配布済み QR がこの新バージョンを指すようになる」旨

選択肢: 「実行する」「内容を変更する」「キャンセル」

**「内容を変更する」が選ばれた場合:** AskUserQuestion は 1 回に 4 問までなので、2 段階で尋ねる。

1. **変更する項目を選ぶ**: AskUserQuestion(`multiSelect: true`)で以下の 6 項目から選ばせる。
   各選択肢の説明欄に現在の値を添える(例: 「運用終了日 (現在: 未設定)」)
   - product / title / environment / note / 運用終了日 / QR 有効期限
2. **選んだ項目だけ**を 1 回の AskUserQuestion にまとめて渡す(UI 上はタブで切り替わる)。
   5 問以上選ばれた場合は 4 問ずつに分けて 2 回に分割する。
   各問とも先頭の選択肢は「現在のまま: {現在の値}」にし、それ以外の値は Other で自由入力できるようにする。

| タブ | 選択肢 |
|------|--------|
| product | 現在のまま / config.json の `products` から主要候補を最大 3 つ(例: MirrorSnap Pro、受託、その他) |
| title | 現在のまま / ブランチ名に実行日 `YYMMDD_` を前置(例: `261029_main`) / Other で入力 |
| environment | 現在のまま / もう一方の値(`test` ↔ `production`) |
| note | 現在のまま / note なし / Other で入力 |
| 運用終了日 | 現在のまま / 未設定に戻す / 実行日の 1 ヶ月後 / Other で日付入力(`2026-12-31` または `2026/12/31`) |
| QR 有効期限 | 現在のまま / 未設定に戻す / 実行日の 1 ヶ月後 / Other で日付入力(同上) |

**日付の正規化と検証:** 運用終了日・QR 有効期限に Other で入力された値は、確認画面に戻る前に
`YYYY-MM-DD` へ正規化する(Unity の Distribution Uploader と同じく `yyyy-M-d` と `yyyy/M/d` を受け付ける):

```bash
d="{入力}"
date -j -f "%Y-%m-%d" "$d" "+%Y-%m-%d" 2>/dev/null || date -j -f "%Y/%m/%d" "$d" "+%Y-%m-%d" 2>/dev/null
```

- 出力が得られればその値を採用する
- どちらも失敗したら「「{入力}」は日付として読めません。YYYY-MM-DD の形で入力してください」と伝えて、
  その項目だけ AskUserQuestion で再入力を求める
- 過去の日付でも API は受け付けるため、「過去の日付です」と一言添えて続行する

回答を反映した登録内容を再表示し、**Step 4 の確認(実行する / 内容を変更する / キャンセル)に戻る。**
「実行する」が選ばれるまでこのループを繰り返す。

title にブランチ名由来の `/` が含まれる場合(例: `feature/xxx`)はそのまま渡してよいが、確認画面で見えるようにする。

### 5. アップロード実行

`references/upload.sh` を実行する。**timeout: 600000ms**(IPA は数百 MB になり得る)。
Step 4 で確定した最終値を渡す。note は Step 4 で「note なし」を選んだ場合のみ `--note` を省略する。

`--credentials` には config.json の `credentialsPath` を必ず渡す(upload.sh の既定値と config.json が食い違わないようにするため)。
運用終了日・QR 有効期限は**設定されている場合のみ** `--end-date` / `--qr-expires-at` を付ける(未設定なら引数ごと省略する)。

新規追加:
```bash
bash ~/.claude/skills/mirrorsnap-upload/references/upload.sh \
  --ipa "{IPAパス}" --title "{title}" --product-id "{productId}" \
  --environment "{environment}" --credentials "{credentialsPath}" \
  [--note "{note}"] [--end-date "{運用終了日 YYYY-MM-DD}"] [--qr-expires-at "{QR有効期限 YYYY-MM-DD}"]
```

バージョン更新(`--source-app-id` を追加):
```bash
bash ~/.claude/skills/mirrorsnap-upload/references/upload.sh \
  --ipa "{IPAパス}" --title "{title}" --product-id "{productId}" \
  --source-app-id "{sourceAppId}" --environment "{environment}" --credentials "{credentialsPath}" \
  [--note "{note}"] [--end-date "{運用終了日 YYYY-MM-DD}"] [--qr-expires-at "{QR有効期限 YYYY-MM-DD}"]
```

失敗時: スクリプトが表示する `--app-id` 付きコマンドに `--credentials "{credentialsPath}"` を付けてアップロードのみ再試行する。
**頭から再実行しない**(レコードが重複する)。エラーの意味は Technical Notes のエラー表を参照。

### 6. 結果を報告

upload.sh の出力から以下をテーブル表示する:

- タイトル / バージョン / 環境
- モード(新規追加 = 新しい QR を発行 / バージョン更新 = 配布済み QR を引き継ぎ)
- 管理画面 URL(`https://distribution.mirrorsnap.net/apps/{appId}`)

**インストール URL(`itms-services://...`)と配布リンクトークンは表示しない。**
QR の表示・共有は管理画面から行うため、共有先として案内するのは管理画面 URL のみにする。

表示後、管理画面をブラウザで自動的に開く:

```bash
open "https://distribution.mirrorsnap.net/apps/{appId}"
```

appId は upload.sh の出力 `appId: ...` 行、または `管理画面   : ...` 行から取る。

## Technical Notes

- **認証**: `POST /auth/login` で得る **idToken** を使う(accessToken を送ると 401)。有効期限1時間
- **iOS は ipaMetadata 必須**: `POST /apps/analyze-ipa-content` に Info.plist と embedded.mobileprovision の base64 を送り、返ってきた `.metadata` をそのまま `POST /apps` に渡す(証明書期限の Slack 通知に使われる)
- **bundleIdentifier は ipaMetadata から取る**: フォーム値と IPA の値が食い違うと 400
- **アップロードは3段階**: ⑤ `POST /apps/{id}/upload` で presigned URL 発行(10分有効)→ ⑥ S3 へ直接 PUT(Content-Type は⑤と完全一致必須。不一致だと S3 が 403)→ ⑦ `POST /apps/{id}/upload/complete` で確定。⑦ を呼ぶまで反映されない
- **同一アプリの同時アップロードは1件のみ**: ⑤ をやり直すと以前の uploadId は無効化される(⑦ で 409)
- **installUrl の実形式**(2026-09-25 実測): `itms-services://?action=download-manifest&url=https://api.distribution.mirrorsnap.net/public/apps/{token}/manifest.plist`(ガイド8章の `public/dl/...` 表記とは異なる。complete レスポンスの `tokens[].installUrl` をそのまま使う)
- **運用終了日 / QR 有効期限**: `POST /apps` の `operationEndDate` / `tokenExpiresAt` に `YYYY-MM-DD` で送る(upload.sh の `--end-date` / `--qr-expires-at`)。空なら送らない。新規追加の既定はどちらも実行日の 1 ヶ月後(1 ヶ月固定、config.json では変えない)
- **バージョン更新時の挙動**(2026-10-30 実測):
  - `distributionLinkToken` は元アプリと新バージョンで同一 → QR は引き継がれる
  - `operationEndDate` は**レコード単位**。更新時に送らないと新バージョンのレコードでは未設定になる → スキルは元アプリの値を既定で送る
  - QR 有効期限は一覧 `GET /apps` には含まれないが、個別 `GET /apps/{id}` の `app.tokens[].expiresAt` で読める。
    `tokens[].token` は**バージョンごとに別発行**で、更新時に `tokenExpiresAt` を送らないと新バージョンの QR は無期限になる → スキルは元アプリの値を既定で送る(Step 2 で個別取得)
- **レスポンスの jq 直パイプ禁止**: note 欄に制御文字が入り得るため、curl 出力は一度ファイルに保存してから jq で処理する
- **主要エラー**: 401=idToken 誤り/期限切れ(再ログイン)、400 `ipaMetadata`=解析やり直し、400 `bundleIdentifier`=IPA と不一致、409 `uploadId`=⑤からやり直し、404=appId 誤り、S3 403=Content-Type 不一致か URL 期限切れ
- **CI 組み込みは開発チームに要相談**(パスワード管理の方針があるため)。このスキルはローカル実行専用
