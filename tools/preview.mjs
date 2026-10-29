/*
 * See the mobile interface without a phone.
 *
 * The iOS build is invisible until it is installed, which makes judging it
 * guesswork. This builds Comet's page with the shell's layer spliced in —
 * exactly the way CometViewController does it, as a class on <html> plus a
 * <style> and a <script> — and serves it inside a phone-sized frame, so the
 * layout can be looked at in any browser.
 *
 * What it shows: the chrome, the Files surface, the Library sheet, the sheets,
 * the animations, every palette and theme.
 * What it cannot show: haptics, the status bar, the edge swipe, and the native
 * picker — everything that needs the Swift host. Those are reported through the
 * bridge, which is absent here.
 *
 * Usage:
 *   node tools/preview.mjs              # builds, then serves on :8080
 *   PORT=4000 node tools/preview.mjs
 *
 * It needs Comet checked out with its dependencies installed, which is what
 * scripts/prepare.sh does (COMET_WEB overrides the path).
 */
import { createServer } from "node:http";
import { readFile, writeFile, mkdir, cp, rm } from "node:fs/promises";
import { existsSync } from "node:fs";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.join(here, "..");
const cometWeb = path.resolve(process.env.COMET_WEB ?? path.join(root, ".comet", "web"));
const out = path.join(root, ".preview");
const shell = path.join(root, "app", "Resources", "mobile");
const port = Number(process.env.PORT ?? 8080);

if (!existsSync(path.join(cometWeb, "src", "main.tsx"))) {
  console.error(`No Comet source at ${cometWeb}. Run scripts/prepare.sh first.`);
  process.exit(1);
}

/* ------------------------------------------------------------------ build */

// esbuild ships with Comet (Vite depends on it), so it is loaded from there
// rather than being a dependency of this shell.
const esbuild = await import(pathToFileURL(path.join(cometWeb, "node_modules", "esbuild", "lib", "main.js")).href)
  .catch(() => import("esbuild"));

// Read before the bundle: a plugin callback cannot await.
const appVersion = await version();

async function version() {
  try {
    return (await readFile(path.join(root, ".comet-version"), "utf8")).trim();
  } catch {
    return "0.1.0";
  }
}

console.log("bundling Comet…");
await rm(out, { recursive: true, force: true });
await mkdir(out, { recursive: true });

await esbuild.build({
  entryPoints: [path.join(cometWeb, "src", "main.tsx")],
  bundle: true,
  format: "esm",
  target: "safari16",
  outdir: out,
  entryNames: "app",
  assetNames: "assets/[name]-[hash]",
  logLevel: "warning",
  loader: { ".png": "dataurl", ".svg": "dataurl", ".woff2": "file", ".woff": "file", ".ttf": "file" },
  define: { "process.env.NODE_ENV": "\"production\"" },
  plugins: [{
    name: "comet",
    setup(builder) {
      // Comet refers to its public assets by absolute URL, which is right in the
      // web view; leave them alone and serve them from the same folder.
      builder.onResolve({ filter: /^\/.*\.(png|svg|jpe?g|webp|gif|ico)$/ }, (args) => ({ path: args.path, external: true }));
      // The pieces Vite supplies.
      builder.onResolve({ filter: /^virtual:comet-version$/ }, () => ({ path: "version", namespace: "comet" }));
      builder.onLoad({ filter: /.*/, namespace: "comet" }, () => ({
        contents: `export const APP_VERSION = ${JSON.stringify(appVersion)};`,
        loader: "js"
      }));
      builder.onResolve({ filter: /\?worker(&inline)?$/ }, (args) => ({ path: args.path, namespace: "worker" }));
      builder.onLoad({ filter: /.*/, namespace: "worker" }, () => ({
        contents: "export default class Worker { postMessage() {} terminate() {} addEventListener() {} removeEventListener() {} }",
        loader: "js"
      }));
    }
  }]
});

/* ---------------------------------------------- Comet's own public files */

await cp(path.join(cometWeb, "public"), out, { recursive: true });
for (const dir of ["cmaps", "standard_fonts", "wasm", "iccs"]) {
  const from = path.join(cometWeb, "node_modules", "pdfjs-dist", dir);
  if (existsSync(from)) await cp(from, path.join(out, "pdfjs", dir), { recursive: true });
}

/* -------------------------------------- the layer, spliced as iOS does it */

const css = await readFile(path.join(shell, "mobile.css"), "utf8");
const js = await readFile(path.join(shell, "mobile.js"), "utf8");
const page = await readFile(path.join(cometWeb, "index.html"), "utf8");

const html = page
  .replace("</head>", '<link rel="stylesheet" href="/app.css" />\n</head>')
  .replace('<div id="root">', [
    `<style id="comet-mobile-styles">${css}</style>`,
    '<script>document.documentElement.classList.add("comet-mobile");</script>',
    '<div id="root">'
  ].join("\n  "))
  .replace("</body>", `<script>${js}</script>\n</body>`)
  .replace('src="/src/main.tsx"', 'src="/app.js"');

await writeFile(path.join(out, "index.html"), html);

/* ------------------------------------------------- the frame around it */

