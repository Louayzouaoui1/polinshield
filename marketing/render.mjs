// Renders scene.html with headless Chrome over CDP (no npm deps; Node 22+ has WebSocket).
//   node render.mjs stills   -> ../docs/*.png (+ social-preview.png, app icon)
//   node render.mjs video    -> ../docs/polinshield.mp4 (+ demo.gif)
import { spawn, execFileSync } from "node:child_process";
import { mkdirSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const docs = join(here, "../docs");
const CHROME = process.env.CHROME || "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
const port = 9334;
const profile = join(tmpdir(), "polinshield-render-profile");
const chrome = spawn(CHROME, ["--headless=new", `--remote-debugging-port=${port}`, `--user-data-dir=${profile}`,
  "--hide-scrollbars", "--force-device-scale-factor=1", "--window-size=1920,1080", "about:blank"], { stdio: "ignore" });

let target;
for (let i = 0; i < 50 && !target; i++) {
  await new Promise((r) => setTimeout(r, 200));
  try { target = (await (await fetch(`http://127.0.0.1:${port}/json`)).json()).find((t) => t.type === "page"); } catch {}
}
const ws = new WebSocket(target.webSocketDebuggerUrl);
await new Promise((r) => ws.addEventListener("open", r, { once: true }));
let seq = 0;
const pending = new Map();
ws.addEventListener("message", (e) => {
  const m = JSON.parse(e.data);
  if (pending.has(m.id)) { pending.get(m.id)(m); pending.delete(m.id); }
});
const send = (method, params = {}) => new Promise((r) => { const id = ++seq; pending.set(id, r); ws.send(JSON.stringify({ id, method, params })); });

async function load(page, w, h) {
  await send("Emulation.setDeviceMetricsOverride", { width: w, height: h, deviceScaleFactor: 1, mobile: false });
  await send("Page.navigate", { url: "file://" + join(here, page) });
  await new Promise((r) => setTimeout(r, 800));
}
async function shot(t, file) {
  if (t !== null) await send("Runtime.evaluate", { expression: `render(${t})` });
  const { result } = await send("Page.captureScreenshot", { format: "png" });
  writeFileSync(file, Buffer.from(result.data, "base64"));
}

const mode = process.argv[2] || "stills";
mkdirSync(docs, { recursive: true });
if (mode === "stills") {
  await load("scene.html", 1920, 1080);
  for (const [t, name] of [[1.6, "hero"], [7.0, "threat"], [11.9, "layers"], [16.2, "hook"], [20.2, "alert"], [24.5, "install"]])
    await shot(t, join(docs, `${name}.png`));
  // GitHub social preview is 1280x640: crop the title frame to 2:1 and scale it down.
  execFileSync("magick", [join(docs, "hero.png"), "-gravity", "center", "-crop", "1920x960+0+0", "+repage", "-resize", "1280x640", join(docs, "social-preview.png")]);
  await send("Emulation.setDefaultBackgroundColorOverride", { color: { r: 0, g: 0, b: 0, a: 0 } });
  await load("icon.html", 1024, 1024);
  await shot(null, join(docs, "brand/icon-1024.png"));
} else {
  const fps = 30, dur = 26, dir = join(tmpdir(), "polinshield-frames");
  rmSync(dir, { recursive: true, force: true });
  mkdirSync(dir);
  await load("scene.html", 1920, 1080);
  for (let f = 0; f < fps * dur; f++) await shot((f / fps).toFixed(4), join(dir, `${String(f).padStart(4, "0")}.png`));
  execFileSync("ffmpeg", ["-y", "-loglevel", "error", "-framerate", `${fps}`, "-i", join(dir, "%04d.png"),
    "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "20", "-preset", "slow", "-movflags", "+faststart", join(docs, "polinshield.mp4")]);
  execFileSync("ffmpeg", ["-y", "-loglevel", "error", "-i", join(docs, "polinshield.mp4"), "-vf",
    "fps=15,scale=960:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=128[p];[b][p]paletteuse=dither=sierra2_4a", join(docs, "demo.gif")]);
}
ws.close();
chrome.kill();
