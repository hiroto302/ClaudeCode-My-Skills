# Mermaid 生成ガイドライン

## 得意な図の種類

1. **シーケンス図** — 最も得意。ライフライン・矢印・ノートが自動配置される
2. **ER図** — エンティティ間のリレーションが明確に表現できる
3. **簡易フローチャート** — 5-10ノード程度の小規模なフロー
4. **状態遷移図** — `stateDiagram-v2` で表現可能

## 苦手な図の種類

- 複雑なアーキテクチャ図（ネスト・自由配置が必要）
- 大規模フローチャート（レイアウトが崩れる）
- インフラ構成図（アイコン・精密な配置が必要）

→ これらは XML を推奨する

## シーケンス図のテンプレート

```
sequenceDiagram
    autonumber
    participant A as 表示名A
    participant B as 表示名B
    participant C as 表示名C

    rect rgb(30, 42, 62)
    Note over A,C: Phase 1: フェーズ名
    A->>B: 同期メッセージ
    B-->>A: 非同期レスポンス
    Note over B: 状態メモ
    end

    rect rgb(46, 30, 30)
    Note over A,C: Phase 2: フェーズ名
    A->>C: メッセージ
    C-->>A: レスポンス
    end
```

## 矢印の種類

| 記法 | 意味 |
|------|------|
| `->>` | 同期メッセージ（実線＋塗り矢印） |
| `-->>` | 非同期レスポンス（破線＋塗り矢印） |
| `->>+` | アクティベーション開始 |
| `->>-` | アクティベーション終了 |
| `--)` | 非同期メッセージ（実線＋開き矢印） |

## フェーズ分けのルール

- `rect rgb(R, G, B)` でフェーズを背景色で囲む
- 色は控えめに（暗い色推奨）
- Phase タイトルは `Note over` で表現する

## ラベルのルール

- 短く簡潔に（20文字以内を目安）
- 関数名はフルシグネチャではなく `funcName()` の形
- JSON を入れない（`{ type: 'init' }` 程度は可）
- 日本語の説明は `Note over` に入れる

## フローチャートのテンプレート

```
graph TD
    A[開始] --> B{条件分岐}
    B -->|Yes| C[処理A]
    B -->|No| D[処理B]
    C --> E[完了]
    D --> E
```

## 状態遷移図のテンプレート

```
stateDiagram-v2
    [*] --> Idle
    Idle --> Loading: init
    Loading --> Ready: loaded
    Ready --> Processing: process
    Processing --> Result: done
    Processing --> Error: fail
    Error --> Idle: retry
    Result --> Idle: reset
```

## アンチパターン

- `style` ディレクティブの多用 → Draw.io変換で無視されることが多い
- 10以上の participant → 横幅が足りなくなる
- ネストした `rect` → サポートが不安定
- サブグラフの多用（`graph` の場合）→ レイアウト崩壊の原因
