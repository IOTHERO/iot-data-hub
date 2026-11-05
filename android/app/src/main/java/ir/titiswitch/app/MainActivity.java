package ir.titiswitch.app;

import android.Manifest;
import android.app.Activity;
import android.app.AlertDialog;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.Bundle;
import android.text.InputType;
import android.view.View;
import android.webkit.PermissionRequest;
import android.webkit.WebChromeClient;
import android.webkit.WebResourceRequest;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.EditText;
import android.widget.Toast;

/**
 * The customer app: the hub's web app (/app/) in a WebView, so every screen, translation and
 * update comes from the server and matches the web version on iPhone. Native parts only where a
 * web page cannot do it: the local bridge (switching devices over the home Wi-Fi while the
 * internet is down) and the camera permission for scanning QR labels.
 *
 * The page works offline from its service-worker cache once it has been opened online. Links to
 * other sites open in the phone's browser; the bridge answers only pages of the hub itself.
 */
public class MainActivity extends Activity {
    private static final String PREFS = "titiswitch";
    private static final String KEY_SERVER = "server_url";
    private static final int CAMERA_REQUEST = 7;

    private WebView web;
    private LocalBridge bridge;
    private PermissionRequest pendingCamera;

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        web = new WebView(this);
        web.setBackgroundColor(0xFF0B0D12);
        setContentView(web);

        WebSettings s = web.getSettings();
        s.setJavaScriptEnabled(true);
        s.setDomStorageEnabled(true);           // the app keeps its session and offline data
        s.setDatabaseEnabled(true);
        s.setMediaPlaybackRequiresUserGesture(false);
        s.setAllowFileAccess(false);
        s.setAllowContentAccess(false);
        s.setUserAgentString(s.getUserAgentString() + " TiTiSwitchApp/" + BuildConfig.VERSION_NAME);

        bridge = new LocalBridge(this, web);
        web.addJavascriptInterface(bridge, "TiTiNative");
        web.setWebViewClient(new WebViewClient() {
            @Override
            public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
                Uri uri = request.getUrl();
                if (sameOrigin(uri)) return false;
                if ("tel".equals(uri.getScheme()) || "sms".equals(uri.getScheme())
                        || "http".equals(uri.getScheme()) || "https".equals(uri.getScheme())) {
                    startActivity(new Intent(Intent.ACTION_VIEW, uri));   // the phone dials, the browser opens
                }
                return true;
            }

            @Override
            public void onPageStarted(WebView view, String url, android.graphics.Bitmap favicon) {
                bridge.setPageUrl(url);
            }
        });
        web.setWebChromeClient(new WebChromeClient() {
            @Override
            public void onPermissionRequest(PermissionRequest request) {
                if (!sameOrigin(request.getOrigin())) { request.deny(); return; }
                for (String r : request.getResources()) {
                    if (!PermissionRequest.RESOURCE_VIDEO_CAPTURE.equals(r)) { request.deny(); return; }
                }
                if (checkSelfPermission(Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) {
                    request.grant(request.getResources());
                } else {
                    pendingCamera = request;
                    requestPermissions(new String[]{Manifest.permission.CAMERA}, CAMERA_REQUEST);
                }
            }
        });
        String server = server();
        if (server.isEmpty()) askServer(true);
        else web.loadUrl(server);
    }

    String server() {
        SharedPreferences p = getSharedPreferences(PREFS, MODE_PRIVATE);
        return p.getString(KEY_SERVER, BuildConfig.SERVER_URL);
    }

    boolean sameOrigin(Uri uri) {
        if (uri == null) return false;
        Uri home = Uri.parse(server());
        return home.getScheme() != null && home.getScheme().equals(uri.getScheme())
                && home.getHost() != null && home.getHost().equalsIgnoreCase(uri.getHost())
                && home.getPort() == uri.getPort();
    }

    /** First start (no address built in) or the user asked to change it. */
    void askServer(boolean first) {
        EditText input = new EditText(this);
        input.setInputType(InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_URI);
        input.setHint(R.string.server_hint);
        input.setText(server());
        input.setTextDirection(View.TEXT_DIRECTION_LTR);
        AlertDialog.Builder b = new AlertDialog.Builder(this)
                .setTitle(R.string.server_title)
                .setView(input)
                .setCancelable(!first)
                .setPositiveButton(R.string.ok, (d, w) -> {
                    String url = input.getText().toString().trim();
                    if (!url.endsWith("/")) url += "/";
                    if (!LocalBridge.allowedServer(url)) {
                        Toast.makeText(this, R.string.server_bad, Toast.LENGTH_LONG).show();
                        askServer(first);
                        return;
                    }
                    getSharedPreferences(PREFS, MODE_PRIVATE).edit().putString(KEY_SERVER, url).apply();
                    web.loadUrl(url);
                });
        if (!first) b.setNegativeButton(R.string.cancel, null);
        b.show();
    }

    @Override
    public void onRequestPermissionsResult(int code, String[] permissions, int[] results) {
        if (code == CAMERA_REQUEST && pendingCamera != null) {
            if (results.length > 0 && results[0] == PackageManager.PERMISSION_GRANTED) {
                pendingCamera.grant(pendingCamera.getResources());
            } else {
                pendingCamera.deny();
            }
            pendingCamera = null;
        }
    }

    // back: the page's own history; a long press on back changes the server address
    @Override
    public boolean onKeyDown(int keyCode, android.view.KeyEvent event) {
        if (keyCode == android.view.KeyEvent.KEYCODE_BACK) {
            event.startTracking();
            return true;
        }
        return super.onKeyDown(keyCode, event);
    }

    @Override
    public boolean onKeyLongPress(int keyCode, android.view.KeyEvent event) {
        if (keyCode == android.view.KeyEvent.KEYCODE_BACK) {
            askServer(false);
            return true;
        }
        return super.onKeyLongPress(keyCode, event);
    }

    @Override
    public boolean onKeyUp(int keyCode, android.view.KeyEvent event) {
        if (keyCode == android.view.KeyEvent.KEYCODE_BACK && event.isTracking() && !event.isCanceled()) {
            if (web.canGoBack()) web.goBack();
            else finish();
            return true;
        }
        return super.onKeyUp(keyCode, event);
    }

    @Override
    protected void onDestroy() {
        bridge.close();
        web.destroy();
        super.onDestroy();
    }
}
