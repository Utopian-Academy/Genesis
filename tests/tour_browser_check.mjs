// Opens an exported virtual tour in headless Chrome and walks it the way a
// person would: click the ring for the next view and check the tour moved
// there, facing the same way. Needs Node 22+ (built-in WebSocket) and Chrome.
//
//     node tests/tour_browser_check.mjs path/to/tour.html [chrome.exe]
//
// Prints "TOUR ok ..." / "TOUR FAIL ..." lines and exits non-zero on failure.

import { spawn } from "node:child_process";
import { pathToFileURL } from "node:url";
import { mkdtempSync, existsSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";

const page = resolve(process.argv[2]);
const chrome = process.argv[3] || "C:/Program Files/Google/Chrome/Application/chrome.exe";
if (!existsSync(chrome)) {
  console.log("TOUR skipped: no Chrome at " + chrome);
  process.exit(0);
}
const port = 9300 + Math.floor(Math.random() * 500);
const proc = spawn(chrome, ["--headless=new", "--use-angle=swiftshader", "--enable-unsafe-swiftshader",
  `--remote-debugging-port=${port}`, `--user-data-dir=${mkdtempSync(join(tmpdir(), "gntour-"))}`,
  "--window-size=1280,720", "about:blank"], { stdio: "ignore" });

let ok = true;
const check = (what, good, detail = "") => {
  console.log(`TOUR ${good ? "ok  " : "FAIL"} ${what}${good ? "" : ": " + detail}`);
  ok &&= good;
};
const sleep = ms => new Promise(r => setTimeout(r, ms));

try {
  let targets;
  for (let i = 0; i < 50 && !targets; i++) {
    try { targets = await (await fetch(`http://127.0.0.1:${port}/json`)).json(); } catch { await sleep(200); }
  }
  const ws = new WebSocket(targets.find(t => t.type === "page").webSocketDebuggerUrl);
  await new Promise(r => ws.addEventListener("open", r));
  let id = 0;
  const pending = new Map();
  ws.addEventListener("message", m => {
    const msg = JSON.parse(m.data);
    if (pending.has(msg.id)) { pending.get(msg.id)(msg); pending.delete(msg.id); }
  });
  const send = (method, params = {}) => new Promise(r => { const n = ++id; pending.set(n, r); ws.send(JSON.stringify({ id: n, method, params })); });
  const evaluate = async expr => (await send("Runtime.evaluate", { expression: expr, returnByValue: true })).result.result.value;

  // View 1, facing east, where view 2's ring stands.
  await send("Page.navigate", { url: pathToFileURL(page).href + "#1/90" });
  let ready = false;
  for (let i = 0; i < 50 && !ready; i++) { await sleep(200); ready = await evaluate("!document.getElementById('loading')"); }
  check("the tour loads its pictures", ready);
  const views = await evaluate("typeof TOUR === 'object' && TOUR.stops.length");
  check("it has its views", views >= 2, String(views));
  await sleep(300);
  // The ring is at the centre of the view; click it on the canvas.
  const [cx, cy] = await evaluate("[canvas.clientWidth / 2, canvas.clientHeight / 2]");
  for (const type of ["mousePressed", "mouseReleased"]) {
    await send("Input.dispatchMouseEvent", { type, x: cx, y: cy, button: "left", clickCount: 1 });
  }
  await sleep(300);
  const hash = await evaluate("location.hash");
  check("clicking the ring walks to view 2, still facing east", hash === "#2/90", hash);
  // The menu goes back.
  await evaluate("document.querySelector('#bottom button').click()");
  await sleep(200);
  check("the menu goes back to view 1", (await evaluate("location.hash")).startsWith("#1/"), await evaluate("location.hash"));
  ws.close();
} catch (err) {
  check("the browser check ran", false, String(err));
} finally {
  proc.kill();
}
process.exit(ok ? 0 : 1);
