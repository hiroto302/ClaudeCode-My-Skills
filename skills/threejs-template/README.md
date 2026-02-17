# Three.js Template Skill

A Claude Code skill that creates a new Three.js project with Vite, GSAP, lil-gui, and GLSL support.

## 概要

このskillは、Three.js開発に最適化されたプロジェクトテンプレートを素早く生成します。`npm create vite@latest`を使用して最新のViteテンプレートをベースに、Three.js開発に必要な依存関係と設定を自動的に追加します。

## 特徴

- ✨ 最新のViteテンプレートを使用（常に最新バージョン）
- 🎨 Three.js、GSAP、lil-guiが事前インストール
- 🎬 GLSLシェーダーサポート（vite-plugin-glsl）
- 🔄 静的ファイル変更時の自動リロード
- 📦 3Dアセット対応（GLTF、GLB、HDR、EXR）
- ⚡ Viteによる高速な開発体験

## インストール

1. このskillを`~/.claude/skills/`ディレクトリに配置:

```bash
cd ~/.claude/skills/
git clone <this-repo-url> threejs-template
# または
mkdir -p ~/.claude/skills/threejs-template
# SKILL.mdをコピー
```

2. Claude Codeを再起動してskillを読み込み

## 使い方

Claude Codeセッション内で以下のコマンドを実行:

```
/threejs-template my-project-name
```

プロジェクト名を省略した場合、デフォルトで`threejs-project`という名前になります。

## 生成されるプロジェクト構造

```
my-project-name/
├── node_modules/
├── src/
│   ├── index.html
│   ├── main.js
│   ├── style.css
│   └── counter.js
├── static/
│   ├── vite.svg
│   └── javascript.svg
├── .gitignore
├── package.json
├── package-lock.json
└── vite.config.js
```

## インストールされる依存関係

### Dependencies
- `three` - Three.js 3Dライブラリ
- `gsap` - アニメーションライブラリ
- `lil-gui` - デバッグUI

### Dev Dependencies
- `vite` - ビルドツール
- `vite-plugin-glsl` - GLSLシェーダーサポート
- `vite-plugin-restart` - 静的ファイル変更時の自動リロード

## vite.config.js の特徴

- `root: 'src/'` - src/をルートディレクトリとして設定
- `publicDir: '../static/'` - 静的アセット用ディレクトリ
- GLSLシェーダーファイルのサポート
- 3Dモデルフォーマット（GLTF、GLB、HDR、EXR）の対応
- ソースマップ生成

## 開発サーバーの起動

生成されたプロジェクトで:

```bash
cd my-project-name
npm run dev
```

## ビルド

```bash
npm run build
```

ビルド結果は`dist/`ディレクトリに出力されます。

## 要件

- Node.js (v18以上推奨)
- npm または yarn
- Claude Code CLI

## カスタマイズ

SKILL.mdを編集することで、以下をカスタマイズできます:
- インストールするパッケージのバージョン
- vite.config.jsの設定
- 生成されるファイルの内容

## トラブルシューティング

### skillが認識されない

Claude Codeセッションを再起動してください:
```bash
exit
claude
```

### パーミッションエラー

SKILL.mdの`allowed-tools`に必要なツールが含まれているか確認してください:
```yaml
allowed-tools: Bash, Write, Read, Edit
```

## ライセンス

MIT

## 作者

[H.T.]

## 関連リンク

- [Three.js Documentation](https://threejs.org/docs/)
- [Vite Documentation](https://vitejs.dev/)
- [Claude Code Documentation](https://code.claude.com/)
