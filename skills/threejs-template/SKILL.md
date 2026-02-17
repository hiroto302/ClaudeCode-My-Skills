---
name: threejs-template
description: Create a new Three.js project with Vite, GSAP, lil-gui, and GLSL support using the latest Vite template
disable-model-invocation: true
user-invocable: true
argument-hint: "[project-name]"
allowed-tools: Bash, Write, Read, Edit
---

# Three.js Template Skill

Create a new Three.js project with pre-configured development environment using the latest Vite template.

## Usage
This skill creates a Three.js project by:
1. Using `npm create vite@latest` to get the latest Vite vanilla template
2. Adding Three.js-specific dependencies (three, gsap, lil-gui)
3. Configuring Vite for Three.js development (GLSL support, asset handling)

## Steps to Execute

1. **Determine project name**:
   - If `$ARGUMENTS` is provided, use it as the project name
   - If not provided, use "threejs-project" as the default name

2. **Create Vite project**:
   ```bash
   npm create vite@latest [project-name] -- --template vanilla
   cd [project-name]
   ```

3. **Restructure project for Three.js**:
   - Create `static/` directory and move all static assets:
     ```bash
     mkdir -p static
     mv public/* static/ 2>/dev/null || true
     mv src/*.svg static/ 2>/dev/null || true
     rmdir public 2>/dev/null || true
     ```
   - Move `index.html` from root to `src/` directory:
     ```bash
     mv index.html src/
     ```
   - Fix the script path in `src/index.html`:
     - Change `<script type="module" src="/src/main.js"></script>`
     - To `<script type="module" src="/main.js"></script>`
     - This is necessary because vite.config.js sets `root: 'src/'`
   - Fix import paths in `src/main.js` to use absolute paths:
     - Change `import './style.css'` to `import '/style.css'`
     - Change `import javascriptLogo from './javascript.svg'` to `import javascriptLogo from '/javascript.svg'`
     - Change `import { setupCounter } from './counter.js'` to `import { setupCounter } from '/counter.js'`
     - Keep `import viteLogo from '/vite.svg'` as is (already correct)

4. **Install Three.js dependencies**:
   ```bash
   npm install three gsap lil-gui
   npm install -D vite-plugin-glsl vite-plugin-restart
   ```

5. **Create vite.config.js** (overwrite if exists) with the following content:

### vite.config.js (create this file)
```js
import restart from 'vite-plugin-restart'
import glsl from 'vite-plugin-glsl'

export default {
    root: 'src/',
    publicDir: '../static/',
    base: './',
    server:
    {
        host: true, // Open to local network and display URL
        open: true  // Open to browser on server start
    },
    build:
    {
        outDir: '../dist', // Output in the dist/ folder ← Build ファイルの出力先を dist/ フォルダに変更
        emptyOutDir: true, // Empty the folder first before building
        sourcemap: true    // Add sourcemap for easier debugging
    },
    // Three.jsでよく使うアセット形式を追加 (例: 3Dモデル、HDR環境マップなど)
    assetsInclude: ['**/*.gltf', '**/*.glb', '**/*.hdr', '**/*.exr'],
    // Plugins の追加
    plugins:
    [
        restart({ restart: [ '../static/**', ] }), // Restart server on static file change
        glsl() // Handle shader files
    ]
}
```

6. **Display success message** with next steps:
   ```
   ✅ Three.js project created successfully!

   Next steps:
     cd [project-name]
     npm run dev

   Your project includes:
   - Three.js (latest)
   - GSAP for animations
   - lil-gui for debugging
   - GLSL shader support
   - Vite for fast development
   ```

## Notes
- This approach ensures you always get the latest Vite template and latest npm packages
- The vite.config.js adds Three.js-specific optimizations:
  - GLSL shader file support
  - Auto-restart on static file changes
  - Support for 3D assets (GLTF, GLB, HDR, EXR)
- All other files (HTML, CSS, JS) come from Vite's vanilla template
- You can manually update src/main.js later to include Three.js scene setup
