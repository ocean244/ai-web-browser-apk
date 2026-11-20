package pl.tomaszewski.aiweb

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.View
import android.view.ViewGroup
import android.webkit.JavascriptInterface
import android.webkit.WebView
import androidx.appcompat.app.AppCompatActivity
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import java.util.concurrent.TimeUnit

class MainActivity : AppCompatActivity() {

    private val mainHandler = Handler(Looper.getMainLooper())

    private val httpClient: OkHttpClient by lazy {
        OkHttpClient.Builder()
            .connectTimeout(10, TimeUnit.SECONDS)
            .readTimeout(45, TimeUnit.SECONDS)
            .writeTimeout(15, TimeUnit.SECONDS)
            .callTimeout(60, TimeUnit.SECONDS)
            .retryOnConnectionFailure(true)
            .build()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        attachBridgeWhenReady()
    }

    override fun onResume() {
        super.onResume()
        attachBridgeWhenReady()
    }

    private fun attachBridgeWhenReady(attempt: Int = 0) {
        val webView = findWebView(window.decorView)
        if (webView != null) {
            webView.settings.javaScriptEnabled = true
            webView.settings.domStorageEnabled = true
            webView.removeJavascriptInterface("AndroidNative")
            webView.addJavascriptInterface(AndroidNative(webView), "AndroidNative")
            return
        }
        if (attempt < 40) {
            mainHandler.postDelayed({ attachBridgeWhenReady(attempt + 1) }, 50L)
        }
    }

    private fun findWebView(root: View?): WebView? {
        if (root == null) return null
        if (root is WebView) return root
        if (root is ViewGroup) {
            for (i in 0 until root.childCount) {
                val found = findWebView(root.getChildAt(i))
                if (found != null) return found
            }
        }
        return null
    }

    inner class AndroidNative(private val webView: WebView) {

        @JavascriptInterface
        fun openExternalUrl(url: String?) {
            val cleanUrl = url?.trim().orEmpty()
            if (cleanUrl.isEmpty()) return
            mainHandler.post {
                try {
                    val uri = Uri.parse(cleanUrl)
                    val scheme = uri.scheme?.lowercase()
                    if (scheme == "http" || scheme == "https") {
                        val intent = Intent(Intent.ACTION_VIEW, uri).apply {
                            addCategory(Intent.CATEGORY_BROWSABLE)
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        startActivity(intent)
                    } else if (cleanUrl.startsWith("file://") || cleanUrl.startsWith("about:")) {
                        webView.loadUrl(cleanUrl)
                    }
                } catch (e: Exception) {
                    emitJsError("openExternalUrl: ${e.message ?: "intent error"}")
                }
            }
        }

        @JavascriptInterface
        fun goBack() {
            mainHandler.post {
                try {
                    if (webView.canGoBack()) {
                        webView.goBack()
                    }
                } catch (e: Exception) {
                    emitJsError("goBack: ${e.message ?: "error"}")
                }
            }
        }

        @JavascriptInterface
        fun goForward() {
            mainHandler.post {
                try {
                    if (webView.canGoForward()) {
                        webView.goForward()
                    }
                } catch (e: Exception) {
                    emitJsError("goForward: ${e.message ?: "error"}")
                }
            }
        }

        @JavascriptInterface
        fun postChatCompletion(
            endpoint: String?,
            model: String?,
            apiKey: String?,
            payloadJson: String?
        ): String {
            val targetUrl = endpoint?.trim().orEmpty()
            if (targetUrl.isEmpty()) {
                return JSONObject().put("error", "Brak endpointu AI").toString()
            }
            val rawBody = payloadJson?.trim().orEmpty()
            if (rawBody.isEmpty()) {
                return JSONObject().put("error", "Pusty ładunek JSON").toString()
            }

            val normalizedBody = try {
                val obj = JSONObject(rawBody)
                if (!model.isNullOrBlank()) {
                    obj.put("model", model.trim())
                }
                obj.toString()
            } catch (e: Exception) {
                return JSONObject().put("error", "Niepoprawny JSON żądania: ${e.message}").toString()
            }

            return try {
                val mediaType = "application/json; charset=utf-8".toMediaType()
                val body = normalizedBody.toRequestBody(mediaType)
                val reqBuilder = Request.Builder()
                    .url(targetUrl)
                    .post(body)
                    .header("Content-Type", "application/json")
                    .header("Accept", "application/json")

                val cleanKey = apiKey?.trim().orEmpty()
                if (cleanKey.isNotEmpty()) {
                    reqBuilder.header("Authorization", "Bearer $cleanKey")
                }

                httpClient.newCall(reqBuilder.build()).execute().use { response ->
                    val responseBody = response.body?.string().orEmpty()
                    if (!response.isSuccessful) {
                        JSONObject()
                            .put("error", "HTTP ${response.code}: ${response.message} ${responseBody.take(400)}")
                            .toString()
                    } else if (responseBody.isBlank()) {
                        JSONObject().put("error", "Pusta odpowiedź z endpointu AI").toString()
                    } else {
                        responseBody
                    }
                }
            } catch (e: Exception) {
                JSONObject()
                    .put("error", "${e.javaClass.simpleName}: ${e.message ?: "błąd połączenia"}")
                    .toString()
            }
        }

        private fun emitJsError(message: String) {
            val escaped = JSONObject.quote("[BRIDGE] $message")
            webView.evaluateJavascript(
                """
                (function() {
                  var out = document.getElementById('aiOutput');
                  if (out) {
                    out.textContent += '\n' + $escaped + '\n';
                    out.scrollTop = out.scrollHeight;
                  }
                })();
                """.trimIndent(),
                null
            )
        }
    }
}
