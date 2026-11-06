// Members of a home and its access levels: a level is a name, ticks (what the member may do),
// a scope (every device, or some rooms / groups / single outputs), hours (weekdays, from-to)
// and "only his own scenes". The server enforces all of it; this page only edits it.

import { api, dialog, errorText, h, icon, name, t, toast, viewsOf } from "./core.js";
import { contactsSection } from "./more.js";

const BUILT_IN = ["customer_owner", "customer_member", "customer_viewer"];
const PERM_ICON = { "device.view": "home", "device.operate": "power", "scene.run": "star",
  "automation.manage": "sliders", "timer.manage": "clock", "energy.view": "bolt",
  "device.share": "share", "org.members": "people", "home.settings": "gear", "ticket.manage": "chat" };

function header(title, back) {
  return h("div", { class: "row between top-bar" },
    h("a", { class: "icon-btn", href: back, "aria-label": t("common.back") }, icon("back")),
    h("h1", { class: "h2 grow center" }, title), h("span", { class: "icon-btn hidden" }));
}

function busy(button, task) {
  return async (ev) => {
    ev?.preventDefault?.();
    button.disabled = true;
    try { await task(); } catch (err) { toast(errorText(err), "err"); } finally { button.disabled = false; }
  };
}

const roleName = (role, levels) => (role.startsWith("lvl_")
  ? (levels.find((l) => l.role_id === role)?.name || t("levels.custom")) : t(`roles.${role}`));

