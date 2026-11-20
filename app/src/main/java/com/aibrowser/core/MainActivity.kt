package com.aibrowser.core

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
}
