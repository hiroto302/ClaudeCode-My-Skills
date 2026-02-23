---
name: discuss
description: "一つの議題に対して、複数のエージェント（実践派・革新派・批評家・まとめ役）がそれぞれ異なる視点から分析するディスカッションチーム。「/discuss」「議論して」「discuss」と言った時にトリガーする。"
---

# Discussion Agent Team

一つの議題に対して、4人のエージェント（Pragmatist/Innovator/Critic/Synthesizer）がそれぞれ異なる視点から分析し、比較表と総合推薦を含むレポートを生成する。

## ワークフロー

### 1. トピックを確認する

スキルの引数としてトピックが渡された場合はそれを使う。引数がない場合は、AskUserQuestionツールで議論したいトピックを聞く。

### 2. モデルを選択してもらう

AskUserQuestionツールで使用モデルをユーザーに選択してもらう。

選択肢:
1. **Sonnet（推奨）** — 高速でコスト効率が良い。ほとんどの議題に十分な品質
2. **Opus** — 最高品質。複雑な技術的議題や深い分析が必要な場合に
3. **Haiku** — 最速・最安。簡単な議題やクイックな意見出しに

選択されたモデルは、後のエージェント起動時に `model` パラメータとして使用する。

### 3. チームを作成する

TeamCreateツールを使い、チームを作成する。

```
team_name: "discussion"
description: "ディスカッションチーム: {トピック}"
```

### 4. タスクを作成する

TaskCreateツールで以下の4つのタスクを作成する:

**タスク1: Pragmatist分析**
- subject: "Pragmatist: 実践的な視点で分析"
- description: "議題「{トピック}」について、実践派の視点で分析してください。実装コスト、学習曲線、コミュニティ支持、実績を重視して、今すぐ使える信頼性の高い方法を提案してください。分析結果はSendMessageツールでteam-leadに送信してください。"
- activeForm: "Pragmatistが分析中"

**タスク2: Innovator分析**
- subject: "Innovator: 革新的な視点で分析"
- description: "議題「{トピック}」について、革新派の視点で分析してください。将来性、スケーラビリティ、技術的優位性を重視して、最先端の技術でエレガントな解決策を提案してください。分析結果はSendMessageツールでteam-leadに送信してください。"
- activeForm: "Innovatorが分析中"

**タスク3: Critic分析**
- subject: "Critic: 批評的な視点で分析"
- description: "議題「{トピック}」について、批評家の視点で分析してください。セキュリティ、パフォーマンス、保守性、隠れたコストを重視して、問題点やリスクを指摘してください。分析結果はSendMessageツールでteam-leadに送信してください。"
- activeForm: "Criticが分析中"

**タスク4: Synthesizer統合** （タスク1〜3にblockedByを設定）
- subject: "Synthesizer: 全視点を統合してレポート作成"
- description: "Pragmatist、Innovator、Criticの3つの分析結果を統合し、比較表と総合推薦を含む最終レポートを作成してください。output-template.mdのフォーマットに従ってください。最終レポートはSendMessageツールでteam-leadに送信してください。"
- activeForm: "Synthesizerが統合レポートを作成中"

TaskUpdateを使ってタスク4にaddBlockedByでタスク1〜3のIDを設定する。

### 5. エージェントを起動する

Taskツールで3つのエージェント（pragmatist, innovator, critic）を**並行**に起動する。各エージェントの起動パラメータ:

- `subagent_type`: 各エージェントの定義ファイルに対応するagent名（`pragmatist`, `innovator`, `critic`）
- `team_name`: "discussion"
- `name`: エージェント名（例: "pragmatist"）
- `model`: ステップ2で選択されたモデル
- `prompt`: "あなたは議題「{トピック}」について分析するディスカッションチームのメンバーです。あなたの役割に従って分析し、結果をSendMessageツールでteam-leadに送信してください。TaskListでタスクを確認し、自分のタスクをin_progressに更新してから作業を開始し、完了したらcompletedに更新してください。"

3つのエージェントからメッセージ（分析結果）を受け取ったら、次のステップに進む。

### 6. Synthesizerを起動する

3つの分析結果が揃ったら、Taskツールで synthesizer エージェントを起動する。

- `subagent_type`: `synthesizer`
- `team_name`: "discussion"
- `name`: "synthesizer"
- `model`: ステップ2で選択されたモデル
- `prompt`: 以下の内容を含める:
  - 議題: {トピック}
  - Pragmatistの分析結果: {受信した分析}
  - Innovatorの分析結果: {受信した分析}
  - Criticの分析結果: {受信した分析}
  - "これらの分析を統合し、[output-template.md](references/output-template.md)のフォーマットに従って最終レポートを作成してください。結果はSendMessageツールでteam-leadに送信してください。TaskListでタスクを確認し、自分のタスクをin_progressに更新してから作業を開始し、完了したらcompletedに更新してください。"

### 7. レポートを出力する

Synthesizerからの最終レポートを受け取ったら:

1. チャット上にレポート全文をマークダウンとして表示する
2. AskUserQuestionツールで次のアクションを聞く:
   - **ファイルに保存する** — レポートをMarkdownファイルとして保存する
   - **このまま終了** — チャット表示のみで終了する

「ファイルに保存する」が選ばれた場合:
- ファイル名: `discussion-{YYYY-MM-DD}-{トピックの短い要約}.md`
- 保存先: 現在の作業ディレクトリ
- 保存後、ファイルパスをユーザーに伝える

### 8. クリーンアップ

1. 全エージェントにSendMessageツール（type: "shutdown_request"）を送信する
2. shutdown_responseを待つ
3. TeamDeleteツールでチームを削除する
4. 完了メッセージを表示する

## 注意事項

- エージェントの分析は日本語で行う（技術用語は英語のまま）
- WebSearchを使う場合は最新の情報を優先する
- 各エージェントの分析は独立して行い、お互いの結果を参照しない（Synthesizer以外）
- エラーが発生した場合は、エラー内容をユーザーに伝えてスキップするか再試行するか確認する
