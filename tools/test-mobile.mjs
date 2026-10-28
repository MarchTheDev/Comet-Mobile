/*
 * Checks the mobile shell against the real Comet app.
 *
 * The app is not mocked: Comet's own App.tsx is bundled with esbuild, mounted
 * in jsdom exactly as its own test suite mounts components, and driven through
 * the same Tauri bridge shim the phone uses, talking to a small stand-in for
 * the native side. mobile.js is then loaded on top, and every anchor it presses
 * is the app's genuine button.
 *
 * What that can prove: the chrome attaches, the tabs reach the app's real
 * controls, long-press opens the app's real menu, and none of it duplicates.
 * What it cannot: how any of it looks. jsdom has no layout and no paint.
 *
 * Usage: node tools/test-mobile.mjs [path-to-comet-web]
 */
import { mkdtempSync, writeFileSync, rmSync, existsSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { createServer } from "node:http";
import { readFileSync } from "node:fs";

const here = path.dirname(fileURLToPath(import.meta.url));
const shimPath = path.join(here, "..", "app", "Resources", "shim.js");
const mobilePath = path.join(here, "..", "app", "Resources", "mobile", "mobile.js");
const cssPath = path.join(here, "..", "app", "Resources", "mobile", "mobile.css");
const cometWeb = path.resolve(process.argv[2] ?? process.env.COMET_WEB ?? path.join(here, "..", ".comet", "web"));

/*
 * Everything below runs out of Comet's own node_modules, so the check runs
 * against the exact packages the app is built with. esbuild arrives as a
 * dependency of Vite rather than of Comet, so it is looked up in the two places
 * npm may put it before giving up with something readable.
 */
function fromComet(...candidates) {
  for (const candidate of candidates) {
    const full = path.join(cometWeb, candidate);
    if (existsSync(full)) return pathToFileURL(full).href;
  }
  throw new Error(
    `Could not find ${candidates[0]} under ${cometWeb}.\n` +
    `Run "npm ci" in that directory first (scripts/prepare.sh does it).`
  );
}
function cometPackage(dir, entry = "lib/api.js") {
  return fromComet(`node_modules/${dir}/${entry}`, `node_modules/vite/node_modules/${dir}/${entry}`);
}

let failures = 0;
const results = [];
function check(name, condition, detail) {
  if (condition) console.log(`  ok    ${name}`);
  else { failures++; console.log(`  FAIL  ${name}${detail ? ` — ${detail}` : ""}`); }
  results.push(condition);
}

/* ------------------------------------------------------------------ fixtures */

const files = [
  { name: "Welcome.md", path: "/vault/Welcome.md", kind: "file" },
  { name: "Ideas.md", path: "/vault/Ideas.md", kind: "file" },
  { name: "Archive", path: "/vault/Archive", kind: "folder" }
];

const replies = {
  list_vault: files,
  read_note: "# Welcome\n\nThis is the test workspace.\n",
  search_vault: [],
  tray_available: false,
  "plugin:autostart|is_enabled": false,
  "plugin:window|show": null,
  "plugin:window|hide": null,
  "plugin:window|is_visible": true,
  "plugin:event|listen": 1,
  "plugin:event|unlisten": null,
  "plugin:event|emit": null,
  restore_vault_access: null,
  google_status: false,
  "plugin:dialog|open": "/vault",
  open_vault: "/vault",
  write_note: null,
  create_note: null,
  create_dir: null,
  "plugin:opener|open_url": null,
  restore_vault: null,
  read_audio_metadata: null,
  read_cached_music_cover: null,
  read_music_cover_for_file: null,
  music_file_fingerprint: null,
  lookup_music_cover: null
};

const seen = [];
const server = createServer((request, response) => {
  if (request.method !== "POST") { response.writeHead(200).end("{}"); return; }
  let body = "";
  request.on("data", (chunk) => { body += chunk; });
  request.on("end", () => {
    let payload = {};
    try { payload = JSON.parse(body); } catch { /* ignore */ }
    seen.push(payload.cmd);
    const value = Object.prototype.hasOwnProperty.call(replies, payload.cmd) ? replies[payload.cmd] : null;
    response.writeHead(200, { "Content-Type": "application/json" });
    response.end(JSON.stringify({ ok: true, value }));
  });
});
await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
const base = `http://127.0.0.1:${server.address().port}`;

/* ------------------------------------------------------------------- jsdom */

const { JSDOM } = await import(fromComet("node_modules/jsdom/lib/api.js"));

const dom = new JSDOM('<!doctype html><html><head><meta charset="utf-8"></head><body><div id="root"></div></body></html>', {
  url: "http://127.0.0.1/",
  pretendToBeVisual: true,
  runScripts: "outside-only"
});
const { window } = dom;

// The browser surfaces Comet touches that jsdom either lacks or stubs out.
class Observer {
  observe() {}
  unobserve() {}
  disconnect() {}
  takeRecords() { return []; }
}
window.ResizeObserver = Observer;
window.IntersectionObserver = Observer;
window.matchMedia = (query) => ({
  matches: /max-width|pointer/.test(query), media: query, onchange: null,
  addEventListener() {}, removeEventListener() {}, addListener() {}, removeListener() {}, dispatchEvent() { return false; }
});
window.requestIdleCallback = (callback) => window.setTimeout(() => callback({ didTimeout: false, timeRemaining: () => 8 }), 0);
window.cancelIdleCallback = (handle) => window.clearTimeout(handle);
window.HTMLElement.prototype.scrollIntoView = function () {};
window.HTMLMediaElement.prototype.play = function () { return Promise.resolve(); };
window.HTMLMediaElement.prototype.pause = function () {};
for (const name of ["PointerEvent"]) {
  if (!window[name]) window[name] = window.MouseEvent;
}
window.URL.createObjectURL = () => "blob:comet-test";
window.URL.revokeObjectURL = () => {};

globalThis.window = window;
globalThis.document = window.document;
Object.defineProperty(globalThis, "navigator", { value: window.navigator, configurable: true });
globalThis.HTMLElement = window.HTMLElement;
globalThis.Element = window.Element;
globalThis.Node = window.Node;
globalThis.MouseEvent = window.MouseEvent;
globalThis.Event = window.Event;
globalThis.CustomEvent = window.CustomEvent;
globalThis.getComputedStyle = window.getComputedStyle.bind(window);
globalThis.requestAnimationFrame = window.requestAnimationFrame.bind(window);
globalThis.cancelAnimationFrame = window.cancelAnimationFrame.bind(window);
globalThis.matchMedia = window.matchMedia;
globalThis.IS_REACT_ACT_ENVIRONMENT = false;
const nodeFetch = globalThis.fetch;
globalThis.fetch = (...args) => nodeFetch(...args);
// The shim runs inside the jsdom window, which has no fetch of its own.
window.fetch = (...args) => nodeFetch(...args);

try {
  const indexedDB = await import(fromComet("node_modules/fake-indexeddb/auto/index.mjs"));
  window.indexedDB = globalThis.indexedDB;
  void indexedDB;
} catch { /* cover cache is not exercised here */ }

// The bridge, loaded the way the app loads it, pointed at the stand-in server.
window.eval(readFileSync(shimPath, "utf8").replaceAll("__COMET_BASE__", base));

// Inside WKWebView the page's global object *is* the window. Under jsdom the
// bundle runs with Node's global object, so the app's isTauri() check and the
// Tauri API's lookups need the same values in both places.
globalThis.isTauri = true;
globalThis.__TAURI_INTERNALS__ = window.__TAURI_INTERNALS__;
globalThis.__TAURI_EVENT_PLUGIN_INTERNALS__ = window.__TAURI_EVENT_PLUGIN_INTERNALS__;

/* --------------------------------------------------------- bundle the app */

const esbuild = await import(cometPackage("esbuild", "lib/main.js"));
const work = mkdtempSync(path.join(tmpdir(), "comet-mobile-test-"));
const entry = path.join(cometWeb, ".test-mobile-entry.tsx");
writeFileSync(entry, `
  import React from "react";
  import { createRoot } from "react-dom/client";
  import App from "./src/App.tsx";
  export function mount(node) {
    const root = createRoot(node);
    root.render(React.createElement(App));
    return root;
  }
`);

const bundlePath = path.join(work, "app.mjs");
await esbuild.build({
  entryPoints: [entry],
  bundle: true,
  format: "esm",
  platform: "browser",
  target: "es2022",
  outfile: bundlePath,
  logLevel: "silent",
  loader: { ".png": "dataurl", ".svg": "text", ".css": "empty", ".mjs": "js" },
  define: { "process.env.NODE_ENV": '"development"' },
  plugins: [{
    name: "comet-vite-isms",
    setup(build) {
      // Vite's virtual version module.
      build.onResolve({ filter: /^virtual:comet-version$/ }, () => ({ path: "comet-version", namespace: "comet" }));
      build.onLoad({ filter: /.*/, namespace: "comet" }, () => ({
        contents: 'export const APP_VERSION = "0.1.0";',
        loader: "js"
      }));
      // `import Worker from "pdfjs-dist/...?worker&inline"`.
      build.onResolve({ filter: /\?worker(&inline)?$/ }, (args) => ({ path: args.path, namespace: "worker" }));
      build.onLoad({ filter: /.*/, namespace: "worker" }, () => ({
        contents: "export default class Worker { postMessage() {} terminate() {} addEventListener() {} removeEventListener() {} }",
        loader: "js"
      }));
    }
  }]
});
rmSync(entry, { force: true });

const app = await import(pathToFileURL(bundlePath).href);
const React = await import(fromComet("node_modules/react/index.js"));

async function settle(times = 6) {
  for (let index = 0; index < times; index++) {
    await new Promise((resolve) => setTimeout(resolve, 12));
    await new Promise((resolve) => window.requestAnimationFrame(() => resolve()));
  }
}

console.log("Comet mobile shell");

/* ------------------------------------------------------------------ mount */

const root = app.mount(document.getElementById("root"));
await settle(10);

check("the app mounts", Boolean(document.querySelector(".app-shell")));
check("the desktop top bar is in the page before the shell runs", Boolean(document.querySelector(".app-topbar")));
check("the shell has not run yet", !document.querySelector(".m-header"));

// Long-press is wired on touchstart; jsdom has no touch, so this exercises the
// install path and the chrome only.
window.eval(readFileSync(mobilePath, "utf8"));
await settle(6);

const html = document.documentElement;
check("html carries comet-mobile", html.classList.contains("comet-mobile"));
check("a header is added", Boolean(document.querySelector(".m-header")));
const tabs = [...document.querySelectorAll(".m-tab")];
check("five tabs are added", tabs.length === 5, String(tabs.length));
check("the tabs are Files, Search, New, Calendar, Library",
  tabs.map((tab) => tab.dataset.tab).join(",") === "files,search,create,calendar,library",
  tabs.map((tab) => tab.dataset.tab).join(","));

const header = document.querySelector(".m-header");
const title = header?.querySelector("strong")?.textContent ?? "";
check("the header names where you are", title.length > 0, title);

// Re-running the script must not stack a second set of chrome.
window.eval(readFileSync(mobilePath, "utf8"));
await settle(3);
check("installing twice changes nothing", document.querySelectorAll(".m-header").length === 1 && document.querySelectorAll(".m-tabs").length === 1);

/* ------------------------------------------------------ opening a workspace */

// Through the app's own controls: the workspace menu, then "Add workspace",
// which asks the native side for a folder. The stand-in returns /vault.
const picker = document.querySelector(".workspace-picker");
picker.dispatchEvent(new window.MouseEvent("click", { bubbles: true }));
await settle(4);
const addWorkspace = [...document.querySelectorAll(".vault-add")]
  .find((button) => button.textContent.trim().startsWith("Add workspace"));
check("the workspace menu offers Add workspace", Boolean(addWorkspace));
addWorkspace.dispatchEvent(new window.MouseEvent("click", { bubbles: true }));
await settle(10);

check("the bridge was actually used", seen.length > 0, `commands seen: ${seen.join(",") || "none"}`);
const entries = [...document.querySelectorAll(".workspace-entry")];
check("the workspace lists the files the native side returned", entries.length === files.length, String(entries.length));

// Rows show titles, not file names: Comet strips ".md" for display, so the
// accessible name on the row menu is the stable way to find a specific file.
function welcomeRow() {
  return [...document.querySelectorAll(".workspace-entry")]
    .find((entry) => entry.querySelector('[aria-label="More options for Welcome.md"]')) ?? null;
}

/* ------------------------------------------------------- driving the tabs */

const filesTab = document.querySelector('.m-tab[data-tab="files"]');
const calendarTab = document.querySelector('.m-tab[data-tab="calendar"]');
const libraryTab = document.querySelector('.m-tab[data-tab="library"]');

calendarTab.dispatchEvent(new window.MouseEvent("click", { bubbles: true }));
await settle(10);
check("Calendar reaches the app's own Calendar view",
  (document.querySelector(".primary-nav .nav-item.active")?.textContent ?? "").includes("Calendar"),
  document.querySelector(".primary-nav .nav-item.active")?.textContent ?? "none");
check("the Calendar tab is marked current", calendarTab.getAttribute("aria-current") === "page");

filesTab.dispatchEvent(new window.MouseEvent("click", { bubbles: true }));
await settle(10);
check("Files reaches the app's own All files view",
  (document.querySelector(".primary-nav .nav-item.active")?.textContent ?? "").includes("All files"),
  document.querySelector(".primary-nav .nav-item.active")?.textContent ?? "none");
check("the Files tab is marked current, and only it", filesTab.getAttribute("aria-current") === "page" &&
  calendarTab.getAttribute("aria-current") !== "page");
check("the files came back", document.querySelectorAll(".workspace-entry").length === files.length);

const sidebarBefore = document.querySelector(".sidebar")?.classList.contains("is-closed");
libraryTab.dispatchEvent(new window.MouseEvent("click", { bubbles: true }));
await settle(4);
const sidebarAfter = document.querySelector(".sidebar")?.classList.contains("is-closed");
check("Library opens the drawer", sidebarBefore === true && sidebarAfter === false, `${sidebarBefore} -> ${sidebarAfter}`);
libraryTab.dispatchEvent(new window.MouseEvent("click", { bubbles: true }));
await settle(4);
check("Library closes it again", document.querySelector(".sidebar")?.classList.contains("is-closed") === true);

/* ------------------------------------------------------------ the anchors */

const anchors = {
  files: () => [...document.querySelectorAll(".sidebar .nav-item")].find((item) => item.textContent.trim().startsWith("All files")),
  calendar: () => [...document.querySelectorAll(".sidebar .nav-item")].find((item) => item.textContent.trim().startsWith("Calendar")),
  search: () => document.querySelector(".sidebar-search"),
  create: () => document.querySelector('[aria-label="Add file or upload"]'),
  drawer: () => document.querySelector(".sidebar-toggle"),
  back: () => document.querySelector('[aria-label="Go back"]')
};
for (const [name, resolve] of Object.entries(anchors)) {
  check(`the ${name} anchor exists in the app`, Boolean(resolve()));
}

/* --------------------------------------------------------------- the menu */

document.querySelector('.m-tab[data-tab="create"]').dispatchEvent(new window.MouseEvent("click", { bubbles: true }));
await settle(6);
const createMenu = document.querySelector(".context-menu");
check("New opens the app's own create menu", Boolean(createMenu));
check("the create menu offers the app's items",
  Boolean(createMenu) && [...createMenu.querySelectorAll("button")].length >= 3,
  createMenu ? String(createMenu.querySelectorAll("button").length) : "no menu");
document.dispatchEvent(new window.KeyboardEvent("keydown", { key: "Escape", bubbles: true }));
await settle(4);
check("Escape closes the create menu", !document.querySelector(".context-menu"));

/* --------------------------------------------------------- long press */

function touch(element, type, point) {
  const event = new window.Event(type, { bubbles: true, cancelable: true });
  Object.defineProperty(event, "touches", { value: type === "touchend" ? [] : [point] });
  element.dispatchEvent(event);
}

const row = welcomeRow();
check("the row for a known file is on screen", Boolean(row));
if (row) {
  touch(row.querySelector(".workspace-entry-open"), "touchstart", { clientX: 20, clientY: 40 });
  await new Promise((resolve) => setTimeout(resolve, 620));
  await settle(4);
  const menu = document.querySelector(".context-menu");
  check("a long press opens that row's menu", Boolean(menu));
  check("the menu belongs to the row that was pressed",
    Boolean(menu) && (menu.textContent ?? "").includes("Welcome.md"),
    menu ? (menu.textContent ?? "").slice(0, 60) : "no menu");
  check("only one menu is open", document.querySelectorAll(".context-menu").length === 1);
  document.dispatchEvent(new window.KeyboardEvent("keydown", { key: "Escape", bubbles: true }));
  await settle(4);
  check("Escape closes it", !document.querySelector(".context-menu"));
}

/* ------------------------------------------------------ the header title */

// A long press ends with the finger lifting, which fires a click. That click
// must not also open the file — it is the shell's one-shot guard, so this is
// the assertion that the guard exists and is spent.
row?.querySelector(".workspace-entry-open").dispatchEvent(new window.MouseEvent("click", { bubbles: true }));
await settle(8);
check("the click that follows a long press does not open the file", !document.querySelector(".note-card"));

row?.querySelector(".workspace-entry-open").dispatchEvent(new window.MouseEvent("click", { bubbles: true }));
await settle(12);
const headerTitle = document.querySelector(".m-header strong")?.textContent ?? "";
check("opening a note puts its name in the header", headerTitle === "Welcome", headerTitle);
check("the note itself rendered", Boolean(document.querySelector(".note-card")));
check("the back button appeared", document.querySelector(".m-header-back")?.hidden === false);

/* ---------------------------------------------------------------- the CSS */

const css = readFileSync(cssPath, "utf8");
check("the stylesheet is scoped to the mobile class", !/(^|\n)\s*(html|body|\.app-shell)\s*\{/.test(css));
check("the desktop top bar is hidden", /\.app-topbar\s*\{\s*display:\s*none/.test(css));
check("every declaration block is closed", (css.match(/\{/g) ?? []).length === (css.match(/\}/g) ?? []).length);
check("menus become sheets", /\.context-menu\s*\{[^}]*bottom:\s*0\s*!important/.test(css));
check("dialogs become sheets", /\.modal-backdrop\s*\{[^}]*place-items:\s*end center/.test(css));
check("inputs avoid the iOS focus zoom", /font-size:\s*16px/.test(css));
const layers = [".sidebar-scrim", ".sidebar", ".context-menu", ".modal-backdrop"].map((selector) => {
  const match = css.match(new RegExp(`html\\.comet-mobile ${selector.replace(".", "\\.")} \\{ z-index: (\\d+)`));
  return match ? Number(match[1]) : NaN;
});
check("the layers stack in order", layers.every((value, index) => index === 0 || value > layers[index - 1]), layers.join(" < "));

/* ------------------------------------------------------------------ done */

root.unmount?.();
server.close();
dom.window.close();
rmSync(work, { recursive: true, force: true });
delete globalThis.IS_REACT_ACT_ENVIRONMENT;

// One machine-readable line, so CI can surface the outcome as an annotation
// even when the run's log is not reachable.
const total = results.length;
const summary = failures === 0
  ? `mobile shell: ${total} checks, all passed`
  : `mobile shell: ${total - failures}/${total} checks passed, ${failures} failed`;
console.log(`\n${summary}`);
process.exit(failures === 0 ? 0 : 1);
