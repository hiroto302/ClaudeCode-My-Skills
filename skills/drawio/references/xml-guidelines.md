# XML 生成ガイドライン

## 基本構造

```xml
<mxfile>
  <diagram name="図のタイトル" id="unique-id">
    <mxGraphModel dx="1200" dy="800" grid="1" gridSize="10" guides="1" tooltips="1" connect="1" arrows="1" fold="1" page="1" pageScale="1" pageWidth="1400" pageHeight="900" math="0" shadow="0">
      <root>
        <mxCell id="0"/>
        <mxCell id="1" parent="0"/>
        <!-- ノードとエッジをここに記述 -->
      </root>
    </mxGraphModel>
  </diagram>
</mxfile>
```

## ダークテーマのカラーパレット

背景・コンテナ:
- メイン背景: `fillColor=#1a1a2e;strokeColor=#30305a`
- コンテナ: `fillColor=#16213e;strokeColor=#4A90D9`（青系）
- サブコンテナ: `dashed=1` を追加して破線枠にする

ノードのカテゴリカラー（最大5色を推奨）:
| カテゴリ | fillColor | strokeColor | fontColor |
|----------|-----------|-------------|-----------|
| Core/Primary | #4A90D9 | #2C5F8A | #FFFFFF |
| Worker/Process | #E8833A | #B5622A | #FFFFFF |
| UI/Frontend | #2a5a3f | #50C878 | #FFFFFF |
| Utility/Helper | #4a3e1e | #FFD700 | #FFFFFF |
| External/AI | #5a1e1e | #FF6B6B | #FFB0B0 |
| Backend/Infra | #4a2e5a | #DDA0DD | #E0E0E0 |

テキスト・ラベル:
- メインテキスト: `fontColor=#E0E0E0`
- サブテキスト: `fontColor=#8899AA`
- 凡例テキスト: `fontColor=#AAAAAA`

## ノードのスタイル規則

- 角丸: `rounded=1;arcSize=10〜15`
- シャドウ: `shadow=1`（主要ノードのみ）
- フォントサイズ: タイトル 20px、ノード 11-13px、ラベル 9-10px
- ノードの最小サイズ: 幅 140px、高さ 45px

## エッジ（矢印）のスタイル規則

- ルーティング: `edgeStyle=orthogonalEdgeStyle;rounded=1`（直角＋角丸）
- 同期呼び出し: `endArrow=block;endFill=1;strokeWidth=1.5`
- 非同期レスポンス: `endArrow=open;endFill=0;dashed=1;dashPattern=6 3`
- ラベル: `edgeLabel` を使用、矢印の上にオフセット配置

## レイアウト規則

- ノード間の最小間隔: 水平 40px、垂直 30px
- コンテナの内側パディング: 20px 以上
- ラベルが矢印や他のノードと重ならないように配置する
- 長いラベルは省略するか改行（`&#xa;`）を使う
- **ラベルは短く**: 関数名のフルシグネチャではなく、要点のみ記載

## 凡例（Legend）

- 図の右上または左下に配置
- 小さい色付きの四角（14x14px）＋ テキストラベル
- 背景ボックスで囲む

## アンチパターン（避けるべきこと）

- 7色以上の使用 → 視認性が下がる
- 長いJSON/コードをラベルに入れる → 読めなくなる
- ノートやラベルを矢印の上に重ねる → 方向が分からなくなる
- ノードが少なすぎる簡素な図 → 各モジュールの内部（関数・イベント・状態）まで描くことで情報量を確保する。キャンバスサイズを広げて対応する
