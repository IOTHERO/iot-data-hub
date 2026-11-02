// Start-up splash: the TiTiSwitch logo draws itself for about two seconds while the app loads
// underneath, then fades away (a tap skips it). A short chime plays with it when the browser
// allows sound before the first touch (installed apps usually do); otherwise it stays silent.
// The same file serves the app and the maker panel (maker/js/splash.js is a copy, kept equal by
// tests/frontend); each passes its own sound setting.

import { logo } from "./logo.js";

const SHOW_MS = 2000;
const FADE_MS = 450;

/** Two soft switch clicks, then a rising three-note chime (synthesised, no sound file). */
function chime() {
  const Ctx = window.AudioContext || window.webkitAudioContext;
  if (!Ctx) return;
  let ctx;
  try { ctx = new Ctx(); } catch { return; }
  const play = () => {
    const t0 = ctx.currentTime + 0.05;
    const tone = (at, freq, length, peak, type = "sine") => {
      const osc = ctx.createOscillator();
      const gain = ctx.createGain();
      osc.type = type;
      osc.frequency.setValueAtTime(freq, t0 + at);
      gain.gain.setValueAtTime(0.0001, t0 + at);
      gain.gain.exponentialRampToValueAtTime(peak, t0 + at + 0.012);
      gain.gain.exponentialRampToValueAtTime(0.0001, t0 + at + length);
      osc.connect(gain).connect(ctx.destination);
      osc.start(t0 + at);
      osc.stop(t0 + at + length + 0.05);
    };
    tone(0.70, 2400, 0.04, 0.05, "triangle");         // the first switch flips
    tone(0.85, 2000, 0.04, 0.05, "triangle");         // the second one
    [[1.00, 1046.5], [1.12, 1318.5], [1.24, 1568.0], [1.36, 2093.0]].forEach(([at, f], i) =>
      tone(at, f, i === 3 ? 1.1 : 0.7, i === 3 ? 0.09 : 0.07));
    setTimeout(() => ctx.close().catch(() => {}), 3000);
  };
  if (ctx.state === "running") play();
  else ctx.resume().then(() => { if (ctx.state === "running") play(); else ctx.close(); })
    .catch(() => ctx.close().catch(() => {}));
}

/** Show the splash; resolves when it is gone. */
export function splash({ sound = true } = {}) {
  const still = window.matchMedia?.("(prefers-reduced-motion: reduce)").matches;
  const box = document.createElement("div");
  box.className = `splash ${still ? "still" : ""}`;
  box.setAttribute("aria-hidden", "true");
  const glow = document.createElement("div");
  glow.className = "splash-glow";
  box.append(glow, logo());
  document.body.append(box);
  if (sound) chime();
  return new Promise((done) => {
    let gone = false;
    const leave = () => {
      if (gone) return;
      gone = true;
      box.classList.add("out");
      setTimeout(() => { box.remove(); done(); }, FADE_MS);
    };
    box.addEventListener("pointerdown", leave);
    setTimeout(leave, still ? 900 : SHOW_MS);
  });
}
