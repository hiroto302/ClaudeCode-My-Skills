# CSV 生成ガイドライン

## 得意な図の種類

1. **組織図** — 階層的なデータを素早く可視化
2. **ツリー構造** — ファイルツリー、カテゴリ分類
3. **フローチャート** — 線形または分岐のあるフロー

## 苦手な図の種類

- シーケンス図（ライフラインの表現不可）
- 複雑なアーキテクチャ図（自由配置不可）
- 双方向の矢印が多い図

→ これらは XML または Mermaid を推奨する

## 基本構造

```
# label: %name%
# stylename: type
# styles: {"style1": "...", "style2": "..."}
# connect: {"from": "refs", "to": "id", "invert": false, "style": "..."}
# width: 200
# height: 40
# padding: 20
# ignore: id,refs,type
# nodespacing: 20
# levelspacing: 40
# edgespacing: 20
# layout: verticalflow
id,name,type,refs
```

## 重要な注意事項

### 行継続（`\`）は使用禁止

draw.io の CSV パーサーは行継続をサポートしない。`# styles` などの長いヘッダーディレクティブは**必ず1行で記述**する。

悪い例:
```
# styles: {"a": "...", \
#   "b": "..."}
```

良い例:
```
# styles: {"a": "...", "b": "..."}
```

### スタイル定義

`# styles` で型ごとのスタイルを JSON で定義する。キーは `# stylename` で指定したカラム値に対応する。

### 接続の定義

`# connect` で接続ルールを定義する:
- `from`: 接続元を指定する CSV カラム名
- `to`: 接続先のIDカラム名（通常 `id`）
- `invert`: true で矢印の方向を反転
- `style`: エッジのスタイル

複数の接続タイプが必要な場合、`# connect` を複数行書く:
```
# connect: {"from": "next", "to": "id", "style": "実線スタイル"}
# connect: {"from": "alt", "to": "id", "style": "破線スタイル"}
```

## ダークテーマのカラーパレット

XML ガイドラインと同じカラーパレットを使用する。`# styles` 内で fillColor/strokeColor/fontColor を指定する。

## レイアウトの種類

- `verticalflow` — 上から下へ（最も汎用的）
- `horizontalflow` — 左から右へ
- `verticalTree` — ツリー構造（縦）
- `horizontalTree` — ツリー構造（横）
- `organic` — 自動配置（ノード数が多い場合）

## データ行のルール

- ID はユニークな文字列（例: `s1`, `s2`, `p1`）
- 接続先は ID を指定（複数指定はカンマ区切り）
- テキスト内の改行は `\n` ではなくスペースで代替する
- ダブルクォートでフィールドを囲む（カンマを含む場合は必須）

## アンチパターン

- `\` による行継続 → パース失敗の原因
- 1つの connect で複雑なルーティング → シンプルな接続に分ける
- 20行以上のデータ → レイアウトが崩れ始める。分割を検討
