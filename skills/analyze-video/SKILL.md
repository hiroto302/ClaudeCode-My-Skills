---
name: analyze-video
description: 動画ファイル（.mov, .mp4 など）からキーフレームを抽出し、Claude Code で画像として分析する。「/analyze-video」「動画を分析して」「この動画を見て」と言った時にトリガーする。
disable-model-invocation: true
user-invocable: true
argument-hint: "[動画ファイルパス]"
allowed-tools: Bash, Read, Write, AskUserQuestion
---

# analyze-video

動画ファイルからキーフレームを抽出し、Claude Code の画像読み込み機能で内容を分析するスキル。

## Trigger

ユーザーが `/analyze-video` と入力した時、または「動画を分析して」「この動画を見て」と言った時にこのスキルを実行する。

## Configuration

`~/.claude/skills/analyze-video/config.json` で設定をカスタマイズできる。

| キー | デフォルト | 説明 |
|------|-----------|------|
| `defaults.preset` | `standard` | デフォルトのプリセット（quick/standard/detailed） |
| `defaults.filter_mode` | `scene` | デフォルトのフィルタモード（scene/similarity/time） |
| `defaults.time_interval` | `5` | time モードの間隔（秒） |
| `max_frames` | `100` | 安全制限（超過時は警告） |

## 進捗表示ルール

各ステップの実行時に、**必ず**以下の形式でヘッダーと結果サマリーをユーザーに表示すること。

**ヘッダー形式:** `### Step {番号}: {ステップ名}`

| Step | ヘッダー | 表示内容 |
|------|---------|---------|
| 0 | `### Step 0: 前提チェック` | FFmpeg のインストール状態、config の読み込み結果 |
| 1 | `### Step 1: 動画ファイル確認` | ファイルパス、長さ、解像度、FPS、ファイルサイズをテーブル表示 |
| 2 | `### Step 2: 抽出設定を選択` | 選択したプリセットとパラメータ |
| 3 | `### Step 3: コスト見積もり` | 推定フレーム数、推定解像度、トークン数、コストをテーブル表示 |
| 4 | `### Step 4: フレーム抽出` | 抽出枚数、合計サイズ、出力ディレクトリ |
| 5 | `### Step 5: フレーム分析` | 各フレームの内容説明と全体の流れ |
| 6 | `### Step 6: レポート生成` | 構造化された分析結果 |
| 7 | `### Step 7: クリーンアップ案内` | 手動削除コマンドと自動削除の案内 |

**重要:** ステップを省略したり、ヘッダーなしで実行したりしないこと。

## Workflow

### 0. 前提チェック

1. FFmpeg がインストールされているか確認:
   ```bash
   which ffmpeg
   ```
   見つからない場合、以下を表示して**終了**する:
   > FFmpeg がインストールされていません。以下のコマンドでインストールしてください:
   > ```bash
   > brew install ffmpeg
   > ```

2. config.json を読み込む:
   ```
   Read ~/.claude/skills/analyze-video/config.json
   ```
   ファイルが存在しない場合はデフォルト値を使用する。

### 1. 動画ファイル確認

1. `$ARGUMENTS` が指定されていればそのパスを使用する
2. 指定がなければ AskUserQuestion で動画ファイルのパスを尋ねる
3. ファイルの存在を確認し、拡張子が `supported_formats` に含まれるか検証する
4. `ffprobe` で動画メタデータを取得する:
   ```bash
   /usr/bin/python3 ~/.claude/skills/analyze-video/references/extract_frames.py --estimate -i "{video_path}" --mode scene -t 0.3 -s 0.3 -q 8
   ```
5. 動画情報をテーブルで表示:

   | 項目 | 値 |
   |------|-----|
   | ファイル | {path} |
   | 長さ | {duration} 秒 |
   | 解像度 | {width}x{height} |
   | FPS | {fps} |
   | ファイルサイズ | {size} MB |

### 2. 抽出設定を選択

AskUserQuestion で抽出モードを選択させる:

- **クイック概要**: 最少フレーム・最低コスト（scene 閾値 0.4、スケール 0.25、品質 10）
- **標準分析**: バランス重視（scene 閾値 0.3、スケール 0.3、品質 8）
- **詳細分析**: より多いフレーム・高品質（scene 閾値 0.2、スケール 0.4、品質 5）
- **時間ベース**: N秒間隔で抽出（ユーザーに間隔を追加で尋ねる）

フィルタモードは config の `defaults.filter_mode` を使用する。ユーザーが明示的に `similarity` モードを希望する場合はそちらを使用する。

