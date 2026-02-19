# xcode-adhoc-export

Xcode Ad Hoc IPA export (Archive + Export) を CLI で自動化する Claude Code スキル。

## 前提条件

- macOS + Xcode がインストール済み
- CocoaPods を使用するプロジェクト（`.xcworkspace` があること）
- Ad Hoc 用のプロビジョニングプロファイルが Mac にインストール済み
  - `~/Library/MobileDevice/Provisioning Profiles/` に `.mobileprovision` が存在すること
  - Xcode > Settings > Accounts からダウンロード可能

## セットアップ

### 1. スキルファイルの配置

以下のファイルを `~/.claude/skills/xcode-adhoc-export/` に配置する:

```
~/.claude/skills/xcode-adhoc-export/
  SKILL.md
  config.json
  README.md                          # このファイル（配置は任意）
  references/
    ExportOptions-template.plist
    find_profiles.sh                 # Ad Hoc プロファイル検出スクリプト
```

### 2. config.json の設定

IPA の出力先を指定する。未作成の場合はデフォルト値 `~/dev/ipa` が使用される。

```json
{
  "exportBasePath": "~/dev/ipa"
}
```

### 3. パーミッションの設定

スキルが使用する Bash コマンドを自動許可するため、**プロジェクトの** `.claude/settings.local.json` に以下を追加する:

```json
{
  "permissions": {
    "allow": [
      "Bash(git rev-parse *)",
      "Bash(xcodebuild *)",
      "Bash(bash ~/.claude/skills/xcode-adhoc-export/references/find_profiles.sh *)",
      "Bash(open *)",
      "Bash(mkdir *)"
    ]
  }
}
```

> **注意:** `find`、`grep`、`cat`、`ls` などの読み取り系コマンドはユーザーレベル (`~/.claude/settings.json`) で許可済みであることが多い。
> 未許可の場合は実行時に都度確認が表示される。

各パターンの用途:

| パターン | 用途 |
|---------|------|
| `Bash(git rev-parse *)` | Git ブランチ名の取得 |
| `Bash(xcodebuild *)` | archive・exportArchive の実行 |
| `Bash(bash ~/.claude/skills/xcode-adhoc-export/references/find_profiles.sh *)` | Ad Hoc プロビジョニングプロファイルの検出 |
| `Bash(open *)` | Finder でエクスポート先を開く |
| `Bash(mkdir *)` | エクスポート先ディレクトリの作成 |

> **パーミッションの制限事項:** Claude Code の `*` ワイルドカードは改行文字にマッチしない。
> そのため複数行の Bash コマンドは自動許可できず、`find_profiles.sh` のように外部スクリプト化して1行コマンドで実行する必要がある。

### 4. (任意) ユーザーレベルのパーミッション

複数プロジェクトで使う場合は `~/.claude/settings.json` の `permissions.allow` に追加してもよい。

## 使い方

Xcode プロジェクトのディレクトリで Claude Code を起動し、以下を入力:

```
/xcode-adhoc-export
```

Step 0〜9 の進捗が表示され、確認後に IPA がエクスポートされる。

## 今後の改善案

### Ad Hoc プロビジョニングプロファイルの配置・参照

現在はローカルの `~/Library/MobileDevice/Provisioning Profiles/` から自動検出しているが、以下の方法でさらに改善が可能:

- **references/ にプロファイルを直接配置**: `.mobileprovision` ファイルを `references/` に入れておき、チームメンバーが clone するだけでプロファイルを取得できるようにする
- **references/ にダウンロード URL を配置**: Apple Developer Portal のプロファイル URL や社内配布サーバーの URL を記載した設定ファイルを置き、スクリプトで自動ダウンロード → インストールする

これにより「Mac にプロファイルがインストールされていない」場合でもスキル側で解決でき、セットアップの手間を減らせる。

### Step 0〜9 の完全自動実行（確認ステップのスキップ）

現在は Step 3 で AskUserQuestion による確認が入り、ユーザーが「実行する」を選択する必要がある。これを config.json やパーミッション設定で制御し、確認なしで Step 0〜9 を一気通貫で自動実行できるようにする。

想定される実装案:

- **config.json に `skipConfirmation` フラグを追加**: `true` の場合、Step 3 の確認を省略して即座にビルドを開始する
  ```json
  {
    "exportBasePath": "~/dev/ipa",
    "skipConfirmation": true
  }
  ```
- **SKILL.md の Step 3 に条件分岐を追記**: `skipConfirmation` が `true` の場合は検出結果を表示するのみで AskUserQuestion を呼ばない

これにより `/xcode-adhoc-export` を入力するだけで、確認操作なしに IPA が出力されるワンコマンド運用が可能になる。
