---
name: sync-skills
description: ~/.claude/skills/（ライブ環境）で編集したスキルをリポジトリに同期し、差分を分析して意味のあるコミットメッセージを生成してGitにコミットする。「/sync-skills」「スキルを同期して」「sync skills」と言った時にトリガーする。
allowed-tools: Bash, Read, Write, Edit
---

# Sync Skills

`~/.claude/skills/` のスキルファイルをリポジトリの `skills/` に同期し、変更をGitコミットする。

**どのディレクトリからでも実行可能。** すべてのコマンドは設定ファイルから読み取ったリポジトリパスを使用する。

## 設定ファイル

パス: `~/.claude/skills/sync-skills/config`

```
REPO_DIR=/Users/yourname/path/to/ClaudeCode-My-Skills
```

- 各環境でリポジトリのクローン先が異なるため、設定ファイルでパスを管理する
- このファイルは `.gitignore` に含まれており、各ユーザーが自分の環境に合わせて作成する

## ワークフロー

### 0. 設定を読み込む

スキル実行時、最初に `~/.claude/skills/sync-skills/config` を読み取り `REPO_DIR` を取得する。

```bash
cat ~/.claude/skills/sync-skills/config
```

**設定ファイルが存在しない場合:**
1. ユーザーにリポジトリのパスを聞く（AskUserQuestion）
2. 入力されたパスで `config` ファイルを作成する
3. 作成後、ワークフローを続行する

以降のすべてのコマンドで `$REPO_DIR` を使用する。git コマンドは `git -C $REPO_DIR` で実行する。

### 1. rsyncでスキルを同期する

以下のコマンドでライブ環境からリポジトリへ同期する:

```bash
rsync -av --delete \
  --exclude='.DS_Store' \
  --exclude='*.swp' \
  --exclude='.git' \
  ~/.claude/skills/ $REPO_DIR/skills/
```

- `--delete` で削除されたスキルも反映する
- `.DS_Store` などの不要ファイルは除外する

### 2. 変更を検出する

```bash
git -C $REPO_DIR status --short
git -C $REPO_DIR diff
git -C $REPO_DIR diff --cached
```

変更がなければ「スキルは最新です。同期する変更はありません。」と伝えて終了する。

### 3. 差分を分析する

変更がある場合、`git diff` と `git status` の出力を読み取り、**スキル単位**で変更を分類する:

- 新規追加されたスキル
- 更新されたスキル（具体的にどの部分が変わったか）
- 削除されたスキル

変更内容をスキルごとに一覧で報告する。例:

```
変更を検出しました:
1. [新規] sync-skills - スキル同期の自動化スキル
2. [更新] session-summary - スタイル選択機能を追加
3. [削除] old-unused-skill
```

### 4. 同期対象を選択する

変更が**複数スキル**にまたがる場合、ユーザーに同期方法を選択させる:

- **すべて同期** — 全変更をまとめて1コミット
- **個別に選択** — スキルごとに同期するか確認し、選択したものだけを個別コミット

変更が**1スキルのみ**の場合はこのステップをスキップする。

#### 「個別に選択」の場合

スキルごとに「同期する / スキップする」を確認する。スキップされたスキルの変更は `git checkout` で元に戻す:

```bash
# スキップされたスキルの変更を元に戻す
git -C $REPO_DIR checkout -- skills/{スキップしたスキル名}/
```

選択されたスキルごとに個別のコミットを作成する（ステップ5-6をスキルごとに繰り返す）。

### 5. コミットメッセージを生成する

[COMMIT_RULES.md](references/COMMIT_RULES.md) のルールに従い、差分の内容に基づいて適切なコミットメッセージを生成する。

重要なルール:
- 差分の「意味」を反映するメッセージにする（ファイル名の羅列ではなく）
- 個別コミットの場合は各スキルに対して1つずつメッセージを生成する
- まとめてコミットの場合で複数スキルがあるときは、最も重要な変更を先頭に書く

生成したコミットメッセージをユーザーに提示する。

### 6. コミットする

```bash
# まとめてコミットの場合
git -C $REPO_DIR add skills/
git -C $REPO_DIR commit -m "<生成したメッセージ>"

# 個別コミットの場合（スキルごと）
git -C $REPO_DIR add skills/{スキル名}/
git -C $REPO_DIR commit -m "<そのスキルのメッセージ>"
```

### 7. プッシュの確認

全コミット完了後、ユーザーに「GitHubにプッシュしますか？」と確認する。

承認された場合のみ:
```bash
git -C $REPO_DIR push origin main
```

拒否された場合はコミットだけで終了し、その旨を伝える。