export function members(state, orgId) {
  const page = h("div", { class: "page" }, header(t("members.title"), "#/me"));
  const body = h("div", { class: "stack loose" });
  page.append(body);
  async function draw() {
    let rows, lv;
    try {
      [rows, lv] = await Promise.all([api("GET", `/api/platform/organizations/${orgId}/members`),
        api("GET", `/api/platform/organizations/${orgId}/levels`)]);
    } catch (err) { body.replaceChildren(h("p", {}, errorText(err))); return; }
    const all = [...BUILT_IN, ...lv.levels.map((l) => l.role_id)];
    const choose = (value) => h("select", { class: "input", "aria-label": t("members.role") },
      all.map((r) => h("option", { value: r, selected: r === value }, roleName(r, lv.levels))));

    // members: tap one to change his level or remove him
    const memberRows = rows.map((m) => h("button", { class: "reading pick", onclick: async () => {
      const sel = choose(m.role_id);
      // the member's own mobile: whose this account is, and where the alarms reach them
      const phone = h("input", { class: "input ltr", type: "tel", inputmode: "tel", value: m.phone || "",
        placeholder: "0912…", "aria-label": t("members.phone") });
      const answer = await dialog(m.display_name, h("div", { class: "stack" },
        h("span", { class: "tiny muted ltr" }, m.email || ""),
        h("span", { class: "label" }, t("members.phone")), phone,
        h("p", { class: "tiny muted lh" }, t("members.phone_help")),
        h("span", { class: "label" }, t("members.role")), sel,
        h("p", { class: "tiny muted lh" }, t("levels.change_help"))),
      [["remove", t("members.remove"), "danger"], [null, t("common.cancel")], ["save", t("common.save"), "primary"]]);
      try {
        if (answer === "save") {
          const number = phone.value.trim().replace(/[۰-۹]/g, (d) => "۰۱۲۳۴۵۶۷۸۹".indexOf(d)).replace(/[\s-]/g, "");
          if (number !== (m.phone || "")) {
            await api("PUT", `/api/platform/organizations/${orgId}/members/${m.user_role_id}/phone`,
              { phone: number || null });
          }
          if (sel.value !== m.role_id) {
            await api("PATCH", `/api/platform/organizations/${orgId}/members/${m.user_role_id}`, { role: sel.value });
          }
          toast(t("common.saved"), "ok");
        } else if (answer === "remove") {
          if (!confirm(t("members.remove_confirm"))) return;
          await api("DELETE", `/api/platform/organizations/${orgId}/members/${m.user_role_id}`);
        } else return;
        draw();
      } catch (err) { toast(errorText(err), "err"); }
    } }, h("span", { class: "stack tight" }, h("span", {}, m.display_name),
      h("span", { class: "tiny muted ltr" }, m.email || ""),
      h("span", { class: `tiny ltr ${m.phone ? "" : "warn-text"}` }, m.phone || t("members.no_phone"))),
    h("span", { class: `chip ${m.role_id.startsWith("lvl_") ? "violet" : m.role_id === "customer_owner" ? "accent" : ""}` },
      roleName(m.role_id, lv.levels))));

    // invite
    const email = h("input", { class: "input", type: "email", dir: "ltr", placeholder: "name@example.com",
      "aria-label": t("share.email") });
    const role = choose("customer_member");
    const invite = h("button", { class: "btn primary" }, t("members.invite"));
    invite.addEventListener("click", busy(invite, async () => {
      await api("POST", `/api/platform/organizations/${orgId}/invitations`, { email: email.value.trim(), role: role.value });
      email.value = "";
      toast(t("share.sent"), "ok");
    }));

    // levels: the built-in ones (read only) and the home's own
    const levelCard = (title, perms, extra, onEdit) => h(onEdit ? "button" : "div",
      { class: `card stack level-card ${onEdit ? "editable" : ""}`, onclick: onEdit || null },
      h("div", { class: "row between" }, h("span", { class: "h3" }, title),
        onEdit ? icon("edit") : h("span", { class: "chip" }, t("levels.built_in"))),
      h("div", { class: "row wrap perm-chips" }, lv.permissions.map((p) => h("span",
        { class: `perm-chip ${perms.includes(p) ? "on" : ""}`, title: t(`perm.${p.replace(".", "_")}`) }, icon(PERM_ICON[p] || "check")))),
      extra);
    const limits = (l) => {
      const parts = [];
      const sc = l.scope || {};
      parts.push(sc.rooms?.length || sc.groups?.length || sc.outputs?.length
        ? t("levels.scope_some", { r: sc.rooms?.length || 0, g: sc.groups?.length || 0, o: sc.outputs?.length || 0 })
        : t("levels.scope_all"));
      if (l.schedule) parts.push(t("levels.hours_x", { from: l.schedule.from, to: l.schedule.to }));
      if (l.own_only) parts.push(t("levels.own_only_short"));
      parts.push(t("levels.members_n", { n: l.members }));
      return h("span", { class: "tiny muted" }, parts.join(" · "));
    };
    const newLevel = h("button", { class: "btn block dashed-btn" }, icon("plus"), t("levels.new"));
    newLevel.addEventListener("click", async () => { if (await levelDialog(orgId, lv, null)) draw(); });

    body.replaceChildren(
      h("section", { class: "stack" }, h("h2", { class: "h2" }, t("members.title")), ...memberRows),
      contactsSection(orgId, true),
      h("section", { class: "card stack" }, h("h2", { class: "h2" }, t("members.invite")), email,
        h("span", { class: "label" }, t("members.role")), role),
      invite,
      h("section", { class: "stack" }, h("div", { class: "row between" }, h("h2", { class: "h2" }, t("levels.title")),
        h("span", { class: "tiny muted" }, t("levels.help_short"))),
      ...lv.built_in.map((b) => levelCard(t(`roles.${b.role_id}`), b.permissions, h("span", { class: "tiny muted" },
        t(`levels.about_${b.role_id}`)), null)),
      ...lv.levels.map((l) => levelCard(l.name, l.permissions, limits(l),
        async () => { if (await levelDialog(orgId, lv, l)) draw(); })),
      newLevel));
  }
  draw();
  return page;
}

