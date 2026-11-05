// Local mode: when the internet is down but the phone is on the home Wi-Fi, the Android app
// switches devices directly (hub.platform.local_sign: a one-time nonce from the device, the
// command signed with the device's local key). The page itself cannot reach the home network
// (a secure page may not call a plain-HTTP address in the house), so the Android shell lends
// a small bridge:
//
//   window.TiTiNative.request(id, method, url, bodyJson, timeoutMs)  -> window.__titiDone(id, status, text)
//   window.TiTiNative.discover(id, timeoutMs)                       -> window.__titiDone(id, 200, "[{device_id, host, port}]")
//   window.TiTiNative.hmac(keyBase64url, message)                   -> signature (base64url)
//
// Without the bridge (web, iPhone) only the last data is shown while offline (read-only).
// What the app shows offline comes from the last answers of the server, kept on the phone.

import { saved } from "./core.js";

const CACHED = [/^\/api\/auth\/me$/, /^\/api\/account\/organizations$/,
  /^\/api\/platform\/my\/(devices|views|summary)(\?.*)?$/];
const native = () => (typeof window !== "undefined" ? window.TiTiNative : undefined);
export const hasBridge = () => !!native();

// --- the bridge ---------------------------------------------------------------------------------

const calls = new Map();
let seq = 0;
if (typeof window !== "undefined") {
  window.__titiDone = (id, status, text) => {
    const done = calls.get(id);
    if (done) { calls.delete(id); done({ status, text }); }
  };
}

function bridge(method, args, timeoutMs) {
  return new Promise((resolve) => {
    const id = `c${++seq}`;
    calls.set(id, resolve);
    setTimeout(() => { if (calls.delete(id)) resolve({ status: 0, text: "" }); }, timeoutMs + 500);
    native()[method](id, ...args, timeoutMs);
  });
}

async function lan(method, url, body, timeoutMs = 3000) {
  const r = await bridge("request", [method, url, body === undefined ? "" : JSON.stringify(body)], timeoutMs);
  let data = {};
  try { data = r.text ? JSON.parse(r.text) : {}; } catch { /* not JSON */ }
  return { status: r.status, data };
}

// --- what the phone keeps -----------------------------------------------------------------------

function load(key, fallback) {
  try { return JSON.parse(saved.get(key) || "null") ?? fallback; } catch { return fallback; }
}

/** Called with every good answer of the server: the screens offline show the last ones. */
export function remember(method, path, data) {
  if (method === "GET" && CACHED.some((re) => re.test(path))) saved.set(`local.get:${path}`, JSON.stringify(data));
}

export function cached(path) { return load(`local.get:${path}`, undefined); }

/** The keys for the devices this phone may switch locally (fetched whenever online). */
export async function refreshKeys(api) {
  if (!hasBridge()) return;
  try {
    const r = await api("GET", "/api/platform/my/local-keys");
    saved.set("local.keys", JSON.stringify(r.devices || []));
  } catch { /* keep the old ones until the server answers */ }
}

const keyOf = (deviceId) => load("local.keys", []).find((k) => k.device_id === deviceId) || null;

let found = null;            // device_id -> "host:port" from mDNS, this visit
async function addressOf(entry) {
  if (!found) {
    found = {};
    const r = await bridge("discover", [], 2500);
    try { for (const d of JSON.parse(r.text || "[]")) found[d.device_id] = `${d.host}:${d.port}`; } catch { /* none */ }
  }
  return found[entry.device_id] || (entry.local_addr ? `${entry.local_addr}:${entry.port || 8080}` : null);
}

// --- signed requests to a device ----------------------------------------------------------------

async function signed(entry, path, fields, kind, tag, valueJson) {
  const addr = await addressOf(entry);
  if (!addr) return { status: 0, data: { error: "not_found" } };
  // the device on the home network (plain HTTP inside the house, reached through the native
  // bridge only; the page itself loads nothing from outside)
  const scheme = "http:";
  const base = `${scheme}//${addr}`;
  const n = await lan("GET", `${base}/local/v1/nonce`);
  if (n.status !== 200 || !n.data.nonce) return n;
  const parts = [entry.device_id, n.data.nonce, kind, ...(kind === "command" ? [tag, valueJson] : [])];
  const sig = native().hmac(entry.key, parts.join("\n"));
  return lan("POST", `${base}${path}`, { nonce: n.data.nonce, sig, ...fields });
}

/** A write while offline: straight to the device over the Wi-Fi. */
export async function localWrite(body) {
  const m = /^platform\.devices\.([^.]+)\.([^.]+)$/.exec(body?.tag || "");
  const entry = m && keyOf(m[1]);
  if (!entry) return { result: "rejected_offline", local: true };
  const valueJson = JSON.stringify(body.value);
  const r = await signed(entry, "/local/v1/command", { tag: m[2], value_json: valueJson }, "command", m[2], valueJson);
  if (r.status === 200 && r.data.ok) {
    patchCache(m[1], { [m[2]]: r.data.value });
    return { result: "applied", value: r.data.value, local: true };
  }
  return { result: r.status === 0 ? "rejected_offline" : "failed", local: true, message: r.data.error };
}

/** The values the devices have now (offline), into the kept views. */
export async function localRefresh() {
  for (const entry of load("local.keys", [])) {
    const r = await signed(entry, "/local/v1/state", {}, "state");
    if (r.status === 200 && r.data.values) patchCache(entry.device_id, r.data.values);
  }
}

function patchCache(deviceId, values) {
  for (let i = 0; i < localStorage.length; i++) {
    const k = localStorage.key(i);
    if (!k || !k.startsWith("local.get:/api/platform/my/views")) continue;
    const views = load(k, []);
    for (const v of views) {
      if (v.device.device_id !== deviceId) continue;
      for (const tag of v.tags) if (tag.key in values) tag.value = values[tag.key];
      v.device.state = "online";
    }
    saved.set(k, JSON.stringify(views));
  }
}

/** The answer to a request the server cannot take now; null when there is none offline. */
export async function offlineAnswer(method, path, body) {
  if (method === "POST" && path === "/api/control/write" && hasBridge()) return localWrite(body);
  if (method !== "GET") return null;
  if (hasBridge() && path.startsWith("/api/platform/my/views")) await localRefresh();
  const data = cached(path);
  return data === undefined ? null : data;
}
