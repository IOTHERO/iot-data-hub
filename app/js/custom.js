// The person's own section of the home screen: whatever they pick - outputs, sensors and scenes
// from any module of the home - in the order they like, under a name they choose. It is one of
// the home layout's sections (Me > home layout), and is kept on this phone like the layout.

import { api, dialog, errorText, h, icon, name, saved, SCENE_TONE, t, toast } from "./core.js";
import { buzz, outButton, sensorRow } from "./outputs.js";

/** {title, items: [{type: "out" | "sensor", device_id, key} | {type: "scene", org, scene_id}]} */
export function customSettings() {
  try {
    const v = JSON.parse(saved.get("app.custom") || "{}");
    return { title: typeof v.title === "string" ? v.title : "", items: Array.isArray(v.items) ? v.items : [] };
  } catch { return { title: "", items: [] }; }
}
function setCustom(v) { saved.set("app.custom", JSON.stringify(v)); }

const itemId = (x) => (x.type === "scene" ? `scene/${x.scene_id}` : `${x.type}/${x.device_id}/${x.key}`);

/** The section's body for the home screen. */
export function customBody(views, scenes, redraw, rerender) {
  const { items } = customSettings();
  const byId = new Map(views.filter(Boolean).map((v) => [v.device.device_id, v]));
  const edit = () => customEditor(views, scenes, rerender);
  if (!items.length) {
    return h("button", { class: "card empty custom-empty", onclick: edit },
      icon("plus", "i lg"), h("p", {}, t("custom.empty")));
  }
  const tiles = [];
  const rows = [];
  for (const x of items) {
    if (x.type === "scene") {
      const s = scenes.find((sc) => String(sc.scene_id) === String(x.scene_id));
      if (s) tiles.push(sceneTile(s));
      continue;
    }
    const v = byId.get(x.device_id);
    const tag = v?.tags.find((tg) => tg.key === x.key);
    if (!tag) continue;
    if (x.type === "out") tiles.push(outButton(x.device_id, tag, redraw, { sub: v.device.name, offline: v.device.state !== "online" }));
    else rows.push(sensorRow(x.device_id, tag));
  }
  return h("div", { class: "stack" },
    tiles.length ? h("div", { class: "outputs custom-tiles" }, tiles) : null,
    rows.length ? h("div", { class: "stack" }, rows) : null);
}

function sceneTile(s) {
  const b = h("button", { class: `out custom-scene tone-${SCENE_TONE[s.icon] || "accent"}`, onclick: async () => {
    buzz();
    b.classList.add("busy");
    try {
      const r = await api("POST", `/api/platform/organizations/${s.org}/scenes/${s.scene_id}/run`);
      const bad = r.detail.filter((d) => d.tag && d.result !== "applied").length;
      toast(bad ? t("auto.scene_partial", { n: bad }) : t("auto.scene_done"), bad ? "err" : "ok");
    } catch (err) { toast(errorText(err), "err"); }
    b.classList.remove("busy");
  } }, icon(s.icon || "power"), h("span", { class: "out-name" }, s.name));
  return b;
}

