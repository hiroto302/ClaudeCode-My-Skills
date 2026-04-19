---
name: threejs-template
description: Create a new Three.js project with Vite, GSAP, lil-gui, and GLSL support using the latest Vite template
disable-model-invocation: true
user-invocable: true
argument-hint: "[project-name]"
allowed-tools: Bash, Write, Read, Edit
---

# Three.js Template Skill

Create a new Three.js project using the latest Vite vanilla template as a base, then restructure and configure for Three.js development.

## Steps to Execute

### 1. Determine project name
- If `$ARGUMENTS` is provided, use it as the project name
- If not provided, use "threejs-project" as the default name

### 2. Check if directory already exists
```bash
[ -d "[project-name]" ] && echo "ERROR: Directory [project-name] already exists" && exit 1
```
- If the directory exists, **stop and inform the user**. Do not overwrite.

### 3. Create Vite project
```bash
npm create vite@latest [project-name] -- --template vanilla
```

### 4. Install base dependencies
```bash
cd [project-name]
npm install
```

### 5. Restructure project
Run the following commands in order:
```bash
# Create static/ and move public/ contents into it
mkdir -p static
mv public/* static/ 2>/dev/null || true
rmdir public 2>/dev/null || true

# Move index.html to src/
mv index.html src/ 2>/dev/null || true

# Remove unnecessary files (Vite demo assets)
rm -rf src/assets 2>/dev/null || true
rm -f src/counter.js 2>/dev/null || true

# Remove unnecessary static files (Vite demo icons)
rm -f static/favicon.svg static/icons.svg 2>/dev/null || true
```

### 6. Overwrite src/index.html
Write the following content (replace whatever Vite generated):
```html
<!doctype html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>[project-name]</title>
  </head>
  <body>
    <canvas class="webgl"></canvas>
    <script type="module" src="/main.js"></script>
  </body>
</html>
```
- Note: `src="/main.js"` (not `/src/main.js`) because `root: 'src/'` in vite.config.js

### 7. Overwrite src/style.css
Write the following content (replace Vite's demo CSS):
```css
*
{
    margin: 0;
    padding: 0;
}

html,
body
{
    overflow: hidden;
}

.webgl
{
    position: fixed;
    top: 0;
    left: 0;
    outline: none;
}
```

### 8. Overwrite src/main.js
Write the following content (replace Vite's demo JS):
```js
import './style.css'
import * as THREE from 'three'
import gsap from 'gsap'
import GUI from 'lil-gui'

/**
 * Debug
 */
const gui = new GUI()

/**
 * Scene
 */
const scene = new THREE.Scene()

/**
 * Object
 */
const geometry = new THREE.BoxGeometry(1, 1, 1)
const material = new THREE.MeshBasicMaterial({ color: 0xff0000 })
const mesh = new THREE.Mesh(geometry, material)
scene.add(mesh)

/**
 * Sizes
 */
const sizes = {
    width: window.innerWidth,
    height: window.innerHeight
}

window.addEventListener('resize', () =>
{
    sizes.width = window.innerWidth
    sizes.height = window.innerHeight

    camera.aspect = sizes.width / sizes.height
    camera.updateProjectionMatrix()

    renderer.setSize(sizes.width, sizes.height)
    renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2))
})

/**
 * Camera
 */
const camera = new THREE.PerspectiveCamera(75, sizes.width / sizes.height, 0.1, 100)
camera.position.z = 3
scene.add(camera)

/**
 * Renderer
 */
const canvas = document.querySelector('canvas.webgl')
const renderer = new THREE.WebGLRenderer({ canvas })
renderer.setSize(sizes.width, sizes.height)
renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2))

/**
 * Animate
 */
const clock = new THREE.Clock()

const tick = () =>
{
    const elapsedTime = clock.getElapsedTime()

    mesh.rotation.y = elapsedTime

    renderer.render(scene, camera)

    window.requestAnimationFrame(tick)
}

tick()
```

### 9. Create vite.config.js
Write at project root (`[project-name]/vite.config.js`):
```js
import restart from 'vite-plugin-restart'
import glsl from 'vite-plugin-glsl'

export default {
    root: 'src/',
    publicDir: '../static/',
    base: './',
    server:
    {
        host: true,
        open: true
    },
    build:
    {
        outDir: '../dist',
        emptyOutDir: true,
        sourcemap: true
    },
    assetsInclude: ['**/*.gltf', '**/*.glb', '**/*.hdr', '**/*.exr'],
    plugins:
    [
        restart({ restart: [ '../static/**', ] }),
        glsl()
    ]
}
```

### 10. Install Three.js dependencies
```bash
npm install three gsap lil-gui
npm install -D vite-plugin-glsl vite-plugin-restart
```

### 11. Display success message
```
Three.js project "[project-name]" created successfully!

  cd [project-name]
  npm run dev

Project includes:
  - Three.js + basic scene (camera, renderer, animated cube)
  - GSAP for animations
  - lil-gui for debugging
  - GLSL shader support (vite-plugin-glsl)
  - Vite (latest) for fast development

Project structure:
  [project-name]/
  ├── src/
  │   ├── index.html    (entry point)
  │   ├── main.js       (Three.js scene)
  │   └── style.css     (fullscreen canvas)
  ├── static/           (public assets: models, textures, etc.)
  ├── vite.config.js    (Vite + Three.js config)
  ├── package.json
  └── .gitignore
```

## Final Structure
```
[project-name]/
├── node_modules/
├── src/
│   ├── index.html
│   ├── main.js
│   └── style.css
├── static/
├── .gitignore
├── package.json
├── package-lock.json
└── vite.config.js
```

## Notes
- Uses `npm create vite@latest` to get the latest Vite version and .gitignore
- After generation, all Vite demo files are removed and replaced with Three.js-ready files
- `src/main.js` includes a minimal Three.js scene with an animated red cube
- `static/` is for public assets (3D models, textures, HDR maps, etc.)
- GLSL shader files (`.glsl`, `.vert`, `.frag`) are supported via vite-plugin-glsl
- Step 5 uses `2>/dev/null || true` to handle differences between Vite template versions
