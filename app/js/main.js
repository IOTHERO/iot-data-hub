// Router and start-up of the consumer app (hash routes; account links put their token after #).

import { api, h, icon, live, loadLanguage, saved, session, t } from "./core.js";
import { startPickers } from "./picker.js";
import { startChecks } from "./checks.js";
import { splash } from "./splash.js";
import { refreshKeys } from "./local.js";
import { automationsPage } from "./auto.js";
import { alertEvent, alertsPage, loadAlerts } from "./alerts.js";
import * as more from "./more.js";
import * as v from "./views.js";

const root = document.getElementById("app");
const state = { me: null, timer: null, cleanup: null, onLive: null, stopLive: null, pending: null };
// redraw at most every 800 ms when live events arrive in bursts
state.later = (fn) => {
  if (state.pending) return;
  state.pending = setTimeout(() => { state.pending = null; if (!document.hidden) fn(); }, 800);
};
const PUBLIC = new Set(["login", "signup", "forgot", "account"]);

// midnight & champagne by default (the design); light only when the user picks it
const theme = saved.get("app.theme");
if (theme) document.documentElement.dataset.theme = theme;
const accent = saved.get("app.accent");
if (accent) document.documentElement.dataset.accent = accent;
splash({ sound: saved.get("app.sound") !== "off" });   // the logo plays while the app loads

async function render() {
  clearInterval(state.timer);
  state.timer = null;
  state.onLive = null;
  if (state.cleanup) { state.cleanup(); state.cleanup = null; }
  document.querySelectorAll("dialog.sheet").forEach((d) => d.remove());
  const [route, ...args] = location.hash.replace(/^#\/?/, "").split("/").map(decodeURIComponent);
  const page = route || "home";
  if (page === "claim") {               // a scanned label: #/claim/<identifier>/<code>
    if (!session.signedIn) { saved.set("app.after", location.hash); location.hash = "#/login"; return; }
    return show(v.add(state, { identifier: args[0], code: args[1] }), "add");
  }
  if (!PUBLIC.has(page) && !session.signedIn) { location.hash = "#/login"; return; }
  if (!PUBLIC.has(page) && !state.me) {
    try { state.me = await api("GET", "/api/auth/me"); }
    catch (err) {
      // only a refused session signs out; no internet (and nothing kept yet) shows the start
      if (err.status !== 0) session.clear();
      location.hash = "#/login";
      return;
    }
    refreshKeys(api);                      // the local keys, while the server is reachable
    if (!state.stopLive) {                 // one live connection while signed in
      state.stopLive = live((type, data) => {
        if (type === "alert") alertEvent(data);          // the alarm bar and page follow by themselves
        else if (type === "security") document.querySelector(".security-box")?.reload?.();
        else if (state.onLive) state.onLive(type, data);
      });
      loadAlerts();
    }
    more.checkPresence();
  }
  if (PUBLIC.has(page) && state.stopLive) { state.stopLive(); state.stopLive = null; }
  switch (page) {
    case "login": return show(v.login(state.brand));
    case "signup": return show(v.signup());
    case "forgot": return show(v.forgot());
    case "account":
      if (args[0] === "verify") return show(v.verify(args[1]));
      if (args[0] === "reset") return show(v.reset(args[1]));
      if (args[0] === "invitation") return show(v.invitation(args[1]));
      if (args[0] === "forgot") return show(v.forgot());
      return show(v.login());
    case "device":
      if (args[1] === "settings") return show(v.deviceSettings(state, args[0]), "home");
      return show(v.device(state, args[0], args[1] === "focus" ? args[2] : null), "home");
    case "add":
      if (args[0] === "edge") return show(v.addEdge(state, args[1] || null), "add");
      return show(v.add(state), "add");
    case "me": return show(v.me(state), "me");
    case "notifications": return show(v.notifications(state), "home");
    case "alerts": {
      const page = alertsPage();
      state.cleanup = page.cleanup;
      return show(page, "home");
    }
    case "auto": {
      const tab = args[0] === "automations" ? "automations" : "scenes";
      return show(automationsPage(tab, state.me), tab);
    }
    case "members": return show(v.members(state, args[0]), "me");
    case "group": return show(more.groupPage(state, args[0]), "home");
    case "energy": return show(more.energyPage(state), "home");
    case "home-settings": return show(more.homeSettings(state, args[0]), "me");
    case "ticket": return show(more.ticketPage(state, args[0]), "home");
    default: return show(v.home(state), "home");
  }
}

function show(node, navItem = null) {
  const parts = [h("div", { class: "glow", "aria-hidden": "true" }), node];
  if (navItem) parts.push(v.nav(navItem));
  root.replaceChildren(...parts);
  window.scrollTo(0, 0);
  root.classList.add("enter");                    // the page comes in once, not on every redraw
  clearTimeout(show.timer);
  show.timer = setTimeout(() => root.classList.remove("enter"), 1400);
}

// back goes to the page the person came from (not always home): the pages seen in this visit,
// newest last; the browser's / phone's own back is recognised as a step back as well
const trail = [location.hash || "#/home"];
window.addEventListener("hashchange", () => {
  const now = location.hash || "#/home";
  if (trail.length > 1 && trail[trail.length - 2] === now) trail.pop();
  else if (trail[trail.length - 1] !== now) trail.push(now);
  if (trail.length > 50) trail.shift();
  if (!location.hash.startsWith("#/login")) state.me = session.signedIn ? state.me : null;
  render();
});
document.addEventListener("click", (ev) => {
  const back = ev.target.closest?.(".top-bar > a.icon-btn:first-child");
  if (!back || trail.length < 2 || ev.ctrlKey || ev.metaKey) return;
  ev.preventDefault();
  history.back();                       // the page before; its link (href) stays the fallback
});
window.addEventListener("offline", () => document.body.classList.add("is-offline"));
window.addEventListener("online", () => document.body.classList.remove("is-offline"));

if ("serviceWorker" in navigator) {
  navigator.serviceWorker.register("sw.js").catch(() => { /* works without it */ });
}

await loadLanguage(saved.get("app.lang") || "fa");       // Persian first; English in "Me"
document.title = t("app.title");
await brand();
startPickers({ h, icon: (n) => icon(n), t, sheetClass: "sheet" });
startChecks();
render();

/** ?brand=<maker org>: the maker's name on the start page and its nearest accent colour
 * (the CSP allows only the app's own styles, so the colour is one of the four themes). */
async function brand() {
  const id = new URLSearchParams(location.search).get("brand") || saved.get("app.brand");
  if (!id) return;
  try {
    const b = await api("GET", `/api/public/brand/${encodeURIComponent(id)}`, undefined, { auth: false });
    saved.set("app.brand", id);
    state.brand = b;
    document.title = b.display_name;
    if (b.accent && !saved.get("app.accent")) {
      const rgb = (hex) => [1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16));
      const [r, g, bl] = rgb(b.accent);
      const options = { "": "#19B8D0", gold: "#E8B86A", teal: "#7FD1C7", violet: "#A99BFF", coral: "#FF9F7A" };
      const nearest = Object.entries(options).sort(([, a], [, c]) => {
        const d = (x) => rgb(x).reduce((sum, v, i) => sum + (v - [r, g, bl][i]) ** 2, 0);
        return d(a) - d(c);
      })[0][0];
      if (nearest) document.documentElement.dataset.accent = nearest;
    }
  } catch { saved.set("app.brand", null); }
}
