# xcode-adhoc-export

Xcode の Ad Hoc IPA エクスポート（Archive → Export）を CLI で自動化するスキル。

## Trigger

ユーザーが `/xcode-adhoc-export` と入力した時にこのスキルを実行する。

## Configuration

`~/.claude/skills/xcode-adhoc-export/config.json` で設定をカスタマイズできる:

```json
{
  "exportBasePath": "~/dev/ipa"
}
```

| キー | デフォルト | 説明 |
|------|-----------|------|
| `exportBasePath` | `~/dev/ipa` | IPA エクスポート先のベースディレクトリ |

- `config.json` は環境固有の設定のため **Git 管理外**。雛形は同階層の `config.example.json`
- `config.json` が存在しない場合は Step 0 で **初回実行時に自動生成**する (ユーザーに `exportBasePath` を確認して作成)
- `config.json` は存在するがキーが未定義の場合はデフォルト値を使用する

## 進捗表示ルール

各ステップの実行時に、**必ず**以下の形式でヘッダーと結果サマリーをユーザーに表示すること。これにより進捗が一目でわかるようになる。

**ヘッダー形式:** `### Step {番号}: {ステップ名}`

各ステップで表示する内容:

| Step | ヘッダー | 表示内容 |
|------|---------|---------|
| 0 | `### Step 0: 設定読み込み` | `exportBasePath` の値 (config.json を新規作成した場合はその旨も) |
| 1 | `### Step 1: プロジェクト情報を自動検出` | 検出した Workspace, Scheme, Team ID, Bundle ID, Git Branch を箇条書き |
| 1b | `### Step 1b: Ad Hoc プロビジョニングプロファイルを検出` | 選択したプロファイル名・有効期限・署名証明書 CN |
| 2 | `### Step 2: エクスポートパスを生成` | 生成したエクスポートパス |
| 3 | `### Step 3: 確認` | AskUserQuestion（Step 3 自体が確認表示） |
| 4 | `### Step 4: ExportOptions.plist を生成` | 生成完了の旨 |
| 5 | `### Step 5: xcodebuild archive を実行` | 成功: **ARCHIVE SUCCEEDED** / 失敗: エラーログ末尾 |
| 6 | `### Step 6: xcodebuild -exportArchive を実行` | 成功: **EXPORT SUCCEEDED** / 失敗: エラーログ |
| 7 | `### Step 7: 結果を報告` | IPA パスとファイルサイズをテーブル形式で表示 |
| 8 | `### Step 8: Finder でエクスポート先を開く` | 実行完了の旨 |
| 9 | `### Step 9: クリーンアップ案内` | 手動削除コマンドと「/tmp は再起動時に自動削除される」旨を案内 |
| 10 | `### Step 10: 配布サイトへのアップロード案内` | AskUserQuestion(アップロードするか確認) |

**重要:** ステップを省略したり、ヘッダーなしで実行したりしないこと。ツール呼び出しの前後にヘッダーとサマリーを必ずテキスト出力する。

## Workflow

### 0. 設定を読み込み

`~/.claude/skills/xcode-adhoc-export/config.json` を読み込む。

**config.json が存在する場合:** 値を読み取り Step 1 へ進む。キーが未定義ならデフォルト値 (`exportBasePath`: `~/dev/ipa`) で補う。

**config.json が存在しない場合 (初回実行):** 以下の手順で生成してから Step 1 へ進む。

1. AskUserQuestion で `exportBasePath` を確認する
   - 質問: 「IPA のエクスポート先ベースディレクトリを指定してください (config.json を作成します)」
   - 選択肢: 「デフォルト `~/dev/ipa` を使う (推奨)」/ 別のパスは Other で入力
2. `config.example.json` と同じ形式で、回答した値を入れた `config.json` を **Write ツール**で新規作成する
   (新規ファイルの作成なので事前 Read は不要)
   ```json
   {
     "exportBasePath": "{回答したパス}"
   }
   ```
3. 「config.json を作成しました: {パス}」と表示し、以降はその値を使用する

パスは `~` 始まりのまま保存してよい (使用時にシェルが展開する)。

### 1. プロジェクト情報を自動検出

カレントディレクトリから以下を検出する:

