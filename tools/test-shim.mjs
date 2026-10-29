/*
 * Checks that app/Resources/shim.js speaks Tauri's IPC well enough for the real
 * `@tauri-apps/*` packages to drive it.
 *
 * The shim is loaded exactly as the iOS shell loads it (a plain script, before
 * any page script), and then the genuine npm packages that Comet imports are
 * asked to do real work. Whatever they send to the bridge is recorded and
 * compared against the command names the Swift side dispatches.
 *
 * Usage: node tools/test-shim.mjs [path-to-comet-web]
 */
import { readFileSync } from "node:fs";
import path from "node:path";
import { pathToFileURL, fileURLToPath } from "node:url";
import vm from "node:vm";

const here = path.dirname(fileURLToPath(import.meta.url));
const shimPath = path.join(here, "..", "app", "Resources", "shim.js");
const cometWeb = path.resolve(process.argv[2] ?? process.env.COMET_WEB ?? path.join(here, "..", ".comet", "web"));
const packages = path.join(cometWeb, "node_modules", "@tauri-apps");
const BASE = "http://127.0.0.1:47823";

let failures = 0;
const results = [];
function check(name, condition, detail) {
  results.push(condition);
  if (condition) {
    console.log(`  ok    ${name}`);
  } else {
    failures++;
    console.log(`  FAIL  ${name}${detail ? ` — ${detail}` : ""}`);
  }
}

// --- a stand-in browser window ------------------------------------------------
const calls = [];
const replies = {
  list_vault: [{ name: "a.md", path: "/v/a.md", kind: "file" }],
  "plugin:event|listen": 7,
  "plugin:event|unlisten": null,
  "plugin:autostart|is_enabled": false
};
let failNext = null;

globalThis.window = globalThis;
globalThis.fetch = async (url, init) => {
  const payload = JSON.parse(init.body);
  calls.push({ url, cmd: payload.cmd, args: payload.args });
  const result = failNext ? failNext : { ok: true, value: replies[payload.cmd] ?? null };
  failNext = null;
  return { ok: true, status: 200, json: async () => result };
};

const source = readFileSync(shimPath, "utf8").replaceAll("__COMET_BASE__", BASE);
vm.runInThisContext(source, { filename: "shim.js" });

// --- load the genuine packages ------------------------------------------------
const load = (relative) => import(pathToFileURL(path.join(packages, relative)).href);
const core = await load("api/core.js");
const event = await load("api/event.js");
const windowApi = await load("api/window.js");
const dialog = await load("plugin-dialog/dist-js/index.js");
const opener = await load("plugin-opener/dist-js/index.js");
const autostart = await load("plugin-autostart/dist-js/index.js");

const take = () => calls.splice(0, calls.length);
const lastCall = () => {
  const pending = take();
  if (pending.length === 0) throw new Error("the shim sent nothing to the bridge");
  return pending[pending.length - 1];
};

console.log("Comet iOS bridge shim");

// 1. Comet turns on every local-files feature when this reports true.
check("isTauri() is true", core.isTauri() === true);

// 2. Workspace media has to come back as a real, fetchable URL.
const asset = core.convertFileSrc("/var/mobile/Containers/Data/Application/X/Documents/Comet/My Note.mp3");
check("convertFileSrc builds a same-origin URL", asset === `${BASE}/__file?path=%2Fvar%2Fmobile%2FContainers%2FData%2FApplication%2FX%2FDocuments%2FComet%2FMy%20Note.mp3`, asset);
check("convertFileSrc escapes ampersands and hashes", core.convertFileSrc("/v/a&b#c").endsWith("%2Fv%2Fa%26b%23c"));

// 3. Round trip.
const listing = await core.invoke("list_vault", { path: "/v" });
const call = lastCall();
check("invoke posts the command name", call.cmd === "list_vault", call.cmd);
check("invoke posts the arguments unaltered", call.args.path === "/v", JSON.stringify(call.args));
check("invoke posts to /__invoke", call.url === `${BASE}/__invoke`, call.url);
check("invoke resolves the value", Array.isArray(listing) && listing[0].name === "a.md");

