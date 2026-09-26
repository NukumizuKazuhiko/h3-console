package com.h3.console;

import android.app.Activity;
import android.app.DownloadManager;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.content.pm.ResolveInfo;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.view.Window;
import android.os.Environment;
import android.graphics.Color;
import android.view.KeyEvent;
import android.view.View;
import android.view.WindowManager;
import android.webkit.JavascriptInterface;
import android.webkit.ValueCallback;
import android.webkit.WebChromeClient;
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceResponse;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.Toast;

import androidx.browser.customtabs.CustomTabsIntent;
import androidx.webkit.WebViewAssetLoader;

import org.json.JSONObject;

import com.jcraft.jsch.ChannelExec;
import com.jcraft.jsch.JSch;
import com.jcraft.jsch.Session;

import java.io.ByteArrayOutputStream;
import java.net.URI;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.List;
import java.util.Locale;
import java.util.Properties;

public class MainActivity extends Activity {

    private WebView webView;
    private ValueCallback<Uri[]> filePathCallback;
    private WebViewAssetLoader assetLoader;
    // SSH 隧道会话表（id -> session），无公网转发地区经本地端口转发访问 ComfyUI
    private final java.util.Map<String, Session> tunnels = new java.util.HashMap<>();

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        // 全面屏：内容延伸到状态栏/导航栏/刘海区域，去除黑边
        Window w = getWindow();
        w.setStatusBarColor(Color.TRANSPARENT);
        w.setNavigationBarColor(Color.TRANSPARENT);
        w.getDecorView().setSystemUiVisibility(
                View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                        | View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
                        | View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            WindowManager.LayoutParams lp = w.getAttributes();
            lp.layoutInDisplayCutoutMode = WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES;
            w.setAttributes(lp);
        }
        webView = new WebView(this);
        WebSettings s = webView.getSettings();
        s.setJavaScriptEnabled(true);
        s.setDomStorageEnabled(true);
        s.setAllowFileAccess(true);
        s.setMediaPlaybackRequiresUserGesture(false);
        // 页面以 https://appassets.androidplatform.net 正式源加载（替代 file://）：
        // file:// 的 null 源访问 http://127.0.0.1（SSH 隧道）会被 Chromium 静默拦截为
        // Failed to fetch；https 源访问回环地址属「安全上下文访问可信回环」，可正常 fetch。
        assetLoader = new WebViewAssetLoader.Builder()
                .addPathHandler("/assets/", new WebViewAssetLoader.AssetsPathHandler(this))
                .build();
        webView.setWebViewClient(new WebViewClient() {
            // Private Network Access：页面访问 http://127.0.0.1（SSH 隧道）时的
            // CORS/PNA 预检要求 ACAPN 响应头，ComfyUI 的 --enable-cors-header 不带
            // 该头 → 预检失败 Failed to fetch。这里代答预检响应。
            @Override
            public WebResourceResponse shouldInterceptRequest(WebView view, WebResourceRequest request) {
                Uri u = request.getUrl();
                if ("OPTIONS".equals(request.getMethod()) && u != null
                        && ("127.0.0.1".equals(u.getHost()) || "localhost".equals(u.getHost()))) {
                    java.util.Map<String, String> rh = request.getRequestHeaders();
                    java.util.Map<String, String> h = new java.util.HashMap<>();
                    String origin = rh != null ? rh.get("Origin") : null;
                    h.put("Access-Control-Allow-Origin", origin != null ? origin : "*");
                    String m = rh != null ? rh.get("Access-Control-Request-Method") : null;
                    h.put("Access-Control-Allow-Methods", m != null ? m : "*");
                    String hh = rh != null ? rh.get("Access-Control-Request-Headers") : null;
                    h.put("Access-Control-Allow-Headers", hh != null ? hh : "*");
                    h.put("Access-Control-Allow-Private-Network", "true");
                    h.put("Access-Control-Max-Age", "600");
                    try {
                        return new WebResourceResponse("text/plain", "utf-8", 200, "OK", h,
                                new java.io.ByteArrayInputStream(new byte[0]));
                    } catch (Exception ignored) {}
                }
                return assetLoader.shouldInterceptRequest(request.getUrl());
            }

            // 首次换源启动时自动迁移上一次登录的 token（登录时已存 SharedPreferences）
            @Override
            public void onPageFinished(WebView view, String url) {
                String tk = getSharedPreferences("h3cfg", MODE_PRIVATE).getString("token", "");
                if (!tk.isEmpty()) {
                    view.evaluateJavascript(
                            "if(!localStorage.getItem('h3_dltoken')){ applyToken(" + JSONObject.quote(tk) + "); }",
                            null);
                }
            }
        });
        webView.setWebChromeClient(new WebChromeClient() {
            @Override
            public boolean onShowFileChooser(WebView v, ValueCallback<Uri[]> cb, FileChooserParams params) {
                if (filePathCallback != null) filePathCallback.onReceiveValue(null);
                filePathCallback = cb;
                Intent i = new Intent(Intent.ACTION_GET_CONTENT);
                i.addCategory(Intent.CATEGORY_OPENABLE);
                i.setType("image/*");
                try {
                    startActivityForResult(Intent.createChooser(i, "选择图片"), 9);
                } catch (Exception e) {
                    filePathCallback = null;
                    return false;
                }
                return true;
            }
        });
        webView.setDownloadListener(this::download);
        webView.addJavascriptInterface(new Bridge(), "H3App");
        setContentView(webView);
        webView.loadUrl("https://appassets.androidplatform.net/assets/h3_console.html");
        if (Build.VERSION.SDK_INT <= Build.VERSION_CODES.P &&
                checkSelfPermission("android.permission.WRITE_EXTERNAL_STORAGE") != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(new String[]{"android.permission.WRITE_EXTERNAL_STORAGE"}, 1);
        }
    }

    private class Bridge {
        // debug 签名构建才返回 true（FLAG_DEBUGGABLE），release 自动隐藏调试面板
        @JavascriptInterface
        public boolean isDebug() {
            return (getApplicationInfo().flags & android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE) != 0;
        }

        @JavascriptInterface
        public void openLogin() {
            startActivityForResult(new Intent(MainActivity.this, LoginActivity.class), 7);
        }

        @JavascriptInterface
        public void openUrl(String url) {
            openLink(url);
        }

        @JavascriptInterface
        public void setLightSystemBars(final boolean light) {
            runOnUiThread(() -> {
                View decor = getWindow().getDecorView();
                int vis = decor.getSystemUiVisibility();
                if (light) vis |= View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR;
                else vis &= ~View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR;
                decor.setSystemUiVisibility(vis);
            });
        }

        @JavascriptInterface
        public void copyText(String text) {
            if (text == null || text.isEmpty()) return;
            ClipboardManager cm = (ClipboardManager) getSystemService(Context.CLIPBOARD_SERVICE);
            if (cm != null) {
                cm.setPrimaryClip(ClipData.newPlainText("h3_console", text));
                Toast.makeText(MainActivity.this, "已复制", Toast.LENGTH_SHORT).show();
            }
        }

        // 页面内登出时同步清除持久化 token，避免下次启动 onPageFinished 自动重新注入
        @JavascriptInterface
        public void clearToken() {
            getSharedPreferences("h3cfg", MODE_PRIVATE).edit().remove("token").apply();
        }

        // SSH 单命令执行（新手引导自动部署实例侧组件用）：
        // 后台线程跑完经 evaluateJavascript 回调 window.__sshDone(id, code, output)
        @JavascriptInterface
        public void sshExec(String id, String host, int port, String user, String password, String command) {
            new Thread(() -> {
                int code = -1;
                String out;
                try {
                    JSch jsch = new JSch();
                    Session session = jsch.getSession(user, host, port);
                    session.setPassword(password);
                    Properties cfg = new Properties();
                    cfg.put("StrictHostKeyChecking", "no");
                    session.setConfig(cfg);
                    session.setTimeout(25000);
                    session.connect(25000);
                    ChannelExec ch = (ChannelExec) session.openChannel("exec");
                    ch.setCommand(command);
                    ByteArrayOutputStream bo = new ByteArrayOutputStream();
                    ch.setOutputStream(bo);
                    ch.setErrStream(bo);
                    ch.connect(20000);
                    long deadline = System.currentTimeMillis() + 110000;
                    while (!ch.isClosed() && System.currentTimeMillis() < deadline) {
                        Thread.sleep(200);
                    }
                    code = ch.getExitStatus();
                    ch.disconnect();
                    session.disconnect();
                    out = bo.toString("UTF-8");
                } catch (Exception e) {
                    out = "SSH_ERR: " + e.getMessage();
                }
                final int fCode = code;
                final String fOut = out;
                runOnUiThread(() -> webView.evaluateJavascript(
                        "window.__sshDone && __sshDone(" + JSONObject.quote(id) + "," + fCode + "," + JSONObject.quote(fOut) + ")",
                        null));
            }).start();
        }

        // SSH 本地端口转发：把实例侧 127.0.0.1:remotePort 转发到手机 127.0.0.1:<自动分配端口>，
        // 成功后回调 window.__tunnelDone(id, "<localPort>")，失败回调 __tunnelDone(id, "")
        @JavascriptInterface
        public void sshTunnelOpen(String id, String host, int port, String user, String password, int remotePort) {
            new Thread(() -> {
                String res = "";
                try {
                    JSch jsch = new JSch();
                    Session session = jsch.getSession(user, host, port);
                    session.setPassword(password);
                    Properties cfg = new Properties();
                    cfg.put("StrictHostKeyChecking", "no");
                    session.setConfig(cfg);
                    // 不设 socket 读超时：长连接转发期间靠 keepalive 保活，SO_TIMEOUT 会误杀空闲会话
                    session.setServerAliveInterval(15000);
                    session.connect(25000);
                    int local = session.setPortForwardingL("127.0.0.1", 0, "127.0.0.1", remotePort);
                    synchronized (tunnels) { tunnels.put(id, session); }
                    res = String.valueOf(local);
                } catch (Exception ignored) {}
                final String fRes = res;
                runOnUiThread(() -> webView.evaluateJavascript(
                        "window.__tunnelDone && __tunnelDone(" + JSONObject.quote(id) + "," + JSONObject.quote(fRes) + ")",
                        null));
            }).start();
        }

        @JavascriptInterface
        public void sshTunnelClose(String id) {
            Session s;
            synchronized (tunnels) { s = tunnels.remove(id); }
            if (s != null) {
                try { s.disconnect(); } catch (Exception ignored) {}
            }
        }
    }

    // 原生 App（App Links / Deep Links）→ Chrome Custom Tabs → 系统浏览器
    private void openLink(String url) {
        Uri uri = Uri.parse(url);
        if (uri == null || uri.getScheme() == null) {
            Toast.makeText(this, "无效链接", Toast.LENGTH_SHORT).show();
            return;
        }
        PackageManager pm = getPackageManager();
        Intent base = new Intent(Intent.ACTION_VIEW, uri);
        List<ResolveInfo> acts = pm.queryIntentActivities(base, 0);
        for (ResolveInfo ri : acts) {
            // 浏览器的 intent-filter 对 http/https 不限定 host（authorities=0）；
            // 声明了 App Links / Deep Links 的原生 App 必有具体 host
            if (ri.filter != null && ri.filter.countDataAuthorities() > 0) {
                try {
                    startActivity(new Intent(Intent.ACTION_VIEW, uri).setPackage(ri.activityInfo.packageName));
                    return;
                } catch (Exception ignored) {}
            }
        }
        try {
            new CustomTabsIntent.Builder().setShowTitle(true).build().launchUrl(this, uri);
            return;
        } catch (Exception ignored) {}
        try {
            startActivity(base);
        } catch (Exception e) {
            Toast.makeText(this, "无法打开链接", Toast.LENGTH_SHORT).show();
        }
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (requestCode == 9) {
            Uri[] res = null;
            if (resultCode == RESULT_OK && data != null && data.getData() != null) {
                res = new Uri[]{data.getData()};
            }
            if (filePathCallback != null) {
                filePathCallback.onReceiveValue(res);
                filePathCallback = null;
            }
            return;
        }
        if (requestCode == 7 && resultCode == RESULT_OK && data != null) {
            String t = data.getStringExtra("token");
            if (t != null && !t.isEmpty()) {
                getSharedPreferences("h3cfg", MODE_PRIVATE).edit().putString("token", t).apply();
                webView.evaluateJavascript("applyToken(" + JSONObject.quote(t) + ")", null);
            }
        }
    }

    private void download(String url, String userAgent, String contentDisposition, String mimetype, long contentLength) {
        try {
            String ext = ".mp4";
            try {
                String path = URI.create(url).getPath();
                int dot = path.lastIndexOf('.');
                if (dot >= 0) ext = path.substring(dot);
            } catch (Exception ignored) {}
            String ts = new SimpleDateFormat("yyyyMMdd-HHmmss", Locale.CHINA).format(new Date());
            String name = ts + ext;
            DownloadManager.Request req = new DownloadManager.Request(Uri.parse(url));
            req.setDestinationInExternalPublicDir(Environment.DIRECTORY_PICTURES, "product/" + name);
            req.setTitle(name);
            req.setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED);
            DownloadManager dm = (DownloadManager) getSystemService(DOWNLOAD_SERVICE);
            dm.enqueue(req);
            Toast.makeText(this, "已保存到 Pictures/product/" + name, Toast.LENGTH_SHORT).show();
        } catch (Exception e) {
            Toast.makeText(this, "保存失败：" + e.getMessage(), Toast.LENGTH_LONG).show();
        }
    }

    @Override
    public boolean onKeyDown(int keyCode, KeyEvent event) {
        if (keyCode == KeyEvent.KEYCODE_BACK && webView.canGoBack()) {
            webView.goBack();
            return true;
        }
        return super.onKeyDown(keyCode, event);
    }
}
