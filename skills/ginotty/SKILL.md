---
name: ginotty
description: 自作ノートアプリ Ginotty のノートを読み書きする。「:note:」形式のノートリンク（例 :note:01KX286YBGMKBKDAH73XJMCF24）が渡された時、「Ginotty」「ノートに書いて」「ノートを読んで」「ノートにまとめて」と言われた時にトリガーする。
---

# Ginotty

ユーザー自作のノートアプリ（Boostnote ライク、モノレポ: `~/Ginotty/packages/{cli,core,desktop}`）。
ノートの実体は **ローカルの Markdown ファイル**で、デスクトップアプリはそれを読み込んで表示しているだけ。
ノートリポジトリは **git 管理**されている。

## 基本情報

- **ノートリポジトリ**: `~/Ginotty_Notes/`
  - `notes/<フォルダ階層>/<タイトル>.md` — ノート本体
  - `assets/<ノートID>/` — 貼り付け画像などの添付
  - `trash/` — ゴミ箱
  - `ginotty.json` — フォルダ定義などの設定
- **CLI**: `node /Users/snsnap1159/Ginotty/packages/cli/dist/index.js`
  - ⚠️ `ginotty` コマンドは **zsh エイリアスなので非対話シェル（Bash ツール）では使えない**。必ず上記フルパスで `node` 起動すること

## ノートリンクの解決手順

ユーザーから `:note:01ABC...`（ULID）形式のリンクを渡されたら:

```bash
node /Users/snsnap1159/Ginotty/packages/cli/dist/index.js show <ID> --json
```

返り値（`{ ok, note }`）の `note` に以下が入っている:

| フィールド | 内容 |
|-----------|------|
| `id` / `title` / `type` | ID・タイトル・markdown/snippet |
| `folder` / `tags` / `star` / `pinned` | 整理情報 |
| `createdAt` / `updatedAt` | ISO 8601 タイムスタンプ |
| `path` | **リポジトリ相対パス**（例 `notes/Three.js/Water/海の中の表現.md`） |
| `body` | frontmatter を除いた本文 |

編集する場合は `~/Ginotty_Notes/<path>` を Read → Edit する。
`show` の引数は ID のほか**タイトル部分一致・パス**でも解決できる。

## 読み書きの作法

- **読み**: `show --json` で十分。ファイル全体（frontmatter 込み）が必要なら path を Read
- **書き（追記・修正）**: ファイルを直接 Edit してよい。ただし:
  - **frontmatter（`---` 区切りの id / title / folder / tags / createdAt / updatedAt 等）は変更しない** — アプリ/CLI が管理している
  - 画像参照はノートからの相対パス（`../../../assets/<ノートID>/xxx.png`）— 壊さないこと
  - 追記位置は指示に従う（「最後の行から」等）。書式は既存ノートの Markdown スタイルに合わせる
- **新規作成**: 直接ファイルを作らず CLI を使う（frontmatter と ID を正しく生成するため）:
  ```bash
  node .../index.js new "タイトル" -f "Three.js/Water" -t "tag1,tag2" -b "本文" --json
  ```

## CLI コマンドリファレンス

| コマンド | 用途 |
|---------|------|
| `show <note> [--json]` | ノート表示（ID / タイトル部分一致 / パスで解決） |
| `list [--json]` | ノート一覧（更新日時・タイトル・フォルダ・タグ） |
| `search <query> [--json]` | タイトル・タグ・本文の全文検索 |
| `new <title> [-f folder] [-t tags] [-b body]` | 新規ノート作成 |
| `tag <note>` | タグの追加・削除 |
| `trash <note>` / `restore <note>` | ゴミ箱へ移動 / 復元 |
| `sync` | **git 同期**（自動 commit → pull --rebase → push） |

## 同期の注意

`sync` はリモートへの push を伴うため、**勝手に実行せずユーザーに確認してから**行う。
ノートを編集しただけならファイル保存で完結しており、アプリは自動で反映する。
