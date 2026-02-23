---
name: video-ref
description: 動画ファイルからキーフレームを抽出し、ユーザーの目的（UI再現、アニメーション再現、エラー修正、UIフロー把握）に応じた分析を行う。「/video_ref」「動画の意図を分析して」「この動画を再現したい」「この動画のエラーを直して」と言った時にトリガーする。
disable-model-invocation: true
user-invocable: true
argument-hint: "[動画ファイルパス]"
allowed-tools: Bash, Read, Write, AskUserQuestion
---

# video-ref

動画ファイルからキーフレームを抽出し、ユーザーの目的に応じた分析を行うスキル。
動画を「参照素材」として Claude Code に渡し、UI実装・アニメーション再現・エラー修正・UIフロー把握を支援する。

**セッション間フレーム保持**: 抽出したフレーム画像はプロジェクト内の `.video-ref/` ディレクトリに永続保存される。
次回のセッションで同じ動画を参照する際、フレーム画像を直接 Read して視覚的なコンテキストを復元できる。
テキスト記述よりも画像の方が意図を正確に伝えられるため、実装の精度が向上する。

## Trigger

ユーザーが `/video_ref` と入力した時、または「動画の意図を分析して」「この動画を再現したい」「この動画のエラーを直して」と言った時にこのスキルを実行する。

## Configuration

`~/.claude/skills/video-ref/config.json` で設定をカスタマイズできる。

| キー | デフォルト | 説明 |
|------|-----------|------|
| `defaults.preset` | `standard` | デフォルトのプリセット |
| `defaults.filter_mode` | `scene` | デフォルトのフィルタモード |
| `defaults.time_interval` | `5` | time モードの間隔（秒） |
| `max_frames` | `100` | 安全制限（超過時は警告） |

## 進捗表示ルール

各ステップの実行時に、**必ず**以下の形式でヘッダーと結果サマリーをユーザーに表示すること。

**ヘッダー形式:** `### Step {番号}: {ステップ名}`

| Step | ヘッダー | 表示内容 |
|------|---------|---------|
| 0 | `### Step 0: 前提チェック` | FFmpeg のインストール状態、config の読み込み結果 |
| 1 | `### Step 1: 動画ファイル選択` | ファイルパス、長さ、解像度、FPS、ファイルサイズをテーブル表示 |
| 2 | `### Step 2: 分析目的の選択` | 選択した目的カテゴリ |
| 3 | `### Step 3: フレーム分割方法の選択` | 選択した分割モードとパラメータ |
| 4 | `### Step 4: コスト見積もり` | 推定フレーム数、推定解像度、トークン数、コストをテーブル表示 |
| 5 | `### Step 5: フレーム抽出` | 抽出枚数、合計サイズ、出力ディレクトリ |
| 6 | `### Step 6: 目的別フレーム分析` | 各フレームの目的に特化した分析結果 |
| 7 | `### Step 7: 分析結果と次のアクション` | 構造化された分析結果 + 次のアクション選択 |
| 8 | `### Step 8: 保存状況の案内` | フレーム永続保存先と次回セッションでの使い方 |

**重要:** ステップを省略したり、ヘッダーなしで実行したりしないこと。

## フレーム永続化の仕組み

抽出したフレーム画像は以下の構造でプロジェクトディレクトリに保存される:

```
{project}/
  .video-ref/
    {動画名}/
      manifest.json       ← メタデータ + 分析設定 + フレーム一覧
      frames/
        frame_0001.jpg
        frame_0002.jpg
        ...
```

**manifest.json** には以下が含まれる:
- 元動画のパス・メタデータ（duration, resolution, fps）
- 分析設定（目的カテゴリ、分割モード、プリセット）
- フレーム一覧（ファイル名 + 推定タイムスタンプ）
- 作成日時