### 3. コスト見積もり

Python スクリプトの `--estimate` モードで見積もりを取得:

```bash
/usr/bin/python3 ~/.claude/skills/analyze-video/references/extract_frames.py \
  --estimate \
  -i "{video_path}" \
  --mode {mode} \
  -t {threshold} \
  -s {scale} \
  -q {quality} \
  --model {model}
```

見積もり結果をテーブルで表示:

| 項目 | 値 |
|------|-----|
| 抽出モード | {mode} |
| 推定フレーム数 | {frames} 枚 |
| 推定解像度 | {width}x{height} px |
| 1フレームあたりのトークン | ~{tokens} |
| 合計トークン | ~{total_tokens} |
| 推定コスト (Opus) | ${cost_usd} (~{cost_jpy}円) |

AskUserQuestion で確認:
- **実行する**: 次のステップへ
- **設定を変更**: Step 2 に戻る
- **キャンセル**: 終了

### 4. フレーム抽出

Python スクリプトを抽出モード（`--estimate` なし）で実行:

```bash
/usr/bin/python3 ~/.claude/skills/analyze-video/references/extract_frames.py \
  -i "{video_path}" \
  --mode {mode} \
  -t {threshold} \
  -s {scale} \
  -q {quality} \
  -o /tmp/video-frames-{timestamp}
```

- timeout: 300000ms（5分）で実行する
- 出力の JSON をパースし、結果を表示する

**エラーハンドリング:**
- JSON の `status` が `"warning"` の場合（scene 検出で 1 フレームのみ）: `suggestion` フィールドのコマンドを表示し、time モードへの切り替えを AskUserQuestion で提案する
- フレームが 0 枚の場合: 閾値を下げるか、time モードに変更することを提案する
- フレームが `max_frames` を超える場合: 閾値を上げるか、続行するか確認する
- OpenCV 未インストール（similarity モード時）: インストールコマンドを案内し、scene モードへのフォールバックを提案

### 5. フレーム分析

1. Step 4 の JSON 出力から `frames` 配列を取得
2. 各フレームの画像を **Read ツール**で順番に読み込む
3. 各フレームについて:
   - 画面に表示されている内容を詳しく説明する
   - UI要素、テキスト、画面の状態を記述する
4. 全フレームの分析後、以下をまとめる:
   - **全体の概要**: 動画全体で何が起きているかを 2-3 文で要約
   - **画面遷移フロー**: 時系列で画面の遷移を整理
   - **主な発見・ポイント**: 重要な気づきをリスト化

### 6. レポート生成

分析結果を以下の構造で表示する:

```
## 動画分析レポート: {ファイル名}

### 動画情報
- 長さ: {duration}秒
- 解像度: {resolution}
- 抽出フレーム数: {frames}枚
- 分析コスト: ~{cost}

### 全体の概要
{要約}

### フレーム別分析
#### フレーム 1
{説明}
...

### 画面遷移フロー
{フロー}

### 主な発見・ポイント
{ポイント}
```

AskUserQuestion で確認:
- **ファイルに保存**: Markdown ファイルとして保存（動画と同じディレクトリに `{動画名}-analysis.md`）
- **このまま終了**: Step 7 へ

### 7. クリーンアップ案内

コマンドは実行せず、以下のメッセージをユーザーに表示するだけにする:

> 必要に応じて以下の一時ファイルを手動で削除できます:
>
> ```bash
> rm -rf /tmp/video-frames-{timestamp}
> ```
>
> `/tmp` 配下のファイルはシステムの再起動時に自動的に削除されるため、手動で削除しなくても問題ありません。

## Technical Notes

- **FFmpeg scene detection**: `select='gt(scene,T)'` フィルタはフレーム間の画素変化量をスコア化（0.0-1.0）し、閾値を超えるフレームのみ出力する。UIの画面遷移のようなシャープな変化に有効
- **OpenCV similarity**: `cv2.compareHist(HISTCMP_CORREL)` でHSVヒストグラムの相関係数を計算。閾値以下（=大きな変化あり）のフレームを保持。グラデーションやアニメーションの変化により敏感
- **コスト計算**: 画像トークン数はピクセル面積 / 750 で概算（Claude の画像処理基準に基づく）
- **Python 依存**: 標準ライブラリのみ使用（scene/time モード）。similarity モードのみ `opencv-python` が追加で必要
- **`-vsync vfr`**: 可変フレームレート出力。scene detection で選択されたフレームのみ書き出す
- **`-qscale:v`**: JPEG 品質（1=最高品質、31=最低品質）。分析用途では 5-10 で十分
