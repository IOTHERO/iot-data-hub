// Security alerts of the home (a hallway PIR, a door magnet, a smoke detector: a burglar or fire
// alarm wherever they are). The hub opens them (backend/home_alerts.py) and says so on the live
// stream; the home screen shows a pulsing red alarm while any is open, the alarm page lists them:
// each is marked seen, cleared with a swipe, all cleared at once; a touch opens the device.

import { api, errorText, h, home, icon, name, num, t, toast, when } from "./core.js";

const store = { list: [], loaded: false, listeners: new Set() };
const KIND_ICON = { motion: "motion", magnet: "magnet", smoke: "smoke", offline: "globe" };

/** The open alerts (newest first), fetched again when asked or when the stream says so. */
export async function loadAlerts() {
  try {
    store.list = await api("GET", `/api/platform/my/alerts${home.query()}`);
    store.loaded = true;
  } catch { /* offline: keep what is shown */ }
  for (const fn of store.listeners) fn(store.list);
  return store.list;
}

export const openAlerts = () => store.list;
export const unseen = () => store.list.filter((a) => !a.seen_at);

/** Called with every change of the list; returns the unsubscribe. */
export function onAlerts(fn) {
  store.listeners.add(fn);
  return () => store.listeners.delete(fn);
}

/** An ``alert`` event of the live stream: reload, and tell the person about a new trip. */
export async function alertEvent(alert) {
  const before = store.list.find((a) => a.alert_id === alert.alert_id);
  await loadAlerts();
  const tripped = !alert.cleared_at && !alert.seen_at && (!before || before.trips !== alert.trips);
  if (!tripped) return;
  const now = store.list.find((a) => a.alert_id === alert.alert_id);
  try { navigator.vibrate?.([200, 100, 200]); } catch { /* not supported */ }
  toast(t(`alarm.kind_${alert.kind}`, { name: now ? name(now.tag_name) : "" }), "err");
}

const label = (a) => t(`alarm.kind_${a.kind}`, { name: name(a.tag_name) });

/** The home screen's live alarm: a pulsing red bar while any alert is open (else nothing). */
export function alarmBar() {
  const bar = h("a", { class: "alarm-bar hidden", href: "#/alerts", role: "alert" });
  const draw = (list) => {
    bar.classList.toggle("hidden", !list.length);
    if (!list.length) return;
    const fresh = list.filter((a) => !a.seen_at);
    bar.classList.toggle("calm", !fresh.length);           // seen: steady, not pulsing
    const first = fresh[0] || list[0];
    bar.replaceChildren(
      h("span", { class: "alarm-dot", "aria-hidden": "true" }, h("span", {}), icon(KIND_ICON[first.kind] || "alert")),
      h("span", { class: "stack tight grow" },
        h("b", {}, fresh.length ? t("alarm.active", { n: num(fresh.length) }) : t("alarm.open", { n: num(list.length) })),
        h("span", { class: "tiny" }, `${label(first)} · ${first.device_name}`)),
      icon("next"));
  };
  draw(store.list);
  const off = onAlerts(draw);
  if (!store.loaded) loadAlerts();
  bar.cleanup = off;
  return bar;
}

// --- the alarm page ------------------------------------------------------------------------------

export function alertsPage() {
  const list = h("div", { class: "stack alarm-list" });
  const clearAll = h("button", { class: "btn danger block alarm-clear" }, icon("trash"), t("alarm.clear_all"));
  const seenAll = h("button", { class: "btn block" }, icon("check"), t("alarm.seen_all"));
  const foot = h("div", { class: "alarm-foot stack" }, seenAll, clearAll);
  const page = h("div", { class: "page alarm-page" },
    h("div", { class: "row between top-bar" },
      h("a", { class: "icon-btn", href: "#/home", "aria-label": t("common.back") }, icon("back")),
      h("h1", { class: "h2 grow center" }, t("alarm.title")), h("span", { class: "icon-btn hidden" })),
    h("p", { class: "tiny muted center" }, t("alarm.swipe_hint")), list, foot);

  const act = async (path, button) => {
    if (button) button.disabled = true;
    try { await api("POST", path); } catch (err) { toast(errorText(err), "err"); }
    await loadAlerts();
  };
  seenAll.addEventListener("click", () => act(`/api/platform/my/alerts/seen${home.query()}`, seenAll));
  clearAll.addEventListener("click", () => act(`/api/platform/my/alerts/clear${home.query()}`, clearAll));

  const draw = (rows) => {
    foot.classList.toggle("hidden", !rows.length);
    seenAll.classList.toggle("hidden", !rows.some((a) => !a.seen_at));
    seenAll.disabled = false;
    clearAll.disabled = false;
    list.replaceChildren(...(rows.length ? rows.map((a) => item(a, act))
      : [h("div", { class: "card empty" }, icon("check", "i lg"), h("p", {}, t("alarm.none")))]));
  };
  draw(store.list);
  page.cleanup = onAlerts(draw);
  loadAlerts();
  return page;
}

