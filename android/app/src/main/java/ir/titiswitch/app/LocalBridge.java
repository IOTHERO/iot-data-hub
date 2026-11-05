package ir.titiswitch.app;

import android.content.Context;
import android.net.Uri;
import android.net.nsd.NsdManager;
import android.net.nsd.NsdServiceInfo;
import android.net.wifi.WifiManager;
import android.os.Handler;
import android.os.Looper;
import android.util.Base64;
import android.webkit.JavascriptInterface;
import android.webkit.WebView;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.InetAddress;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;

/**
 * window.TiTiNative for app/js/local.js: what a web page cannot do itself.
 *
 *  request(id, method, url, body, timeoutMs)  HTTP to a device on the home network only
 *                                              (private IPv4 / IPv6 or a .local name)
 *  discover(id, timeoutMs)                    mDNS: _titiswitch._tcp with TXT id=<device_id>
 *  hmac(key, message)                         HMAC-SHA256, base64url (hub.platform.local_sign)
 *
 * Answers go back through window.__titiDone(id, status, text). Every call is refused unless the
 * WebView shows a page of the configured hub, so a page from elsewhere cannot use the bridge.
 */
final class LocalBridge {
    private static final String SERVICE = "_titiswitch._tcp.";
    private static final int MAX_BODY = 64 * 1024;

    private final MainActivity activity;
    private final WebView web;
    private final ExecutorService pool = Executors.newFixedThreadPool(4);
    private final Handler main = new Handler(Looper.getMainLooper());
    private volatile String pageUrl = "";

    LocalBridge(MainActivity activity, WebView web) {
        this.activity = activity;
        this.web = web;
    }

    void setPageUrl(String url) { pageUrl = url == null ? "" : url; }

    void close() { pool.shutdownNow(); }

    private boolean trusted() { return activity.sameOrigin(Uri.parse(pageUrl)); }

    /** The hub over HTTPS, or a hub on a private address (a test server in the house). */
    static boolean allowedServer(String url) {
        Uri u = Uri.parse(url);
        if ("https".equals(u.getScheme()) && u.getHost() != null) return true;
        return "http".equals(u.getScheme()) && privateHost(u.getHost());
    }

    static boolean privateHost(String host) {
        if (host == null || host.isEmpty()) return false;
        if (host.toLowerCase().endsWith(".local")) return true;
        if (!host.matches("[0-9.]+") && !host.contains(":")) return false;   // literal addresses only
        try {
            InetAddress a = InetAddress.getByName(host);
            return a.isSiteLocalAddress() || a.isLinkLocalAddress()
                    || (a.getAddress().length == 16 && (a.getAddress()[0] & 0xFE) == 0xFC);   // fc00::/7
        } catch (Exception e) {
            return false;
        }
    }

    private void done(String id, int status, String text) {
        String js = "window.__titiDone(" + JSONObject.quote(id) + "," + status + ","
                + JSONObject.quote(text == null ? "" : text) + ")";
        main.post(() -> web.evaluateJavascript(js, null));
    }

    @JavascriptInterface
    public void request(String id, String method, String url, String body, int timeoutMs) {
        if (!trusted()) { done(id, 0, ""); return; }
        pool.execute(() -> {
            HttpURLConnection c = null;
            try {
                URL u = new URL(url);
                if (!"http".equals(u.getProtocol()) || !privateHost(u.getHost())) {
                    done(id, 0, "");                 // only devices inside the house
                    return;
                }
                c = (HttpURLConnection) u.openConnection();
                c.setInstanceFollowRedirects(false);
                c.setConnectTimeout(Math.min(timeoutMs, 5000));
                c.setReadTimeout(Math.min(timeoutMs, 5000));
                c.setRequestMethod("POST".equals(method) ? "POST" : "GET");
                if (body != null && !body.isEmpty()) {
                    byte[] data = body.getBytes(StandardCharsets.UTF_8);
                    c.setDoOutput(true);
                    c.setRequestProperty("Content-Type", "application/json");
                    c.setFixedLengthStreamingMode(data.length);
                    try (OutputStream out = c.getOutputStream()) { out.write(data); }
                }
                int status = c.getResponseCode();
                InputStream in = status >= 400 ? c.getErrorStream() : c.getInputStream();
                done(id, status, read(in));
            } catch (Exception e) {
                done(id, 0, "");
            } finally {
                if (c != null) c.disconnect();
            }
        });
    }

