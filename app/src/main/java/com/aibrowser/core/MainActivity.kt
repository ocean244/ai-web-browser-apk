package com.aibrowser.core
import android.os.Message
import android.webkit.CookieManager

import android.annotation.SuppressLint
import android.os.Bundle
import android.webkit.JavascriptInterface
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.appcompat.app.AppCompatActivity
import org.json.JSONArray
import org.json.JSONObject
import java.io.BufferedReader
import java.io.InputStreamReader
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import java.util.concurrent.Executors

class MainActivity : AppCompatActivity() {

    private lateinit var webView: WebView
    private val ioExecutor = Executors.newCachedThreadPool()

    @SuppressLint("SetJavaScriptEnabled")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        webView = WebView(this)
        configureAuthResilientWebView(webView)
        setContentView(webView)

        val settings = webView.settings
        settings.javaScriptEnabled = true
        settings.domStorageEnabled = true
        settings.databaseEnabled = true
        settings.allowFileAccess = true
        settings.allowContentAccess = true
        @Suppress("DEPRECATION")
        settings.allowFileAccessFromFileURLs = true
        @Suppress("DEPRECATION")
        settings.allowUniversalAccessFromFileURLs = true
        settings.mixedContentMode = WebSettings.MIXED_CONTENT_ALWAYS_ALLOW
        settings.useWideViewPort = true
        settings.loadWithOverviewMode = true