```bash
# .xcworkspace を検出（Pods/ 配下を除外、.xcodeproj 内も除外）
find . -name "*.xcworkspace" -not -path "*/Pods/*" -not -path "*.xcodeproj/*" -maxdepth 2

# スキーム名 = ワークスペース名（拡張子なし）

# DEVELOPMENT_TEAM を project.pbxproj から抽出
grep -m1 'DEVELOPMENT_TEAM' */project.pbxproj

# PRODUCT_BUNDLE_IDENTIFIER を project.pbxproj から抽出
grep -m1 'PRODUCT_BUNDLE_IDENTIFIER' */project.pbxproj

# Git ブランチ名
git rev-parse --abbrev-ref HEAD
```

### 1b. Ad Hoc プロビジョニングプロファイルを検出

`references/find_profiles.sh` スクリプトを使って、有効な Ad Hoc プロファイルを検出する:

```bash
bash ~/.claude/skills/xcode-adhoc-export/references/find_profiles.sh "{TEAM_ID}" "{BUNDLE_ID}"
```

スクリプトの検出ロジック:
1. 以下の **2 ディレクトリ**の全 `.mobileprovision` をスキャン
   - `~/Library/Developer/Xcode/UserData/Provisioning Profiles/` (Xcode 16 以降の保存先)
   - `~/Library/MobileDevice/Provisioning Profiles/` (Xcode 15 以前の保存先)
2. Team ID が一致し、Ad Hoc 配布タイプのものをフィルタリング
3. **有効期限が現在時刻より未来のもののみ**を候補とする（期限切れは除外）
4. Bundle ID 完全一致 → ワイルドカード の優先順で、それぞれ**有効期限が最も未来のもの**を選択
   （証明書更新の移行期に新旧プロファイルが併存しても新しい方を採用する）
5. 選択したプロファイルの埋め込み証明書 (DeveloperCertificates) から、
   キーチェーンに identity (秘密鍵付き) が存在する証明書の CN を抽出する

出力形式: `PROFILE:{名前}|EXPIRE:{有効期限}|BUNDLE:{App ID}|TYPE:{exact|wildcard}|CERT:{証明書CN}`

選択結果が見つからない場合はエラー終了する（exit 1）。

**エラーハンドリング:**
- workspace が見つからない場合 → エラーメッセージを表示して終了
- scheme が不明な場合 → `xcodebuild -list -workspace {workspace}` でスキーム一覧を表示してユーザーに選択を求める
- TEAM_ID が見つからない場合 → AskUserQuestion でユーザーに手動入力を求める
- プロファイルが見つからない場合 → Apple Developer ポータルでの作成を案内して終了
- CERT が空の場合（秘密鍵がキーチェーンにない）→ AskUserQuestion で自動セレクタ
  （`iOS Distribution` / `Apple Distribution`）のどちらを signingCertificate に使うか選択を求める。
  あわせて「プロファイル埋め込み証明書の秘密鍵がこの Mac にない可能性が高い」旨を警告する

### 2. エクスポートパスを生成

パターン: `{exportBasePath}/{カレントディレクトリ名}/{ブランチ名}/{スキーム名 YYYY-MM-DD HH-MM-SS}/`

`exportBasePath` は config.json の値を使用する（デフォルト: `~/dev/ipa`）。

例: `~/dev/ipa/PhoenixViewer_Swift/main/PhoenixViewer 2026-02-19 15-30-00/`

### 3. 検出結果を表示し確認を求める

AskUserQuestion を使って以下を表示し、ユーザーの確認を得る:

- **Workspace**: 検出した .xcworkspace パス
- **Scheme**: スキーム名
- **Team ID**: DEVELOPMENT_TEAM の値
- **Bundle ID**: PRODUCT_BUNDLE_IDENTIFIER の値
- **Profile**: プロビジョニングプロファイル名
- **Certificate**: 署名証明書の CN（プロファイル埋め込み証明書から自動検出）
- **Git Branch**: ブランチ名
- **Export先**: 生成したエクスポートパス

選択肢: 「実行する」「キャンセル」

### 4. ExportOptions.plist を生成

1. テンプレートファイル `~/.claude/skills/xcode-adhoc-export/references/ExportOptions-template.plist` を **Read ツール**で読み込む
2. 以下のプレースホルダーを置換した内容を、**Bash のヒアドキュメント（`cat > /tmp/ExportOptions.plist << 'EOF'`）**で書き出す

- `__TEAM_ID__` → 実際のチームID
- `__BUNDLE_ID__` → 実際のバンドルID
- `__PROFILE_NAME__` → 検出したプロビジョニングプロファイル名
- `__SIGNING_CERTIFICATE__` → Step 1b で検出した証明書 CN
  (例: `iPhone Distribution: GENEROSITY Inc. (8463VYYM46)`。
  CERT が空だった場合はエラーハンドリングで選択した自動セレクタ)

