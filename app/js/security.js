// A home's security scenarios at the top of the scenes page: burglar alarm (away), night (at home:
// doors and windows only), fire alarm, and the connection-loss alarm. Each is switched on or off;
// a tripped sensor is an alarm only while its scenario is on (backend/home_alerts.py). The alarms
// go to the home's people, picked here by name: their numbers are kept on the home's access page.
// Zones and the siren are not fixed pins: a zone is any input of any module given a type (motion,
// magnet, smoke) on its device page; the siren is whichever outputs of whichever modules the home
// picks here (an 8-output module's relay 3, with the zones wired to an 8-input module).

import { api, dialog, errorText, h, icon, name, num, t, toast } from "./core.js";
import { buzz } from "./outputs.js";

const SCENARIOS = [
  ["burglar", "lock", ["motion", "magnet"]],
  ["night", "moon", ["magnet"]],
  ["fire", "flame", ["smoke"]],
  ["offline", "globe", []],
];

/** The security card of a home; it loads itself and keeps the same element across redraws. */
export function securitySection(org, me) {
  const box = h("section", { class: "stack security-box" });
  let data = null;

  async function load() {
    try { data = await api("GET", `/api/platform/organizations/${org}/security`); }
    catch { data = null; }
    draw();
  }

  async function set(key, on, sw) {
    buzz();
    sw.disabled = true;
    try {
      data = await api("PUT", `/api/platform/organizations/${org}/security`, { [key]: on });
      toast(t(on ? "security.on" : "security.off", { name: t(`security.${key}`) }), on ? "ok" : "");
    } catch (err) { toast(errorText(err), "err"); }
    draw();
  }

  function draw() {
    if (!data) { box.replaceChildren(); return; }
    const armed = SCENARIOS.some(([key]) => key !== "fire" && key !== "offline" && data[key]);
    box.replaceChildren(
      h("div", { class: "row between" },
        h("h2", { class: "h2 row" }, icon("lock"), t("security.title")),
        h("span", { class: `chip ${armed ? "danger" : ""}` }, armed ? t("security.armed") : t("security.disarmed"))),
      h("div", { class: "security-grid" }, SCENARIOS.map(([key, ic, kinds]) => {
        const on = !!data[key];
        const count = kinds.reduce((n, k) => n + (data.sensors?.[k] || 0), 0);
        const sw = h("button", { class: `switch ${on ? "on" : ""}`, "aria-pressed": on,
          "aria-label": `${t(`security.${key}`)}: ${on ? t("me.on") : t("me.off")}`,
          onclick: (ev) => { ev.stopPropagation(); set(key, !on, sw); } },
        h("span", { class: "track" }, h("span", { class: "knob" })));
        return h("div", { class: `card security-card ${on ? "on" : ""} sec-${key}`, role: "group",
          "aria-label": t(`security.${key}`) },
        h("div", { class: "row between" }, h("span", { class: "security-ico" }, icon(ic)), sw),
        h("b", {}, t(`security.${key}`)),
        h("span", { class: "tiny muted lh" }, t(`security.${key}_help`)),
        kinds.length ? h("span", { class: `tiny ${count ? "" : "warn-text"}` },
          count ? t("security.sensors", { n: num(count) }) : t("security.no_sensors")) : null);
      })),
      sirenCard(), zonesCard(), contactsLine());
  }

  /** The siren: which outputs (module + relay) sound, and for how long. */
  function sirenCard() {
    const list = data.sirens || [];
    const choose = h("button", { class: "btn small", onclick: pickSirens }, icon("bell"),
      list.length ? t("security.siren_change") : t("security.siren_pick"));
    return h("div", { class: `card stack tight ${list.length ? "" : "warn-card"}` },
      h("div", { class: "row between" },
        h("span", { class: "row strong" }, icon("bell"), t("security.siren")), choose),
      h("span", { class: "tiny muted lh" }, list.length
        ? t("security.siren_set", { n: num(list.length), min: num(Math.round((data.siren_s || 180) / 60)) })
        : t("security.siren_none")),
      list.length ? h("div", { class: "row wrap" }, list.map((x) =>
        h("span", { class: "chip danger" }, icon("bell"), `${x.device_name} · ${x.name}`))) : null);
  }

  async function pickSirens() {
    let views = [];
    try { views = await api("GET", `/api/platform/my/views?org=${encodeURIComponent(org)}`); }
    catch (err) { toast(errorText(err), "err"); return; }
    const chosen = new Set((data.sirens || []).map((x) => `${x.device_id}/${x.key}`));
    const groups = views.map((v) => {
      const outs = v.tags.filter((x) => x.writable && x.data_type === "bool");
      if (!outs.length) return null;
      return h("div", { class: "stack tight" }, h("span", { class: "label" }, v.device.name),
        h("div", { class: "row wrap" }, outs.map((x) => {
          const id = `${v.device.device_id}/${x.key}`;
          const b = h("button", { type: "button", class: `chip ${chosen.has(id) ? "danger" : ""}`,
            "aria-pressed": chosen.has(id), onclick: () => {
              chosen.has(id) ? chosen.delete(id) : chosen.add(id);
              b.classList.toggle("danger", chosen.has(id));
              b.setAttribute("aria-pressed", String(chosen.has(id)));
            } }, name(x.display_name));
          return b;
        })));
    }).filter(Boolean);
    const time = h("select", { class: "input", "aria-label": t("security.siren_time") },
      [1, 2, 3, 5, 10, 15].map((m) => h("option", { value: m * 60, selected: m * 60 === (data.siren_s || 180) },
        t("security.minutes", { n: num(m) }))));
    const answer = await dialog(t("security.siren"), h("div", { class: "stack" },
      h("p", { class: "small muted lh" }, t("security.siren_help")), ...groups,
      h("div", { class: "field" }, h("span", { class: "label" }, t("security.siren_time")), time)),
    [["cancel", t("common.cancel")], ["save", t("common.save"), "primary"]]);
    if (answer !== "save") return;
    const sirens = [...chosen].map((id) => { const [device_id, key] = id.split("/"); return { device_id, key }; });
    try {
      data = await api("PUT", `/api/platform/organizations/${org}/security`,
        { sirens, siren_s: Number(time.value) });
      toast(t("common.saved"), "ok");
    } catch (err) { toast(errorText(err), "err"); }
    draw();
  }

  /** The alarm zones, by the module each is wired to; defined on the device page. */
  function zonesCard() {
    const zones = data.zones || [];
    const byDevice = new Map();
    for (const z of zones) {
      if (!byDevice.has(z.device_id)) byDevice.set(z.device_id, { name: z.device_name, zones: [] });
      byDevice.get(z.device_id).zones.push(z);
    }
    return h("div", { class: "card stack tight" },
      h("span", { class: "row strong" }, icon("sensor"), t("security.zones")),
      h("span", { class: "tiny muted lh" }, t("security.zones_help")),
      ...[...byDevice.entries()].map(([id, d]) => h("a", { class: "reading plain-link", href: `#/device/${id}` },
        h("span", { class: "small" }, d.name),
        h("span", { class: "row wrap" }, d.zones.map((z) => h("span", { class: "chip" }, icon(z.kind), z.name))))),
      zones.length ? null : h("span", { class: "small warn-text" }, t("security.no_sensors")));
  }

  /** Who is told: the home's contacts, picked by name (their numbers are kept in the home
   * settings, where they are added and changed); SMS and / or a call for each. */
  function contactsLine() {
    const people = data.recipients || [];
    const settings = h("a", { class: "btn small", href: `#/members/${org}` }, icon("people"),
      people.length ? t("security.numbers") : t("security.add_people"));
    const pick = (c, kind) => {
      const on = !!c[kind];
      return h("button", { type: "button", class: `chip ${on ? "accent" : ""}`, "aria-pressed": on,
        "aria-label": `${c.name}: ${t(kind === "sms" ? "contacts.sms_long" : "contacts.call_long")}`,
        onclick: () => setRecipient(c, kind, !on) }, icon(kind === "sms" ? "chat" : "call"),
      t(kind === "sms" ? "contacts.sms" : "contacts.call"));
    };
    return h("div", { class: `card stack tight ${people.some((c) => c.sms || c.call) ? "" : "warn-card"}` },
      h("div", { class: "row between" }, h("span", { class: "row strong" }, icon("people"), t("security.recipients")), settings),
      h("span", { class: "tiny muted lh" }, people.length ? t("security.recipients_help") : t("security.no_contacts")),
      ...people.map((c) => h("div", { class: "reading" }, h("span", { class: "small" }, c.name),
        h("span", { class: "row" }, pick(c, "sms"), pick(c, "call")))));
  }

  async function setRecipient(c, kind, on) {
    buzz();
    const people = data.recipients || [];
    const ids = (k) => people.filter((x) => (x === c && k === kind ? on : x[k])).map((x) => x.contact_id);
    try {
      data = await api("PUT", `/api/platform/organizations/${org}/security/recipients`,
        { sms: ids("sms"), call: ids("call") });
    } catch (err) { toast(errorText(err), "err"); }
    draw();
  }

  box.reload = load;
  load();
  return box;
}
