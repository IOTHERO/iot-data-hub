// RF remotes of a device with an RF module (433 or 315 MHz): the home names a remote and its keys;
// each key is a button. A new key is learnt from the remote itself - the module listens, the
// person presses that key on the remote, the module keeps its code in a slot - and a touch on
// the button makes the module send that code again (backend/api/alerts.py, through the
// control-safety layer like any command).

import { api, dialog, errorText, h, icon, num, t, toast } from "./core.js";
import { buzz } from "./outputs.js";

const KEY_ICONS = ["remote", "power", "door", "lock", "bulb", "curtain", "fan", "tv", "bell", "arrive", "out"];

/** The remotes card; it loads by itself and stays the same element across redraws. */
export function remotesBox(deviceId, canOperate) {
  const box = h("section", { class: "card stack rf-box hidden" });
  let data = null;
  let editing = false;

  async function load() {
    try { data = await api("GET", `/api/platform/my/devices/${deviceId}/remotes`); }
    catch { data = null; }
    draw();
  }

  function draw() {
    box.classList.toggle("hidden", !data?.supported);
    if (!data?.supported) return;
    const used = data.remotes.reduce((n, r) => n + r.keys.length, 0);
    const add = canOperate ? h("button", { class: "chip accent", onclick: () => remoteDialog(null) },
      icon("plus"), t("rf.add_remote")) : null;
    const edit = canOperate && data.remotes.length ? h("button", { class: `chip ${editing ? "accent" : ""}`,
      "aria-pressed": editing, onclick: () => { editing = !editing; draw(); } },
    icon(editing ? "check" : "edit"), editing ? t("out.edit_done") : t("out.edit_mode")) : null;
    box.replaceChildren(
      h("div", { class: "row between" }, h("h2", { class: "h2 row" }, icon("remote"), t("rf.title")),
        h("div", { class: "row" }, edit, add)),
      h("p", { class: "tiny muted lh" }, t("rf.help", { used: num(used), total: num(data.slots) })),
      ...(data.remotes.length ? data.remotes.map(remoteCard)
        : [h("p", { class: "small muted" }, t("rf.none"))]));
  }

  function remoteCard(r) {
    const head = h("div", { class: "row between" },
      h("span", { class: "row" }, h("b", {}, r.name), h("span", { class: "chip ltr" }, `${r.band} MHz`)),
      editing ? h("button", { class: "icon-btn", "aria-label": t("rf.edit_remote"),
        onclick: () => remoteDialog(r) }, icon("gear")) : null);
    const keys = r.keys.map((k) => keyButton(r, k));
    if (canOperate) {
      keys.push(h("button", { class: "out rf-key add", onclick: () => newKey(r) },
        icon("plus"), h("span", { class: "out-name" }, t("rf.add_key"))));
    }
    return h("div", { class: "stack rf-remote" }, head,
      keys.length ? h("div", { class: "outputs" }, keys) : null);
  }

  function keyButton(r, k) {
    const learnt = !!k.learnt_at;
    const btn = h("button", { class: `out rf-key ${learnt ? "" : "unlearnt"} ${editing ? "editing" : ""}`,
      disabled: !canOperate,
      "aria-label": `${k.name}${learnt ? "" : ` · ${t("rf.not_learnt")}`}`,
      onclick: async () => {
        if (editing) { keyDialog(r, k); return; }
        if (!learnt) { learn(r, k); return; }
        buzz();
        btn.classList.add("pushing", "on");
        try {
          const res = await api("POST", `/api/platform/my/devices/${deviceId}/remotes/${r.remote_id}/keys/${k.key_id}/send`);
          if (res.result !== "applied") toast(t(`write.${res.result}`) !== `write.${res.result}` ? t(`write.${res.result}`) : res.message, "err");
        } catch (err) { toast(errorText(err), "err"); }
        setTimeout(() => btn.classList.remove("pushing", "on"), 600);
      } },
    h("span", { class: "push-ring", "aria-hidden": "true" }), icon(k.icon || "remote"),
    h("span", { class: "out-name" }, k.name),
    learnt ? null : h("span", { class: "tiny dev-label" }, t("rf.tap_to_learn")));
    return btn;
  }

  async function remoteDialog(r) {
    const nameIn = h("input", { class: "input", value: r?.name || "", maxlength: 40,
      placeholder: t("rf.remote_hint"), "aria-label": t("rf.remote_name") });
    let band = r?.band || data.bands[data.bands.length - 1];
    const bands = h("div", { class: "choice", role: "radiogroup", "aria-label": t("rf.band") }, data.bands.map((b) => {
      const item = h("button", { type: "button", class: `choice-item ${b === band ? "on" : ""}`, role: "radio",
        "aria-checked": b === band, onclick: () => {
          band = b;
          for (const o of bands.children) { o.classList.toggle("on", o === item); o.setAttribute("aria-checked", String(o === item)); }
        } }, h("span", { class: "ltr" }, `${b} MHz`));
      return item;
    }));
    const buttons = [["cancel", t("common.cancel")], ["save", t("common.save"), "primary"]];
    if (r) buttons.unshift(["delete", t("auto.delete"), "danger"]);
    const answer = await dialog(r ? t("rf.edit_remote") : t("rf.add_remote"), h("div", { class: "stack" },
      h("div", { class: "field" }, h("span", { class: "label" }, t("rf.remote_name")), nameIn),
      h("span", { class: "label" }, t("rf.band")), bands,
      h("p", { class: "tiny muted lh" }, t("rf.band_help"))), buttons);
    const base = `/api/platform/my/devices/${deviceId}/remotes`;
    try {
      if (answer === "delete") {
        if (!confirm(t("rf.delete_remote_confirm", { name: r.name }))) return;
        await api("DELETE", `${base}/${r.remote_id}`);
      } else if (answer === "save") {
        const body = { name: nameIn.value.trim() || t("rf.title"), band };
        const saved = r ? await api("PUT", `${base}/${r.remote_id}`, body) : await api("POST", base, body);
        if (!r) { await load(); newKey({ ...saved, keys: [] }); return; }   // straight on to its first key
      } else return;
    } catch (err) { toast(errorText(err), "err"); }
    load();
  }

  async function newKey(r) {
    const nameIn = h("input", { class: "input", maxlength: 40, placeholder: t("rf.key_hint"),
      "aria-label": t("rf.key_name") });
    const answer = await dialog(t("rf.add_key"), h("div", { class: "stack" },
      h("div", { class: "field" }, h("span", { class: "label" }, t("rf.key_name")), nameIn),
      h("p", { class: "tiny muted lh" }, t("rf.add_key_help", { band: r.band }))),
    [["cancel", t("common.cancel")], ["ok", t("rf.learn_now"), "primary"]]);
    if (answer !== "ok") return;
    try {
      const k = await api("POST", `/api/platform/my/devices/${deviceId}/remotes/${r.remote_id}/keys`,
        { name: nameIn.value.trim() || t("rf.key_default", { n: num(r.keys.length + 1) }) });
      await load();
      learn(r, k);
    } catch (err) { toast(errorText(err), "err"); }
  }

  /** The learning window: the module listens; the person presses the key on the remote. */
  async function learn(r, k) {
    const ring = h("div", { class: "rf-listen", "aria-hidden": "true" }, h("span"), h("span"), h("span"), icon("remote", "i lg"));
    const status = h("p", { class: "center lh" }, t("rf.press_now", { key: k.name, band: r.band }));
    let closed = false;
    const shown = dialog(t("rf.learning"), h("div", { class: "stack center" }, ring, status),
      [["cancel", t("common.cancel")]]);
    shown.then(() => { closed = true; });
    let res;
    try {
      res = await api("POST", `/api/platform/my/devices/${deviceId}/remotes/${r.remote_id}/keys/${k.key_id}/learn`);
    } catch (err) { res = { result: "failed", message: errorText(err) }; }
    if (!closed) document.querySelector("dialog.sheet")?.closeWith?.(null);
    if (res.result === "learnt") {
      buzz();
      toast(t("rf.learnt", { key: k.name }), "ok");
    } else if (res.result === "timeout") {
      const again = await dialog(t("rf.learning"), h("p", { class: "lh" }, t("rf.timeout")),
        [["cancel", t("common.cancel")], ["again", t("rf.try_again"), "primary"]]);
      if (again === "again") { learn(r, k); return; }
    } else {
      toast(t(`write.${res.result}`) !== `write.${res.result}` ? t(`write.${res.result}`) : res.message, "err");
    }
    load();
  }

  async function keyDialog(r, k) {
    const nameIn = h("input", { class: "input", value: k.name, maxlength: 40, "aria-label": t("rf.key_name") });
    let chosen = k.icon || "remote";
    const picks = KEY_ICONS.map((ic) => {
      const b = h("button", { type: "button", class: `icon-pick ${chosen === ic ? "on" : ""}`, "aria-label": ic,
        "aria-pressed": chosen === ic, onclick: () => {
          chosen = ic;
          for (const o of picks) { o.classList.toggle("on", o === b); o.setAttribute("aria-pressed", String(o === b)); }
        } }, icon(ic));
      return b;
    });
    const answer = await dialog(t("rf.edit_key"), h("div", { class: "stack" },
      h("div", { class: "field" }, h("span", { class: "label" }, t("rf.key_name")), nameIn),
      h("span", { class: "label" }, t("out.icon")), h("div", { class: "icon-grid" }, picks)),
    [["delete", t("auto.delete"), "danger"], ["learn", t("rf.learn_again")], ["save", t("common.save"), "primary"]]);
    const base = `/api/platform/my/devices/${deviceId}/remotes/${r.remote_id}/keys/${k.key_id}`;
    try {
      if (answer === "save") {
        await api("PUT", base, { name: nameIn.value.trim() || k.name, icon: chosen === "remote" ? null : chosen });
      } else if (answer === "delete") {
        if (!confirm(t("rf.delete_key_confirm", { name: k.name }))) return;
        await api("DELETE", base);
      } else if (answer === "learn") {
        learn(r, k);
        return;
      } else return;
    } catch (err) { toast(errorText(err), "err"); }
    load();
  }

  load();
  return box;
}
