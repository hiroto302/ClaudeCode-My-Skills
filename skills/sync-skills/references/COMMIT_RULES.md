# コミットメッセージルール

sync-skills が生成するコミットメッセージのフォーマット定義。

## フォーマット

```
{type}: {対象} - {変更内容の要約}
```

## Type 一覧

| Type | 用途 | 例 |
|------|------|-----|
| `feat` | 新規スキル追加 | `feat: add sync-skills skill - スキル同期とGitコミットの自動化` |
| `update` | 既存スキル更新 | `update: session-summary - スタイル選択機能を追加` |
| `remove` | スキル削除 | `remove: old-skill skill` |
| `fix` | スキルのバグ修正 | `fix: threejs-template - テンプレートのパス修正` |

## ルール

1. **1行目は72文字以内** に収める
2. **対象はスキル名** を明記する（例: `session-summary`, `sync-skills`）
3. **要約は変更の「意味」** を伝える（何を変えたかではなく、なぜ・何が改善されたか）
4. **言語は英語ベース、要約部分は日本語OK**（type とスキル名は英語）
5. 複数スキルの変更がある場合、最も重要な変更を1行目にし、残りは本文に書く

## 複数スキル変更時

```
feat: add sync-skills skill - スキル同期の自動化

- update: session-summary - テンプレート構造を改善
- fix: threejs-template - デフォルト設定を修正
```

## 単一スキル内の複数変更

```
update: session-summary - スタイル選択機能を追加し、出力形式を3種類から選べるように拡張
```

要約が長くなる場合は1行目を短くし、本文で補足する:

```
update: session-summary - スタイル選択機能を追加

- 構造化テンプレート/要点まとめ/カスタムの3形式を追加
- デフォルトは構造化テンプレート
- references/にスタイル別テンプレートを追加
```