次のセッションでは:
1. `.video-ref/` の存在を検出
2. manifest.json を読み込み
3. フレーム画像を **Read ツール**で直接読み込む → 視覚コンテキストが復元される
4. テキストではなく**画像そのもの**で意図を伝えられる

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
   Read ~/.claude/skills/video-ref/config.json
   ```
   ファイルが存在しない場合はデフォルト値を使用する。

3. **既存のフレーム参照を検出**:
   プロジェクトディレクトリ内に `.video-ref/` ディレクトリが存在するか確認する。
   ```bash
   ls .video-ref/
   ```
   既存の参照が見つかった場合、AskUserQuestion で選択させる:
   - **{動画名} の参照を再利用**: manifest.json を読み込み、保存済みフレーム画像を Read して Step 6 へスキップ
   - **新しい動画を分析**: 通常の Step 1 から開始

   再利用を選択した場合:
   1. `manifest.json` を Read して分析設定を復元
   2. `frames/` ディレクトリ内の各フレーム画像を Read ツールで読み込む
   3. 画像を見た上で、ユーザーの新しい依頼に対応する（実装、修正、追加分析など）

### 1. 動画ファイル選択

1. `$ARGUMENTS` が指定されていればそのパスを使用する
2. 指定がなければ AskUserQuestion で動画ファイルのパスを尋ねる
3. ファイルの存在を確認し、拡張子が `supported_formats` に含まれるか検証する
4. `ffprobe` で動画メタデータを取得する:
   ```bash
   /usr/bin/python3 ~/.claude/skills/video-ref/references/extract_frames.py --estimate -i "{video_path}" --mode scene -t 0.3 -s 0.3 -q 8
   ```
5. 動画情報をテーブルで表示:

   | 項目 | 値 |
   |------|-----|
   | ファイル | {path} |
   | 長さ | {duration} 秒 |
   | 解像度 | {width}x{height} |
   | FPS | {fps} |
   | ファイルサイズ | {size} MB |

### 2. 分析目的の選択

AskUserQuestion でこの動画の分析目的を選択させる:

- **UIの再現・実装**: 「この動画のようなUIを作りたい」— レイアウト、コンポーネント構造、色、タイポグラフィを分析
- **アニメーション・トランジション**: 「この動きを再現したい」— CSS transition/animation、timing、easing、トリガーを分析
- **エラー・バグの修正**: 「この動画のエラーを直したい」— エラーメッセージ、異常な挙動、正常との差分を分析
- **UIフロー・操作手順**: 「この操作フローを実装したい」— 画面遷移、ユーザーアクション、状態変化、ルーティングを分析

※ "Other" 選択時は、ユーザーに自由記述で目的を入力してもらう。

選択した目的カテゴリのキーを以降のステップで使用する（config.json の `intent_categories` を参照）。

### 3. フレーム分割方法の選択

Step 2 で選択した目的カテゴリに基づいて、推奨の分割方法に `(推奨)` ラベルを付与する。

config.json の `intent_categories.{selected}.recommended_mode` を参照して推奨を決定する:
- `ui_reproduction` → シーンベースに `(推奨)` を付与
- `animation` → 高密度に `(推奨)` を付与
- `error_fix` → シーンベースに `(推奨)` を付与
- `ui_flow` → 時間ベースに `(推奨)` を付与

AskUserQuestion でフレーム分割方法を選択させる:

- **シーンベース**: 画面の大きな変化を自動検出して分割。UI実装やエラー確認に最適
- **時間ベース**: N秒間隔で均等に分割。UIフローや操作手順の把握に最適（ユーザーに間隔を追加で尋ねる）
- **高密度（0.5秒間隔）**: 短い間隔で大量のフレームを取得。アニメーションやマイクロインタラクションの分析に最適
- **類似度ベース（要OpenCV）**: フレーム間の類似度で分割。微細な変化の検出に最適

分割方法に応じたプリセットは config.json の `intent_categories.{selected}.recommended_preset` を使用する。
ユーザーが品質を変更したい場合は、追加で quick/standard/detailed/high_density から選択させる。

### 4. コスト見積もり

Python スクリプトの `--estimate` モードで見積もりを取得:

```bash
/usr/bin/python3 ~/.claude/skills/video-ref/references/extract_frames.py \
  --estimate \
  -i "{video_path}" \
  --mode {mode} \
  -t {threshold} \
  -s {scale} \
  -q {quality} \
  --model {model}
