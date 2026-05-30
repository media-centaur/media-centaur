// Records a short, loopable walkthrough of the showcase app as a webm,
// for the marketing-site hero <video>. Run from test/e2e/ so playwright-core
// resolves. Server must be serving on :4003 (showcase override).
import pkg from "playwright-core";
const { chromium } = pkg;

const BASE = "http://127.0.0.1:4003";
const OUT_DIR = process.env.DEMO_OUT_DIR || "/tmp/demo-video";
const W = 1280;
const H = 720;

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function smoothScroll(page, toY, ms) {
  const steps = Math.max(1, Math.round(ms / 16));
  await page.evaluate(
    async ({ toY, steps }) => {
      const startY = window.scrollY;
      const dist = toY - startY;
      const ease = (t) => (t < 0.5 ? 2 * t * t : 1 - Math.pow(-2 * t + 2, 2) / 2);
      for (let i = 1; i <= steps; i++) {
        window.scrollTo(0, startY + dist * ease(i / steps));
        await new Promise((r) => requestAnimationFrame(r));
      }
    },
    { toY, steps },
  );
}

const browser = await chromium.launch({ args: ["--force-color-profile=srgb"] });
const context = await browser.newContext({
  viewport: { width: W, height: H },
  deviceScaleFactor: 1,
  recordVideo: { dir: OUT_DIR, size: { width: W, height: H } },
});
const page = await context.newPage();

// ---- Tour ----
await page.goto(BASE + "/", { waitUntil: "networkidle" });
await sleep(1600); // settle on the home hero

// 1. Glide down through the home rows (Continue Watching, Recently Added, Coming Up)
const maxY = await page.evaluate(() =>
  Math.max(0, document.body.scrollHeight - window.innerHeight),
);
await smoothScroll(page, Math.min(maxY, 1500), 3800);
await sleep(1100);
await smoothScroll(page, 0, 1600);
await sleep(900);

// 2. Into the library grid — couch navigation with the keyboard
await page.goto(BASE + "/library", { waitUntil: "networkidle" });
await sleep(1300);
await page.mouse.move(W / 2, H / 2);
await page.mouse.click(W / 2, H / 2);
for (const key of ["ArrowRight", "ArrowRight", "ArrowRight", "ArrowDown", "ArrowRight"]) {
  await page.keyboard.press(key);
  await sleep(620);
}

// 3. Open a detail, linger, close
await page.keyboard.press("Enter");
await sleep(2200);
await page.keyboard.press("Escape");
await sleep(1000);

await context.close(); // finalizes the webm
await browser.close();
console.log("recorded to " + OUT_DIR);
