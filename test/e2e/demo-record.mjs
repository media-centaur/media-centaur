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
await sleep(1500); // home hero — sidebar visible, the app shows its nav

// 1. Glide down through the home rows (Continue Watching, Recently Added, Coming Up)
const maxY = await page.evaluate(() =>
  Math.max(0, document.body.scrollHeight - window.innerHeight),
);
await smoothScroll(page, Math.min(maxY, 1500), 3600);
await sleep(1000);
await smoothScroll(page, 0, 1400);
await sleep(700);

// 2. Into the library via the sidebar — the nav rail stays on screen
await page.locator('#sidebar a[href="/library"]').first().click();
await sleep(1500); // library WITH the nav visible

// 3. Collapse the sidebar — the artwork takes over (a "watch it respond" beat)
await page.locator("#sidebar").getByText("Collapse", { exact: true }).click();
await sleep(1500);

// 4. Open a title — its detail page takes over the now-full-width frame
await page.mouse.move(300, 400);
await sleep(550);
await page.mouse.click(300, 400);
await sleep(2700); // linger on the detail before the loop restarts

await context.close(); // finalizes the webm
await browser.close();
console.log("recorded to " + OUT_DIR);