```

time モードの場合は `--interval {interval}` を追加する。

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
- **設定を変更**: Step 3 に戻る
- **キャンセル**: 終了

### 5. フレーム抽出（永続保存）

フレームの出力先は `/tmp/` ではなく、プロジェクトディレクトリ内の `.video-ref/` に保存する。
これにより、次回のセッションでもフレーム画像を Read して視覚コンテキストを復元できる。

1. 動画名からディレクトリ名を生成（拡張子を除去、スペースをハイフンに置換）
2. 出力ディレクトリを作成:
   ```bash
   mkdir -p .video-ref/{video_name}/frames
   ```

3. Python スクリプトを抽出モード（`--estimate` なし）で実行:
   ```bash
   /usr/bin/python3 ~/.claude/skills/video-ref/references/extract_frames.py \
     -i "{video_path}" \
     --mode {mode} \
     -t {threshold} \
     -s {scale} \
     -q {quality} \
     -o .video-ref/{video_name}/frames
   ```
   time モードの場合は `--interval {interval}` を追加する。

4. **manifest.json を作成**: 抽出結果のメタデータをフレームと一緒に保存する:
   ```json
   {
     "video": {
       "original_path": "{video_path の絶対パス}",
       "duration_seconds": {duration},
       "resolution": "{width}x{height}",
       "fps": {fps},
       "file_size_mb": {size}
     },
     "analysis": {
       "intent": "{選択した目的カテゴリのキー}",
       "intent_label": "{目的カテゴリのラベル}",
       "mode": "{抽出モード}",
       "interval": {interval or null},
       "preset": "{プリセット名}",
       "threshold": {threshold},
       "scale": {scale},
       "quality": {quality},
       "created_at": "{ISO 8601 形式の日時}"
     },
     "frames": [
       {"filename": "frame_0001.jpg", "estimated_timestamp_s": 0.0},
       {"filename": "frame_0002.jpg", "estimated_timestamp_s": 0.5},
       ...
     ]
   }
   ```
   このファイルを `.video-ref/{video_name}/manifest.json` に Write ツールで保存する。

- timeout: 300000ms（5分）で実行する
- 出力の JSON をパースし、結果を表示する

**エラーハンドリング:**
- JSON の `status` が `"warning"` の場合（scene 検出で 1 フレームのみ）: `suggestion` フィールドのコマンドを表示し、time モードへの切り替えを AskUserQuestion で提案する
- フレームが 0 枚の場合: 閾値を下げるか、time モードに変更することを提案する
- フレームが `max_frames` を超える場合: 閾値を上げるか、続行するか確認する
- OpenCV 未インストール（similarity モード時）: インストールコマンドを案内し、scene モードへのフォールバックを提案

### 6. 目的別フレーム分析

1. Step 5 の JSON 出力から `frames` 配列を取得
2. `~/.claude/skills/video-ref/references/intent-prompts.md` から、Step 2 で選択した目的カテゴリのプロンプトテンプレートを参照する
3. 各フレームの画像を **Read ツール**で順番に読み込む
4. 各フレームについて、目的カテゴリに特化した観点で分析する:

   **UIの再現の場合:**
   - レイアウト構造（グリッド、カラム数、領域配分）
   - UIコンポーネント（ボタン、カード、ナビ等）と状態
   - ビジュアルデザイン（色・HEX値、フォントサイズ、余白）
   - 前フレームからの変化点
   - 実装に必要な CSS 手法・ライブラリ

   **アニメーション・トランジションの場合:**
   - アニメーション対象の要素と現在の状態
   - 前フレームからの変化量（位置、サイズ、透明度、色）
   - 遷移の詳細（種類、duration(ms)、easing、方向）
   - トリガーの推定（hover, click, scroll, load）
   - 実装に必要な CSS/JS プロパティと推奨ライブラリ

   **エラー・バグ修正の場合:**
   - 画面の状態と正常部分
   - エラーメッセージや異常の検出
   - エラー発生タイミングと前フレームとの差分
   - 推定原因（フロント/バック/ネットワーク/状態管理）
   - 修正方針の提案

   **UIフロー・操作手順の場合:**
   - 画面の識別（名前、推定URLパス）
   - 構成要素とインタラクティブ要素
   - 前フレームからの遷移（トリガー、遷移種類）
   - ユーザーアクションの推定
   - ルーティング構造と共通コンポーネントの特定

5. 全フレームの分析後、以下をまとめる:
   - **概要**: 動画全体で何が起きているかを目的の観点で 2-3 文で要約
   - **変化のタイムライン**: 時系列での状態変化を整理
   - **実装指示**: そのまま Claude Code に渡せる具体的な指示テキスト

### 7. 分析結果と次のアクション

分析結果を以下の構造でチャットに表示する:

```
## 動画参照分析: {ファイル名}