/** The section's pencil: name it, pick from every module and scene, drag into order. */
export async function customEditor(views, scenes, redraw) {
  const current = customSettings();
  const chosen = [...current.items];
  const title = h("input", { class: "input", value: current.title, maxlength: 30,
    placeholder: t("custom.title_default"), "aria-label": t("custom.title") });
  const order = h("div", { class: "stack tight layout-list" });
  const picks = h("div", { class: "stack" });

  const labelOf = (x) => {
    if (x.type === "scene") return scenes.find((s) => String(s.scene_id) === String(x.scene_id))?.name || "—";
    const v = views.find((vv) => vv?.device.device_id === x.device_id);
    const tag = v?.tags.find((tg) => tg.key === x.key);
    return tag ? `${name(tag.display_name)} · ${v.device.name}` : "—";
  };
  const iconOf = (x) => (x.type === "scene" ? "star" : x.type === "sensor" ? "sensor" : "power");

  function drawOrder() {
    order.replaceChildren(...(chosen.length ? chosen.map((x) => {
      const handle = h("span", { class: "layout-handle", role: "button", tabindex: 0,
        "aria-label": `${t("layout.drag")}: ${labelOf(x)}` }, icon("grip"));
      const row = h("div", { class: "layout-row", "data-id": itemId(x) }, handle,
        h("span", { class: "row grow small" }, icon(iconOf(x)), labelOf(x)),
        h("button", { type: "button", class: "icon-btn", "aria-label": t("auto.delete"),
          onclick: () => { chosen.splice(chosen.indexOf(x), 1); drawOrder(); drawPicks(); } }, icon("x")));
      handle.addEventListener("pointerdown", (ev) => {
        ev.preventDefault();
        row.classList.add("dragging");
        const move = (e) => {
          const over = [...order.children].find((o) => o !== row &&
            e.clientY > o.getBoundingClientRect().top && e.clientY < o.getBoundingClientRect().bottom);
          if (!over) return;
          const below = e.clientY > over.getBoundingClientRect().top + over.offsetHeight / 2;
          order.insertBefore(row, below ? over.nextSibling : over);
        };
        const up = () => {
          row.classList.remove("dragging");
          window.removeEventListener("pointermove", move);
          window.removeEventListener("pointerup", up);
          window.removeEventListener("pointercancel", up);
          const ids = [...order.children].map((el) => el.dataset.id);
          chosen.sort((a, b) => ids.indexOf(itemId(a)) - ids.indexOf(itemId(b)));
        };
        window.addEventListener("pointermove", move);
        window.addEventListener("pointerup", up);
        window.addEventListener("pointercancel", up);
      });
      return row;
    }) : [h("p", { class: "small muted" }, t("custom.none_chosen"))]));
  }

  function toggle(x) {
    const i = chosen.findIndex((c) => itemId(c) === itemId(x));
    if (i >= 0) chosen.splice(i, 1); else chosen.push(x);
    drawOrder();
    drawPicks();
  }

  function chip(x, label, ic) {
    const on = chosen.some((c) => itemId(c) === itemId(x));
    return h("button", { type: "button", class: `chip ${on ? "accent" : ""}`, "aria-pressed": on,
      onclick: () => toggle(x) }, icon(on ? "check" : ic), label);
  }

  function drawPicks() {
    picks.replaceChildren(
      scenes.length ? h("div", { class: "stack tight" }, h("span", { class: "label" }, t("auto.scenes")),
        h("div", { class: "row wrap" }, scenes.map((s) => chip({ type: "scene", org: s.org, scene_id: s.scene_id }, s.name, "star"))))
        : null,
      ...views.filter(Boolean).map((v) => {
        const outs = v.tags.filter((tg) => tg.writable && tg.data_type === "bool");
        const sensors = v.tags.filter((tg) => !tg.writable && tg.data_type === "bool");
        if (!outs.length && !sensors.length) return null;
        return h("div", { class: "stack tight" }, h("span", { class: "label" }, v.device.name),
          h("div", { class: "row wrap" },
            outs.map((tg) => chip({ type: "out", device_id: v.device.device_id, key: tg.key }, name(tg.display_name), "power")),
            sensors.map((tg) => chip({ type: "sensor", device_id: v.device.device_id, key: tg.key }, name(tg.display_name), "sensor"))));
      }));
  }

  drawOrder();
  drawPicks();
  const answer = await dialog(t("custom.edit"), h("div", { class: "stack" },
    h("div", { class: "field" }, h("span", { class: "label" }, t("custom.title")), title),
    h("span", { class: "label" }, t("custom.order")), h("p", { class: "tiny muted lh" }, t("custom.order_help")), order,
    h("span", { class: "label" }, t("custom.pick")), picks),
  [["cancel", t("common.cancel")], ["save", t("common.save"), "primary"]]);
  if (answer !== "save") return;
  setCustom({ title: title.value.trim(), items: chosen });
  toast(t("common.saved"), "ok");
  redraw();
}

export function customTitle() {
  return customSettings().title || t("custom.title_default");
}