    private static String read(InputStream in) throws Exception {
        if (in == null) return "";
        ByteArrayOutputStream buf = new ByteArrayOutputStream();
        byte[] chunk = new byte[4096];
        int n;
        while ((n = in.read(chunk)) > 0 && buf.size() < MAX_BODY) buf.write(chunk, 0, n);
        in.close();
        return buf.toString("UTF-8");
    }

    @JavascriptInterface
    public void discover(String id, int timeoutMs) {
        if (!trusted()) { done(id, 0, "[]"); return; }
        main.post(() -> new Discovery(id, timeoutMs).start());
    }

    @JavascriptInterface
    public String hmac(String key, String message) {
        if (!trusted()) return "";
        try {
            byte[] k = Base64.decode(key, Base64.URL_SAFE | Base64.NO_PADDING | Base64.NO_WRAP);
            Mac mac = Mac.getInstance("HmacSHA256");
            mac.init(new SecretKeySpec(k, "HmacSHA256"));
            byte[] sig = mac.doFinal(message.getBytes(StandardCharsets.UTF_8));
            return Base64.encodeToString(sig, Base64.URL_SAFE | Base64.NO_PADDING | Base64.NO_WRAP);
        } catch (Exception e) {
            return "";
        }
    }

    /** One mDNS browse: every _titiswitch._tcp service found within the time, resolved. */
    private final class Discovery implements NsdManager.DiscoveryListener {
        private final String id;
        private final int timeoutMs;
        private final NsdManager nsd = (NsdManager) activity.getSystemService(Context.NSD_SERVICE);
        private final JSONArray found = new JSONArray();
        private WifiManager.MulticastLock lock;
        private boolean finished;

        Discovery(String id, int timeoutMs) {
            this.id = id;
            this.timeoutMs = timeoutMs;
        }

        void start() {
            WifiManager wifi = (WifiManager) activity.getApplicationContext()
                    .getSystemService(Context.WIFI_SERVICE);
            if (wifi != null) {
                lock = wifi.createMulticastLock("titiswitch-discovery");
                lock.setReferenceCounted(false);
                lock.acquire();
            }
            try {
                nsd.discoverServices(SERVICE, NsdManager.PROTOCOL_DNS_SD, this);
            } catch (Exception e) {
                finish();
                return;
            }
            main.postDelayed(this::finish, timeoutMs);
        }

        synchronized void finish() {
            if (finished) return;
            finished = true;
            try { nsd.stopServiceDiscovery(this); } catch (Exception ignored) { }
            if (lock != null && lock.isHeld()) lock.release();
            done(id, 200, found.toString());
        }

        @Override
        public void onServiceFound(NsdServiceInfo info) {
            nsd.resolveService(info, new NsdManager.ResolveListener() {
                @Override
                public void onResolveFailed(NsdServiceInfo i, int error) { }

                @Override
                public void onServiceResolved(NsdServiceInfo i) {
                    try {
                        Map<String, byte[]> txt = i.getAttributes();
                        byte[] device = txt.get("id");
                        if (device == null || i.getHost() == null) return;
                        String host = i.getHost().getHostAddress();
                        if (!privateHost(host)) return;
                        JSONObject o = new JSONObject();
                        o.put("device_id", new String(device, StandardCharsets.UTF_8));
                        o.put("host", host.contains(":") ? "[" + host + "]" : host);
                        o.put("port", i.getPort());
                        synchronized (Discovery.this) { if (!finished) found.put(o); }
                    } catch (Exception ignored) { }
                }
            });
        }

        @Override public void onServiceLost(NsdServiceInfo info) { }
        @Override public void onDiscoveryStarted(String type) { }
        @Override public void onDiscoveryStopped(String type) { }
        @Override public void onStartDiscoveryFailed(String type, int error) { main.post(this::finish); }
        @Override public void onStopDiscoveryFailed(String type, int error) { }
    }
}