### 分析情報
- 動画: {path} ({duration}秒, {resolution})
- 目的: {選択した目的カテゴリのラベル}
- 抽出フレーム: {frames}枚
- 推定コスト: ~{cost}

### 概要
{目的に応じた要約}

### フレーム別分析
#### フレーム 1
{目的特化の分析内容}
...

### 変化のタイムライン
{時系列での状態変化}

### 実装指示
{目的に応じた具体的な実装指示テキスト}
```

AskUserQuestion で次のアクションを選択:
- **この内容で実装を開始する**: 上記の「実装指示」セクションをそのまま指示として使い、実装作業に入る
- **レポートも保存する**: 分析結果を `.video-ref/{動画名}/analysis.md` として Markdown ファイルに追加保存する（フレーム画像は Step 5 で既に永続保存済み）
- **終了**: Step 8 へ

「実装を開始する」を選択した場合は、分析結果の「実装指示」セクションに基づいて実装作業を開始する。

### 8. 保存状況の案内

フレーム画像は既にプロジェクト内に永続保存されているため、以下を案内する:

> フレーム画像は以下に保存されています:
>
> ```
> .video-ref/{動画名}/
>   manifest.json    ← メタデータ（次回読み込み用）
>   frames/          ← フレーム画像
> ```
>
> **次回のセッションでの使い方:**
> - `/video_ref` を実行すると、保存済みフレームの再利用を提案します
> - または「前回の動画参照を見て」と伝えれば、フレーム画像を直接読み込みます
> - フレーム画像を Read することで、テキストよりも正確に視覚的な意図を伝えられます
>
> **削除する場合:**
> ```bash
> rm -rf .video-ref/{動画名}
> ```

## Technical Notes

- **FFmpeg scene detection**: `select='gt(scene,T)'` フィルタはフレーム間の画素変化量をスコア化（0.0-1.0）し、閾値を超えるフレームのみ出力する。UIの画面遷移のようなシャープな変化に有効
- **OpenCV similarity**: `cv2.compareHist(HISTCMP_CORREL)` でHSVヒストグラムの相関係数を計算。閾値以下（=大きな変化あり）のフレームを保持。グラデーションやアニメーションの変化により敏感
- **コスト計算**: 画像トークン数はピクセル面積 / 750 で概算（Claude の画像処理基準に基づく）
- **Python 依存**: 標準ライブラリのみ使用（scene/time モード）。similarity モードのみ `opencv-python` が追加で必要
- **`-vsync vfr`**: 可変フレームレート出力。scene detection で選択されたフレームのみ書き出す
- **`-qscale:v`**: JPEG 品質（1=最高品質、31=最低品質）。分析用途では 5-10 で十分
- **目的別プロンプト**: `references/intent-prompts.md` にカテゴリ別の分析プロンプトテンプレートを定義。分析の焦点をカテゴリに応じて切り替える