const frame = `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8" />
<title>Comet for iOS — preview</title>
<meta name="viewport" content="width=device-width, initial-scale=1" />
<style>
  :root { color-scheme: dark; }
  * { box-sizing: border-box; }
  body {
    margin: 0; min-height: 100vh; display: grid; grid-template-rows: auto 1fr auto;
    gap: 18px; padding: 22px; color: #dbe6ec;
    background: radial-gradient(1200px 600px at 50% -10%, #1d2b36, #0b1116 60%);
    font: 14px/1.4 -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
  }
  header { display: flex; align-items: center; gap: 14px; flex-wrap: wrap; }
  h1 { margin: 0; font-size: 15px; font-weight: 700; letter-spacing: -.01em; }
  h1 span { color: #7c99a9; font-weight: 500; }
  .sizes { display: flex; gap: 8px; margin-left: auto; }
  button {
    padding: 8px 14px; color: #cfe0e8; background: #17232c; border: 1px solid #2b3d49;
    border-radius: 99px; font: inherit; font-weight: 600; cursor: pointer;
  }
  button[aria-pressed="true"] { color: #0d1b22; background: #8fc0d6; border-color: transparent; }
  .stage { display: grid; place-items: center; }
  .phone {
    position: relative; border-radius: 54px; background: #0a0f13;
    box-shadow: 0 0 0 10px #1b262e, 0 0 0 12px #0a1116, 0 40px 80px -30px #000;
    transition: width .25s ease, height .25s ease;
  }
  iframe { display: block; width: 100%; height: 100%; border: 0; border-radius: 54px; background: #10161c; }
  .notch {
    position: absolute; top: 10px; left: 50%; width: 116px; height: 28px; margin-left: -58px;
    border-radius: 99px; background: #05080a; pointer-events: none;
  }
  footer { color: #6f8896; font-size: 12.5px; text-align: center; }
  footer code { color: #9ab6c4; }
</style>
</head>
<body>
  <header>
    <h1>Comet for iOS <span>— the shell's layer over Comet's page</span></h1>
    <div class="sizes">
      <button data-size="phone" aria-pressed="true">iPhone</button>
      <button data-size="tablet" aria-pressed="false">iPad</button>
    </div>
  </header>
  <div class="stage">
    <div class="phone" id="phone" style="width: 390px; height: 844px">
      <iframe id="app" src="/app.html" title="Comet"></iframe>
      <div class="notch"></div>
    </div>
  </div>
  <footer>
    The real interface with Comet's sample workspace. Haptics, the status bar and the
    native picker need the Swift host and are not here. Reload after editing
    <code>app/Resources/mobile/</code>.
  </footer>
  <script>
    /*
     * Land on the browsing surface. The app itself opens a note; the frame
     * presses the dock's Files tab once, inside the frame, so the first thing
     * on screen is the surface rather than Comet's own editor chrome.
     */
    const frameWindow = document.getElementById("app");
    const openFiles = () => {
      const target = frameWindow.contentDocument?.querySelector('.m-dock-item[data-tab="files"]');
      if (target) setTimeout(() => target.click(), 350);
    };
    frameWindow.addEventListener("load", openFiles);
    if (frameWindow.contentDocument?.readyState === "complete") openFiles();

    const sizes = { phone: [390, 844], tablet: [820, 1180] };
    const phone = document.getElementById("phone");
    document.querySelectorAll("[data-size]").forEach((button) => {
      button.addEventListener("click", () => {
        const [w, h] = sizes[button.dataset.size];
        phone.style.width = w + "px";
        phone.style.height = h + "px";
        document.querySelectorAll("[data-size]").forEach((other) =>
          other.setAttribute("aria-pressed", String(other === button)));
      });
    });
  </script>
</body>
</html>`;

await writeFile(path.join(out, "phone.html"), frame);

/* ----------------------------------------------------------------- serve */

const types = {
  ".html": "text/html; charset=utf-8", ".js": "text/javascript; charset=utf-8",
  ".css": "text/css; charset=utf-8", ".png": "image/png", ".svg": "image/svg+xml",
  ".woff2": "font/woff2", ".woff": "font/woff", ".ttf": "font/ttf",
  ".json": "application/json", ".wasm": "application/wasm",
  ".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".webp": "image/webp", ".gif": "image/gif",
  ".mp4": "video/mp4", ".webm": "video/webm", ".mp3": "audio/mpeg", ".m4a": "audio/mp4",
  ".pdf": "application/pdf", ".epub": "application/epub+zip"
};

createServer(async (request, response) => {
  const url = decodeURIComponent((request.url || "/").split("?")[0]);
  const name = url === "/" || url === "/phone.html" ? "phone.html" : url === "/app.html" ? "index.html" : url.replace(/^\//, "");
  const file = path.join(out, name);
  const safe = file.startsWith(out) ? file : path.join(out, "phone.html");
  try {
    const body = await readFile(safe);
    response.writeHead(200, {
      "Content-Type": types[path.extname(safe)] || "application/octet-stream",
      "Cache-Control": "no-store"
    });
    response.end(body);
  } catch {
    response.writeHead(404).end("not found");
  }
}).listen(port, "0.0.0.0", () => {
  console.log(`\n  Comet for iOS preview → http://localhost:${port}\n`);
});