        webView.webChromeClient = WebChromeClient()
        webView.webViewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(view: WebView?, request: WebResourceRequest?): Boolean {
                val raw = request?.url?.toString() ?: return false
                val cleaned = sanitizeUrl(raw)
                if (cleaned != raw) {
                    view?.loadUrl(cleaned)
                    return true
                }
                if (cleaned.startsWith("file://") || cleaned.startsWith("http://") || cleaned.startsWith("https://")) {
                    return false
                }
                return true
            }
        }

        webView.addJavascriptInterface(AndroidNativeBridge(), "AndroidNative")
        webView.loadUrl("file:///android_asset/index.html")
    }

    private fun sanitizeUrl(raw: String): String {
        val trimmed = raw.trim()
        return when {
            trimmed.startsWith("https://file:///") -> trimmed.removePrefix("https://")
            trimmed.startsWith("http://file:///") -> trimmed.removePrefix("http://")
            else -> trimmed
        }
    }

    private fun pushDeltaToJs(deltaText: String) {
        val escaped = JSONObject.quote(deltaText)
        runOnUiThread {
            webView.evaluateJavascript("if (window.__onNativeStreamDelta) window.__onNativeStreamDelta(" + escaped + ");", null)
        }
    }

    inner class AndroidNativeBridge {

        @JavascriptInterface
        fun openUrl(url: String) {
            val target = sanitizeUrl(url)
            runOnUiThread {
                if (target.startsWith("file://") || target.startsWith("http://") || target.startsWith("https://")) {
                    webView.loadUrl(target)
                } else if (target.contains(".") && !target.contains(" ")) {
                    webView.loadUrl("https://$target")
                } else {
                    val q = URLEncoder.encode(target, "UTF-8")
                    webView.loadUrl("https://duckduckgo.com/?q=$q")
                }
            }
        }

        @JavascriptInterface
        fun chatCompletion(
            endpoint: String,
            model: String,
            apiKey: String,
            messagesJson: String,
            streamMode: Boolean
        ): String {
            return try {
                val messagesArray = JSONArray(messagesJson)
                val payload = JSONObject().apply {
                    put("model", model.ifBlank { "Qwen2.5-3B-Instruct-Abliterated.Q4_K_M.gguf" })
                    put("messages", messagesArray)
                    put("stream", streamMode)
                }

                val conn = (URL(endpoint).openConnection() as HttpURLConnection).apply {
                    requestMethod = "POST"
                    connectTimeout = 10000
                    readTimeout = 60000
                    doOutput = true
                    setRequestProperty("Content-Type", "application/json; charset=UTF-8")
                    if (apiKey.isNotBlank()) {
                        setRequestProperty("Authorization", "Bearer $apiKey")
                    }
                }

                OutputStreamWriter(conn.outputStream, Charsets.UTF_8).use { writer ->
                    writer.write(payload.toString())
                    writer.flush()
                }

                val code = conn.responseCode
                if (code !in 200..299) {
                    val errText = conn.errorStream?.bufferedReader(Charsets.UTF_8)?.use { it.readText() } ?: ""
                    conn.disconnect()
                    return JSONObject().apply {
                        put("ok", false)
                        put("status", code)
                        put("error", "HTTP $code")
                        put("raw", errText)
                    }.toString(2)
                }

                if (!streamMode) {
                    val rawBody = conn.inputStream.bufferedReader(Charsets.UTF_8).use { it.readText() }
                    conn.disconnect()
                    val json = JSONObject(rawBody)
                    val content = json.optJSONArray("choices")
                        ?.optJSONObject(0)
                        ?.optJSONObject("message")
                        ?.optString("content")
                    return if (!content.isNullOrEmpty()) content else json.toString(2)
                }

                val acc = StringBuilder()
                BufferedReader(InputStreamReader(conn.inputStream, Charsets.UTF_8)).use { reader ->
                    while (true) {
                        val line = reader.readLine() ?: break
                        val trimmed = line.trim()
                        if (!trimmed.startsWith("data:")) continue
                        val dataPart = trimmed.removePrefix("data:").trim()
                        if (dataPart == "[DONE]") break
                        try {
                            val chunk = JSONObject(dataPart)
                            val delta = chunk.optJSONArray("choices")
                                ?.optJSONObject(0)
                                ?.optJSONObject("delta")
                                ?.optString("content")
                            if (!delta.isNullOrEmpty() && delta != "null") {
                                acc.append(delta)
                                pushDeltaToJs(acc.toString())
                            }
                        } catch (_: Exception) {}
                    }
                }
                conn.disconnect()
                acc.toString().ifEmpty { "(brak treści w strumieniu SSE)" }
            } catch (ex: Exception) {
                JSONObject().apply {
                    put("ok", false)
                    put("error", ex.message ?: ex.javaClass.simpleName)
                }.toString(2)
            }
        }

        @JavascriptInterface
        fun searchWeb(query: String): String {
            return try {
                val encoded = URLEncoder.encode(query, "UTF-8")
                val apiUrl = "https://api.duckduckgo.com/?q=$encoded&format=json&no_html=1"
                val conn = (URL(apiUrl).openConnection() as HttpURLConnection).apply {
                    requestMethod = "GET"
                    connectTimeout = 10000
                    readTimeout = 15000
                }
                val text = BufferedReader(InputStreamReader(conn.inputStream, Charsets.UTF_8)).use { it.readText() }
                conn.disconnect()

                val root = JSONObject(text)
                val out = JSONArray()
                val abstractUrl = root.optString("AbstractURL")
                val heading = root.optString("Heading").ifBlank { query }
                if (abstractUrl.isNotBlank()) {
                    out.put(JSONObject().apply {
                        put("title", heading)
                        put("url", abstractUrl)
                    })
                }
                val related = root.optJSONArray("RelatedTopics")
                if (related != null) {
                    for (i in 0 until related.length()) {
                        val item = related.optJSONObject(i) ?: continue
                        val u = item.optString("FirstURL")
                        val t = item.optString("Text")
                        if (u.isNotBlank() && t.isNotBlank()) {
                            out.put(JSONObject().apply {
                                put("title", t)
                                put("url", u)
                            })
                        }
                    }
                }
                if (out.length() == 0) {
                    out.put(JSONObject().apply {
                        put("title", "Szukaj w DuckDuckGo: $query")
                        put("url", "https://duckduckgo.com/?q=$encoded")
                    })
                }
                out.toString()
            } catch (_: Exception) {
                val encoded = URLEncoder.encode(query, "UTF-8")
                JSONArray().put(JSONObject().apply {
                    put("title", "Szukaj w DuckDuckGo: $query")
                    put("url", "https://duckduckgo.com/?q=$encoded")
                }).toString()
            }
        }
    }

    override fun onDestroy() {
        ioExecutor.shutdownNow()
        super.onDestroy()
    }

    private fun authStateResilienceJs(): String = """
        (function() {
          try {
            if (window.__authStateBridgeInstalled) return;
            window.__authStateBridgeInstalled = true;
            var PREFIX = "__ai_auth_state__:";
            function writeCookie(k, v) {
              try {
                if (!v || v.length > 3500) return;
                document.cookie = encodeURIComponent(PREFIX + k) + "=" + encodeURIComponent(v) + "; path=/; max-age=1800; SameSite=Lax";
              } catch (_) {}
            }
            function readCookie(k) {
              try {
                var target = encodeURIComponent(PREFIX + k) + "=";
                var parts = (document.cookie || "").split(";");
                for (var i = 0; i < parts.length; i++) {
                  var c = parts[i].trim();
                  if (c.indexOf(target) === 0) {
                    return decodeURIComponent(c.substring(target.length));
                  }
                }
              } catch (_) {}
              return null;
            }
            var mem = {};
            var origSetItem = Storage.prototype.setItem;
            var origGetItem = Storage.prototype.getItem;
            var origRemoveItem = Storage.prototype.removeItem;
            Storage.prototype.setItem = function(k, v) {
              var sKey = String(k);
              var sVal = String(v);
              mem[sKey] = sVal;
              try { origSetItem.call(this, sKey, sVal); } catch (_) {}
              try { if (this === window.sessionStorage) { window.localStorage.setItem(PREFIX + sKey, sVal); writeCookie(sKey, sVal); } } catch (_) {}
            };
            Storage.prototype.getItem = function(k) {
              var sKey = String(k);
              try {
                var direct = origGetItem.call(this, sKey);
                if (direct !== null && direct !== undefined) return direct;
              } catch (_) {}
              if (this === window.sessionStorage) {
                try {
                  var ls = window.localStorage.getItem(PREFIX + sKey);
                  if (ls !== null && ls !== undefined) return ls;
                } catch (_) {}
                var ck = readCookie(sKey);
                if (ck !== null && ck !== undefined) return ck;
              }
              return Object.prototype.hasOwnProperty.call(mem, sKey) ? mem[sKey] : null;
            };
            Storage.prototype.removeItem = function(k) {
              var sKey = String(k);
              delete mem[sKey];
              try { origRemoveItem.call(this, sKey); } catch (_) {}
              try { if (this === window.sessionStorage) { window.localStorage.removeItem(PREFIX + sKey); } } catch (_) {}
            };
            try {
              for (var i = 0; i < window.localStorage.length; i++) {
                var lk = window.localStorage.key(i);
                if (lk && lk.indexOf(PREFIX) === 0) {
                  var realK = lk.substring(PREFIX.length);
                  var lv = window.localStorage.getItem(lk);
                  if (lv !== null && window.sessionStorage.getItem(realK) === null) {
                    origSetItem.call(window.sessionStorage, realK, lv);
                  }
                }
              }
            } catch (_) {}
          } catch (_) {}
        })();
    """.trimIndent()

    private fun configureAuthResilientWebView(targetWebView: WebView) {
        val cookieManager = CookieManager.getInstance()
        cookieManager.setAcceptCookie(true)
        cookieManager.setAcceptThirdPartyCookies(targetWebView, true)
        cookieManager.flush()

        targetWebView.settings.apply {
            javaScriptEnabled = true
            domStorageEnabled = true
            databaseEnabled = true
            javaScriptCanOpenWindowsAutomatically = true
            setSupportMultipleWindows(true)
            mixedContentMode = WebSettings.MIXED_CONTENT_ALWAYS_ALLOW
            cacheMode = WebSettings.LOAD_DEFAULT
        }

        targetWebView.webChromeClient = object : WebChromeClient() {
            override fun onCreateWindow(
                view: WebView?,
                isDialog: Boolean,
                isUserGesture: Boolean,
                resultMsg: Message?
            ): Boolean {
                val transport = resultMsg?.obj as? WebView.WebViewTransport ?: return false
                val popupTarget = view ?: targetWebView
                transport.webView = popupTarget
                resultMsg.sendToTarget()
                return true
            }
        }
    }

}