**注意:** `/tmp/ExportOptions.plist` の書き出しには Write ツールを使用しないこと。Write ツールは事前に Read していないファイルへの書き込みを拒否するため、Bash ヒアドキュメントを使用する。

**重要:** `signingStyle` は `manual` を使用する。`automatic` では CLI 環境でプロファイルが見つからないため。

### 5. xcodebuild archive を実行

```bash
xcodebuild archive \
  -workspace "{workspace}" \
  -scheme "{scheme}" \
  -configuration Release \
  -destination "generic/platform=iOS" \
  -archivePath "/tmp/{scheme}.xcarchive"
```

- **timeout: 600000ms**（10分）で実行する
- 失敗した場合: エラーログの末尾20行を表示し、考えられる原因を提示する。archiveファイルがあれば残す

### 6. xcodebuild -exportArchive を実行

```bash
xcodebuild -exportArchive \
  -archivePath "/tmp/{scheme}.xcarchive" \
  -exportPath "{エクスポートパス}" \
  -exportOptionsPlist /tmp/ExportOptions.plist
```

- **timeout: 300000ms**（5分）で実行する
- 失敗した場合: エラーログを表示する。デバッグ用に archive は削除しない

### 7. 結果を報告

エクスポート成功後、以下を表示する:
- IPA ファイルのパス
- ファイルサイズ（人間が読みやすい形式: MB単位）

### 8. Finder でエクスポート先を開く

```bash
open "{エクスポートパス}"
```

### 9. クリーンアップ案内

コマンドは実行せず、以下のメッセージをユーザーに表示するだけにする:

> 必要に応じて以下の一時ファイルを手動で削除できます:
>
> ```bash
> rm -rf /tmp/{scheme}.xcarchive
> rm -f /tmp/ExportOptions.plist
> ```
>
> `/tmp` 配下のファイルはシステムの再起動時に自動的に削除されるため、手動で削除しなくても問題ありません。

### 10. 配布サイトへのアップロード案内

AskUserQuestion で「エクスポートした IPA を distribution.mirrorsnap.net にアップロードしますか？」と確認する。

- 選択肢: 「アップロードする」「しない」
- 「アップロードする」の場合: `~/.claude/skills/mirrorsnap-upload/SKILL.md` を読み込み、
  Step 7 で得た IPA パスを引数として mirrorsnap-upload スキルのワークフローを実行する
  (mirrorsnap-upload 側の Step 1「IPA を特定」はこのパスで確定済みとして進める)
- 「しない」の場合: 後から `/mirrorsnap-upload {IPAパス}` で実行できる旨を一言案内して終了する

## Technical Notes

- **`method: ad-hoc`**: Xcode GUI の "Release Testing" と同等。CLI では `ad-hoc` を使用する（`release-testing` は deprecated 警告の提案だが、`ad-hoc` で動作する）
- **`signingStyle: manual`**: CLI 環境では `automatic` だとプロファイルが見つからない。`manual` + `provisioningProfiles` の明示指定が必要
- **`signingCertificate`**: プロファイルに埋め込まれた証明書と一致している必要がある。
  不一致だと `Provisioning profile ... doesn't include signing certificate` で export が失敗する。
  キーチェーンに複数の配布証明書 (Apple Distribution / iPhone Distribution 等) がある環境では
  未指定だと自動セレクタが不一致の証明書を選び得るため、本スキルはプロファイルから
  抽出した CN を明示指定する。なお Xcode GUI 表示名「iOS Distribution」の証明書の
  CN は `iPhone Distribution: ...` (レガシー名) である点に注意
- **プロファイル保存先**: Xcode 16 以降は `~/Library/Developer/Xcode/UserData/Provisioning Profiles/`、
  Xcode 15 以前は `~/Library/MobileDevice/Provisioning Profiles/`。find_profiles.sh は両方をスキャンする
- **Xcode Organizer の "Default" 証明書**: 「Apple Distribution タイプの最新」を自動選択する仕様で、
  Default の対象をユーザー設定で変更する方法はない。本スキルは signingCertificate を明示指定するため
  Default の挙動に依存しない
- **`-destination "generic/platform=iOS"`**: シミュレータではなく実機向けにビルドするために必須
- **CocoaPods 対応**: `.xcworkspace` を使用するため、Pod 依存も含めてビルドされる
- **プロファイル検出**: `security cms -D` で .mobileprovision を XML デコードし、TeamID・Name・ExpirationDate・DeveloperCertificates を抽出する
