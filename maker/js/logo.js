// The TiTiSwitch logo as vector parts, so the start-up splash can draw it piece by piece: the
// cyan line traces the "T" path, the two orange switches flip, the signals ripple out and the
// wordmark rises. The wordmark is part of the artwork (the brand name in both scripts, as on the
// printed logo), not translatable UI text. Coordinates follow the original 2000 x 2000 artwork.
// maker/js/logo.js is a copy of this file (tests/frontend keeps the two equal).

const NS = "http://www.w3.org/2000/svg";

function el(name, attrs) {
  const node = document.createElementNS(NS, name);
  for (const [k, v] of Object.entries(attrs)) node.setAttribute(k, String(v));
  return node;
}

/** An arc around (cx, cy) from angle a0 to a1 (degrees, clockwise on screen). */
function arc(cx, cy, r, a0, a1) {
  const p = (a) => [cx + r * Math.cos((a * Math.PI) / 180), cy + r * Math.sin((a * Math.PI) / 180)]
    .map((n) => n.toFixed(1)).join(" ");
  return `M${p(a0)}A${r} ${r} 0 0 1 ${p(a1)}`;
}

/** A dot with arcs: [radius, start angle, end angle, ripple step (inner first)]. */
function signal(cx, cy, dot, width, arcs) {
  const g = el("g", { class: "lg-signal" });
  g.append(el("circle", { class: "lg-dot", cx, cy, r: dot }));
  arcs.forEach(([r, a0, a1, step]) => g.append(el("path", {
    class: `lg-wave lg-wave-${step}`, d: arc(cx, cy, r, a0, a1), "stroke-width": width })));
  return g;
}

function toggle(n, x, y, knobY) {
  const g = el("g", { class: `lg-switch lg-switch-${n}` });
  g.append(el("rect", { class: "lg-pill", x, y, width: 112, height: 279, rx: 56 }),
    el("circle", { class: "lg-knob", cx: x + 56, cy: knobY, r: 28 }));
  return g;
}

/** The logo; `wordmark` adds the name under the mark. */
export function logo({ wordmark = true, label = "TiTiSwitch" } = {}) {
  const svg = el("svg", { class: "tt-logo", viewBox: wordmark ? "400 150 1150 1560" : "400 150 1100 1120",
    role: "img", "aria-label": label });
  svg.append(
    el("path", { class: "lg-line", pathLength: 1, "stroke-width": 37,
      d: "M1199 327.5H499.5V554.5H726.5V1006H953.5V554.5H1180.5V1006H1444.5V1233H702" }),
    toggle(1, 783, 529, 600),
    toggle(2, 1011, 739, 946),
    signal(1264, 320, 33, 20, [[88, 216, 293, 0], [143, 214, 295, 1], [86, 38, 113, 0], [142, 34, 116, 1]]),
    signal(647, 1233, 32, 32, [[80, 135, 225, 0], [137, 135, 225, 1], [195, 135, 225, 2]]));
  if (wordmark) {
    const fa = el("text", { class: "lg-word", x: 990, y: 1500, "text-anchor": "middle", direction: "rtl" });
    fa.textContent = "تی‌تی‌سویچ";
    const en = el("text", { class: "lg-latin", x: 990, y: 1680, "text-anchor": "middle" });
    en.textContent = "TiTiSwitch";
    svg.append(fa, en);
  }
  return svg;
}