/** Create or change one level. Resolves true when saved or deleted. */
async function levelDialog(orgId, lv, level) {
  const devices = await api("GET", `/api/platform/my/devices?org=${encodeURIComponent(orgId)}`).catch(() => []);
  const [views, groups] = await Promise.all([viewsOf(devices, `?org=${encodeURIComponent(orgId)}`),
    api("GET", `/api/platform/organizations/${orgId}/groups`).catch(() => [])]);
  const scope = level?.scope || {};

  const nameIn = h("input", { class: "input", value: level?.name || "", maxlength: 40,
    placeholder: t("levels.name_hint"), "aria-label": t("levels.name") });

  // the ticks
  const ticks = new Set(level?.permissions || ["device.view", "device.operate"]);
  const tickRows = lv.permissions.map((p) => {
    const cb = h("input", { type: "checkbox", checked: ticks.has(p), disabled: p === "device.view",
      onchange: () => { if (cb.checked) ticks.add(p); else ticks.delete(p); } });
    return h("label", { class: "reading check-row tick-row" }, h("span", { class: "row grow" },
      h("span", { class: "tick-ico" }, icon(PERM_ICON[p] || "check")),
      h("span", { class: "stack tight" }, h("span", {}, t(`perm.${p.replace(".", "_")}`)), h("span", { class: "tiny muted" }, t(`perm_help.${p.replace(".", "_")}`)))), cb);
  });
  ticks.add("device.view");

  // the scope: every device, or some rooms / groups / outputs
  const limited = Boolean(scope.rooms?.length || scope.groups?.length || scope.outputs?.length);
  const scopeAll = h("input", { type: "radio", name: "lv-scope", checked: !limited });
  const scopeSome = h("input", { type: "radio", name: "lv-scope", checked: limited });
  const rooms = [...new Set(devices.map((d) => d.room).filter(Boolean))].sort();
  const pick = (list, chosen, label) => {
    const set = new Set(chosen || []);
    const box = h("div", { class: "row wrap" }, list.map(([value, text]) => {
      const chip = h("button", { type: "button", class: `tab ${set.has(value) ? "on" : ""}`, onclick: () => {
        if (set.has(value)) set.delete(value); else set.add(value);
        chip.classList.toggle("on", set.has(value));
      } }, text);
      return chip;
    }));
    return { set, el: list.length ? h("div", { class: "stack tight" }, h("span", { class: "label" }, label), box) : null };
  };
  const roomPick = pick(rooms.map((r) => [r, r]), scope.rooms, t("levels.rooms"));
  const groupPick = pick(groups.map((g) => [g.group_id, g.name]), scope.groups, t("levels.groups"));
  const outSet = new Set((scope.outputs || []).map((o) => `${o.device_id}:${o.key}`));
  const outputs = views.filter(Boolean).map((v) => {
    const outs = v.tags.filter((x) => x.data_type === "bool" && x.kind === "digital_output");
    if (!outs.length) return null;
    return h("div", { class: "stack tight" }, h("span", { class: "tiny muted" }, v.device.name),
      h("div", { class: "row wrap" }, outs.map((x) => {
        const id = `${v.device.device_id}:${x.key}`;
        const chip = h("button", { type: "button", class: `tab ${outSet.has(id) ? "on" : ""}`, onclick: () => {
          if (outSet.has(id)) outSet.delete(id); else outSet.add(id);
          chip.classList.toggle("on", outSet.has(id));
        } }, name(x.display_name));
        return chip;
      })));
  }).filter(Boolean);
  const somePanel = h("div", { class: `stack scope-panel ${limited ? "" : "hidden"}` }, roomPick.el, groupPick.el,
    outputs.length ? h("span", { class: "label" }, t("levels.outputs")) : null, ...outputs,
    h("p", { class: "tiny muted lh" }, t("levels.scope_help")));
  for (const r of [scopeAll, scopeSome]) r.addEventListener("change", () => somePanel.classList.toggle("hidden", scopeAll.checked));

  // the hours
  const sched = level?.schedule || null;
  const hoursOn = h("input", { type: "checkbox", checked: Boolean(sched) });
  const days = new Set(sched?.weekdays || [0, 1, 2, 3, 4, 5, 6]);
  const dayChips = h("div", { class: "row wrap" }, [0, 1, 2, 3, 4, 5, 6].map((d) => {
    const chip = h("button", { type: "button", class: `tab ${days.has(d) ? "on" : ""}`, onclick: () => {
      if (days.has(d)) days.delete(d); else days.add(d);
      chip.classList.toggle("on", days.has(d));
    } }, t(`week.${d}`));
    return chip;
  }));
  const from = h("input", { class: "input ltr", type: "time", value: sched?.from || "08:00", "aria-label": t("auto.from") });
  const to = h("input", { class: "input ltr", type: "time", value: sched?.to || "18:00", "aria-label": t("auto.to") });
  const hoursPanel = h("div", { class: `stack ${sched ? "" : "hidden"}` }, dayChips,
    h("div", { class: "two" }, h("label", { class: "field" }, h("span", { class: "label" }, t("auto.from")), from),
      h("label", { class: "field" }, h("span", { class: "label" }, t("auto.to")), to)),
    h("p", { class: "tiny muted lh" }, t("levels.hours_help")));
  hoursOn.addEventListener("change", () => hoursPanel.classList.toggle("hidden", !hoursOn.checked));

  const ownOnly = h("input", { type: "checkbox", checked: Boolean(level?.own_only) });

  const form = h("div", { class: "stack" },
    h("label", { class: "field" }, h("span", { class: "label" }, t("levels.name")), nameIn),
    h("span", { class: "section-label" }, t("levels.ticks")), ...tickRows,
    h("span", { class: "section-label" }, t("levels.scope")),
    h("label", { class: "check-row" }, scopeAll, h("span", {}, t("levels.scope_all"))),
    h("label", { class: "check-row" }, scopeSome, h("span", {}, t("levels.scope_pick"))), somePanel,
    h("span", { class: "section-label" }, t("levels.hours")),
    h("label", { class: "check-row" }, hoursOn, h("span", {}, t("levels.hours_on"))), hoursPanel,
    h("label", { class: "check-row" }, ownOnly, h("span", {}, t("levels.own_only"))));
  const buttons = [[null, t("common.cancel")], ["save", t("common.save"), "primary"]];
  if (level) buttons.unshift(["delete", t("auto.delete"), "danger"]);
  for (;;) {
    const answer = await dialog(level ? t("levels.edit") : t("levels.new"), form, buttons);
    try {
      if (answer === "delete") {
        if (!confirm(t("levels.delete_confirm"))) continue;
        await api("DELETE", `/api/platform/organizations/${orgId}/levels/${level.role_id}`);
        toast(t("levels.deleted"), "ok");
        return true;
      }
      if (answer !== "save") return false;
      if (!nameIn.value.trim()) { toast(t("levels.need_name"), "err"); continue; }
      if (hoursOn.checked && !days.size) { toast(t("levels.need_day"), "err"); continue; }
      const body = {
        name: nameIn.value.trim(), permissions: [...ticks], own_only: ownOnly.checked,
        scope: scopeAll.checked ? {} : { rooms: [...roomPick.set], groups: [...groupPick.set].map(Number),
          outputs: [...outSet].map((id) => { const [device_id, key] = id.split(":"); return { device_id, key }; }) },
        schedule: hoursOn.checked ? { weekdays: [...days].sort(), from: from.value || "08:00", to: to.value || "18:00" } : null,
      };
      if (!scopeAll.checked && !body.scope.rooms.length && !body.scope.groups.length && !body.scope.outputs.length) {
        toast(t("levels.need_scope"), "err"); continue;
      }
      if (level) await api("PUT", `/api/platform/organizations/${orgId}/levels/${level.role_id}`, body);
      else await api("POST", `/api/platform/organizations/${orgId}/levels`, body);
      toast(t("common.saved"), "ok");
      return true;
    } catch (err) { toast(errorText(err), "err"); }
  }
}