function item(a, act) {
  const seen = h("button", { class: `chip ${a.seen_at ? "ok" : "danger"} seen-btn`, disabled: !!a.seen_at,
    onclick: (ev) => { ev.stopPropagation(); act(`/api/platform/my/alerts/${a.alert_id}/seen`, ev.currentTarget); } },
  icon("check"), a.seen_at ? t("alarm.seen") : t("alarm.mark_seen"));
  const card = h("div", { class: `card alarm-item ${a.seen_at ? "" : "live"}`, role: "button", tabindex: 0,
    "aria-label": `${label(a)} · ${a.device_name}`,
    onclick: () => { location.hash = `#/device/${a.device_id}/focus/${a.tag_key}`; },
    onkeydown: (ev) => { if (ev.key === "Enter") location.hash = `#/device/${a.device_id}/focus/${a.tag_key}`; } },
  h("span", { class: "alarm-ico" }, icon(KIND_ICON[a.kind] || "alert")),
  h("span", { class: "stack tight grow" },
    h("b", {}, label(a)),
    h("span", { class: "tiny muted" }, [a.device_name, a.room].filter(Boolean).join(" · ")),
    h("span", { class: "tiny muted" }, a.trips > 1 ? t("alarm.trips", { n: num(a.trips), when: when(a.last_at) })
      : when(a.last_at))),
  seen);
  swipe(card, () => act(`/api/platform/my/alerts/${a.alert_id}/clear`));
  return card;
}

/** Drag the card sideways (either way) far enough and it goes: the alert is cleared. The card
 * follows the finger through the Web Animations API (the CSP allows no inline styles). */
function swipe(el, done) {
  let x0 = null;
  let dx = 0;
  let anim = null;
  const place = (x, opacity, ms = 0) => {
    const frames = [{ transform: `translateX(${x}px)`, opacity }];
    if (anim && ms === 0) { anim.effect.setKeyframes(frames); return; }
    anim?.cancel();
    anim = el.animate(frames, { duration: ms, fill: "forwards", easing: "ease-out" });
  };
  el.addEventListener("pointerdown", (ev) => {
    if (ev.target.closest("button")) return;
    x0 = ev.clientX; dx = 0;
    el.setPointerCapture?.(ev.pointerId);
  });
  el.addEventListener("pointermove", (ev) => {
    if (x0 === null) return;
    dx = ev.clientX - x0;
    if (Math.abs(dx) > 6) el.classList.add("dragging");
    place(dx, Math.max(0.25, 1 - Math.abs(dx) / el.offsetWidth));
  });
  const end = () => {
    if (x0 === null) return;
    x0 = null;
    const gone = Math.abs(dx) > el.offsetWidth * 0.35;
    el.classList.remove("dragging");
    if (gone) {
      place((dx > 0 ? 1.1 : -1.1) * el.offsetWidth, 0, 180);
      setTimeout(done, 180);
    } else {
      place(0, 1, 200);
    }
    if (Math.abs(dx) > 6) {                       // a drag is not a touch
      el.addEventListener("click", (ev) => ev.stopImmediatePropagation(), { capture: true, once: true });
    }
  };
  el.addEventListener("pointerup", end);
  el.addEventListener("pointercancel", end);
}