// 4. Tauri rejects with a string; Comet renders it with String(reason).
failNext = { ok: false, error: "An item with that name already exists." };
let rejection = null;
try { await core.invoke("rename_entry", { vault: "/v", path: "/v/a.md", newName: "b.md" }); } catch (error) { rejection = error; }
take();
check("invoke rejects with the native message", rejection === "An item with that name already exists.", String(rejection));

// 5. The 512 KB chunk upload Comet uses for dragged-in files.
failNext = null;
await core.invoke("append_dropped_upload", { id: "x", offset: 0, bytes: [1, 2, 3] });
const upload = lastCall();
check("chunk uploads survive the bridge as byte arrays", upload.cmd === "append_dropped_upload" && upload.args.bytes.length === 3, JSON.stringify(upload.args));

// 6. Listeners, including the one App.tsx removes on unmount.
const stop = await event.listen("comet-request-quit", () => {});
const listened = lastCall();
check("listen registers by event name", listened.cmd === "plugin:event|listen" && listened.args.event === "comet-request-quit", JSON.stringify(listened.args));
check("listen forwards a callback id", typeof listened.args.handler === "number");
check("listen resolves to an unlisten function", typeof stop === "function");
await stop();
const stopCall = lastCall();
check("unlisten reaches the bridge", stopCall.cmd === "plugin:event|unlisten", stopCall.cmd);

// 7. Window commands. Comet reveals the app with show() after its handlers are ready.
const current = windowApi.getCurrentWindow();
check("getCurrentWindow labels the single window main", current.label === "main", current.label);
await current.show();
check("show is dispatched", lastCall().cmd === "plugin:window|show");
await current.hide();
check("hide is dispatched", lastCall().cmd === "plugin:window|hide");
const offClose = await current.onCloseRequested(() => {});
const closeListen = calls.splice(0, calls.length).filter((entry) => entry.cmd === "plugin:event|listen");
check("onCloseRequested listens for the close event", closeListen.some((entry) => entry.args.event === "tauri://close-requested"));
check("onCloseRequested resolves", typeof offClose === "function");

// 8. Drag-and-drop listeners: App.tsx subscribes even on touch devices.
await current.onDragDropEvent(() => {});
const dragEvents = take().filter((entry) => entry.cmd === "plugin:event|listen").map((entry) => entry.args.event);
check("onDragDropEvent registers its four events", ["tauri://drag-enter", "tauri://drag-over", "tauri://drag-drop", "tauri://drag-leave"].every((name) => dragEvents.includes(name)), dragEvents.join(", "));

// 9. External links.
await opener.openUrl("https://github.com/MarchTheDev/Comet");
const opened = lastCall();
check("openUrl is dispatched with the URL", opened.cmd === "plugin:opener|open_url" && opened.args.url === "https://github.com/MarchTheDev/Comet", JSON.stringify(opened.args));

// 10. Pickers. Comet asks for a folder for the workspace and files for imports.
await dialog.open({ directory: true, multiple: false });
const folderPick = lastCall();
check("folder picker passes its options", folderPick.cmd === "plugin:dialog|open" && folderPick.args.options.directory === true, JSON.stringify(folderPick.args));
await dialog.open({ directory: false, multiple: true });
check("file picker passes multiple:true", lastCall().args.options.multiple === true);

// 11. Autostart is a desktop idea; the shim must still answer.
await autostart.isEnabled();
check("autostart is answered", lastCall().cmd === "plugin:autostart|is_enabled");

// 12. Resource plumbing used by transforms Comet does not exercise.
check("transformCallback hands back an id", typeof core.transformCallback(() => {}) === "number");

// One machine-readable line, so CI can surface the outcome as an annotation
// even when the run's log is not reachable.
const total = results.length;
const summary = failures === 0
  ? `bridge: ${total} checks, all passed`
  : `bridge: ${total - failures}/${total} checks passed, ${failures} failed`;
console.log(`\n${summary}`);
process.exit(failures === 0 ? 0 : 1);
