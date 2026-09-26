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
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.Toast;

import androidx.browser.customtabs.CustomTabsIntent;

import org.json.JSONObject;

import java.net.URI;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.List;
import java.util.Locale;

public class MainActivity extends Activity {

    private WebView webView;
    private ValueCallback<Uri[]> filePathCallback;

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
        webView.setWebViewClient(new WebViewClient());
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
        webView.loadUrl("file:///android_asset/h3_console.html");
        if (Build.VERSION.SDK_INT <= Build.VERSION_CODES.P &&
                checkSelfPermission("android.permission.WRITE_EXTERNAL_STORAGE") != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(new String[]{"android.permission.WRITE_EXTERNAL_STORAGE"}, 1);
        }
    }

    private class Bridge {
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
