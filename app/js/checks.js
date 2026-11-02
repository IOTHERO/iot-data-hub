// Every checkbox and radio of the app as a drawn ring: ticking it, the ring unwinds and its
// stroke flows into a tick (a radio: the ring closes around a dot). The input itself stays,
// invisible on top of the drawing, so labels, keyboard, forms and the code that reads
// `.checked` work as before. Inputs made later (dialogs, redraws) are picked up by an observer.

const NS = "http://www.w3.org/2000/svg";
const DONE = new WeakSet();

function svg(radio) {
  const s = document.createElementNS(NS, "svg");
  s.setAttribute("viewBox", "0 0 24 24");
  s.setAttribute("aria-hidden", "true");
  const ring = document.createElementNS(NS, "circle");
  ring.setAttribute("class", "ck-ring");
  ring.setAttribute("cx", "12");
  ring.setAttribute("cy", "12");
  ring.setAttribute("r", "9.5");
  ring.setAttribute("pathLength", "100");
  s.append(ring);
  if (radio) {
    const dot = document.createElementNS(NS, "circle");
    dot.setAttribute("class", "ck-dot");
    dot.setAttribute("cx", "12");
    dot.setAttribute("cy", "12");
    dot.setAttribute("r", "5");
    s.append(dot);
  } else {
    const tick = document.createElementNS(NS, "path");
    tick.setAttribute("class", "ck-tick");
    tick.setAttribute("d", "M6.5 12.5l3.6 3.6L17.5 8.6");
    tick.setAttribute("pathLength", "100");
    s.append(tick);
  }
  return s;
}

function enhance(input) {
  if (DONE.has(input) || input.closest(".switch")) return;
  DONE.add(input);
  const radio = input.type === "radio";
  const box = document.createElement("span");
  box.className = `ck ${radio ? "ck-radio" : ""}`;
  input.replaceWith(box);
  input.classList.add("ck-input");
  box.append(input, svg(radio));
}

export function startChecks(root = document.body) {
  const scan = (node) => {
    if (node.nodeType !== 1) return;
    if (node.matches?.('input[type="checkbox"], input[type="radio"]')) enhance(node);
    else for (const i of node.querySelectorAll?.('input[type="checkbox"], input[type="radio"]') || []) enhance(i);
  };
  scan(root);
  new MutationObserver((records) => {
    for (const r of records) for (const n of r.addedNodes) scan(n);
  }).observe(root, { childList: true, subtree: true });
}
