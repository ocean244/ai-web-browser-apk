package pl.tomaszewski.aiweb

import android.annotation.SuppressLint
import android.content.Intent
import android.graphics.Color
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.text.InputType
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.inputmethod.EditorInfo
import android.webkit.JavascriptInterface
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.Button
import android.widget.EditText
import android.widget.HorizontalScrollView
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import java.util.concurrent.TimeUnit

class MainActivity : AppCompatActivity() {

    private val mainHandler = Handler(Looper.getMainLooper())
    private val ioHandler = android.os.HandlerThread("AiBridgeIoThread").apply { start() }
    private val bgHandler = Handler(ioHandler.looper)

    private lateinit var webView: WebView
    private lateinit var urlInput: EditText
    private lateinit var statusText: TextView
    private lateinit var aiPromptInput: EditText
    private lateinit var aiOutputView: TextView

    private val defaultHomeHtml: String by lazy {
        """
        <!DOCTYPE html>
        <html lang="pl">
        <head>
          <meta charset="UTF-8" />
          <meta name="viewport" content="width=device-width, initial-scale=1.0" />
          <title>AI Web Browser</title>
          <style>
            body {
              margin: 0;
              padding: 18px;
              background: #0e1117;
              color: #e6edf3;
              font-family: sans-serif;
              line-height: 1.5;
            }
            .card {
              background: #161b22;
              border: 1px solid #30363d;
              border-radius: 10px;
              padding: 16px;
              margin-bottom: 14px;
            }
            h1 { margin: 0 0 8px 0; font-size: 20px; color: #58a6ff; }
            code { background: #21262d; padding: 2px 6px; border-radius: 4px; }
            button {
              background: #238636;
              color: #ffffff;
              border: none;
              border-radius: 8px;
              padding: 10px 14px;
              font-size: 14px;
              margin-right: 8px;
              margin-top: 8px;
            }
            #aiOutput {
              white-space: pre-wrap;
              background: #0b0e14;
              border: 1px solid #262c36;
              border-radius: 8px;
              padding: 12px;
              min-height: 90px;
              margin-top: 10px;
              font-family: monospace;
              font-size: 12px;
            }
          </style>
        </head>
        <body>
          <div class="card">
            <h1>AI Web Browser — Aktywny</h1>
            <div>Mostek natywny: <strong id="bridgeStatus">sprawdzanie...</strong></div>
            <button onclick="runBridgePing()">Test AndroidNative</button>
            <button onclick="openSampleSite()">Otwórz example.com</button>
            <div id="aiOutput">Gotowy do pracy.</div>
          </div>
          <script>
            (function initPage() {
              var el = document.getElementById('bridgeStatus');
              if (el) {
                el.textContent = (window.AndroidNative && typeof window.AndroidNative.postChatCompletion === 'function')
                  ? 'AKTYWNY (AndroidNative)'
                  : 'BRAK MOSTKA';
              }
            })();
            function appendOut(msg) {
              var out = document.getElementById('aiOutput');
              if (out) {
                out.textContent += '\n' + msg;
                out.scrollTop = out.scrollHeight;
              }
            }
            function runBridgePing() {
              if (!window.AndroidNative) {
                appendOut('[ERR] window.AndroidNative niedostępny');
                return;
              }
              var res = window.AndroidNative.postChatCompletion('', '', '', '');
              appendOut('[PING] ' + res);
            }
            function openSampleSite() {
              if (window.AndroidNative && typeof window.AndroidNative.openExternalUrl === 'function') {
                window.AndroidNative.openExternalUrl('https://example.com');
              } else {
                window.location.href = 'https://example.com';
              }
            }
          </script>
        </body>
        </html>
        """.trimIndent()
    }

    private val httpClient: OkHttpClient by lazy {
        OkHttpClient.Builder()
            .connectTimeout(10, TimeUnit.SECONDS)
            .readTimeout(45, TimeUnit.SECONDS)
            .writeTimeout(15, TimeUnit.SECONDS)
            .callTimeout(60, TimeUnit.SECONDS)
            .retryOnConnectionFailure(true)
            .build()
    }

    @SuppressLint("SetJavaScriptEnabled")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        buildUserInterface()
        setupWebView()
        webView.loadDataWithBaseURL(
            "https://app.local/",
            defaultHomeHtml,
            "text/html",
            "UTF-8",
            null
        )
    }

    override fun onResume() {
        super.onResume()
        if (::webView.isInitialized) {
            attachBridge(webView)
            webView.onResume()
        }
    }

    override fun onPause() {
        if (::webView.isInitialized) {
            webView.onPause()
        }
        super.onPause()
    }

    override fun onDestroy() {
        if (::webView.isInitialized) {
            webView.removeJavascriptInterface("AndroidNative")
            webView.destroy()
        }
        ioHandler.quitSafely()
        super.onDestroy()
    }

    private fun buildUserInterface() {
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(Color.parseColor("#0E1117"))
            layoutParams = ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
            setPadding(16, 48, 16, 16)
        }

        val navRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            )
        }

        fun makeBtn(label: String, onClick: () -> Unit): Button = Button(this).apply {
            text = label
            setTextColor(Color.WHITE)
            setBackgroundColor(Color.parseColor("#21262D"))
            setPadding(18, 10, 18, 10)
            val lp = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            ).apply {
                marginEnd = 8
            }
            layoutParams = lp
            setOnClickListener { onClick() }
        }

        val btnBack = makeBtn("<") {
            if (webView.canGoBack()) webView.goBack()
        }
        val btnFwd = makeBtn(">") {
            if (webView.canGoForward()) webView.goForward()
        }
        val btnHome = makeBtn("Home") {
            webView.loadDataWithBaseURL(
                "https://app.local/",
                defaultHomeHtml,
                "text/html",
                "UTF-8",
                null
            )
        }

        urlInput = EditText(this).apply {
            hint = "https://..."
            setText("https://example.com")
            setTextColor(Color.WHITE)
            setHintTextColor(Color.parseColor("#8B949E"))
            setBackgroundColor(Color.parseColor("#161B22"))
            setPadding(16, 12, 16, 12)
            inputType = InputType.TYPE_TEXT_VARIATION_URI
            imeOptions = EditorInfo.IME_ACTION_GO
            layoutParams = LinearLayout.LayoutParams(
                0,
                ViewGroup.LayoutParams.WRAP_CONTENT,
                1f
            ).apply {
                marginEnd = 8
            }
            setOnEditorActionListener { _, actionId, _ ->
                if (actionId == EditorInfo.IME_ACTION_GO || actionId == EditorInfo.IME_ACTION_DONE) {
                    navigateTo(text.toString())
                    true
                } else {
                    false
                }
            }
        }

        val btnGo = makeBtn("Idź") {
            navigateTo(urlInput.text.toString())
        }

        navRow.addView(btnBack)
        navRow.addView(btnFwd)
        navRow.addView(btnHome)
        navRow.addView(urlInput)
        navRow.addView(btnGo)

        statusText = TextView(this).apply {
            text = "Status: GOTOWY | Bridge: AndroidNative"
            setTextColor(Color.parseColor("#58A6FF"))
            textSize = 12f
            setPadding(4, 10, 4, 8)
        }

        webView = WebView(this).apply {
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                0,
                1f
            )
            setBackgroundColor(Color.parseColor("#0E1117"))
        }

        val aiPanel = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(Color.parseColor("#161B22"))
            setPadding(14, 14, 14, 14)
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            ).apply {
                topMargin = 10
            }
        }

        val aiRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            )
        }

        aiPromptInput = EditText(this).apply {
            hint = "Prompt JSON lub tekst testowy..."
            setText("""{"messages":[{"role":"user","content":"ping"}]}""")
            setTextColor(Color.WHITE)
            setHintTextColor(Color.parseColor("#8B949E"))
            setBackgroundColor(Color.parseColor("#0D1117"))
            setPadding(14, 10, 14, 10)
            layoutParams = LinearLayout.LayoutParams(
                0,
                ViewGroup.LayoutParams.WRAP_CONTENT,
                1f
            ).apply {
                marginEnd = 8
            }
        }

        val btnTestBridge = Button(this).apply {
            text = "Test AI"
            setTextColor(Color.WHITE)
            setBackgroundColor(Color.parseColor("#238636"))
            setPadding(16, 10, 16, 10)
            setOnClickListener {
                val prompt = aiPromptInput.text.toString()
                bgHandler.post {
                    val result = AndroidNative(webView).postChatCompletion(
                        "",
                        "",
                        "",
                        prompt
                    )
                    mainHandler.post {
                        aiOutputView.append("\n[TEST] $result")
                        statusText.text = "Status: BRIDGE_OK"
                    }
                }
            }
        }

        aiRow.addView(aiPromptInput)
        aiRow.addView(btnTestBridge)

        val scrollOut = ScrollView(this).apply {
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                220
            ).apply {
                topMargin = 8
            }
        }

        aiOutputView = TextView(this).apply {
            text = "[INIT] Aktywność uruchomiona i widoczna."
            setTextColor(Color.parseColor("#C9D1D9"))
            setBackgroundColor(Color.parseColor("#0B0E14"))
            setPadding(12, 10, 12, 10)
            textSize = 12f
            layoutParams = ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            )
        }

        scrollOut.addView(aiOutputView)
        aiPanel.addView(aiRow)
        aiPanel.addView(scrollOut)

        root.addView(navRow)
        root.addView(statusText)
        root.addView(webView)
        root.addView(aiPanel)

        setContentView(root)
    }

    @SuppressLint("SetJavaScriptEnabled")
    private fun setupWebView() {
        webView.settings.apply {
            javaScriptEnabled = true
            domStorageEnabled = true
            databaseEnabled = true
            cacheMode = WebSettings.LOAD_DEFAULT
            mixedContentMode = WebSettings.MIXED_CONTENT_COMPATIBILITY_MODE
            userAgentString = "$userAgentString AiWebBrowser/1.1"
        }
        attachBridge(webView)

        webView.webChromeClient = object : WebChromeClient() {
            override fun onProgressChanged(view: WebView?, newProgress: Int) {
                super.onProgressChanged(view, newProgress)
                mainHandler.post {
                    statusText.text = "Status: Ładowanie ${newProgress}% | Bridge: AndroidNative"
                }
            }
        }

        webView.webViewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(
                view: WebView?,
                request: WebResourceRequest?
            ): Boolean {
                val target = request?.url?.toString().orEmpty()
                if (target.startsWith("http://") || target.startsWith("https://")) {
                    mainHandler.post { urlInput.setText(target) }
                    return false
                }
                return false
            }

            override fun onPageFinished(view: WebView?, url: String?) {
                super.onPageFinished(view, url)
                mainHandler.post {
                    val current = url.orEmpty()
                    if (current.isNotEmpty() && !current.startsWith("data:")) {
                        urlInput.setText(current)
                    }
                    statusText.text = "Status: ZAŁADOWANO | Bridge: AndroidNative"
                }
            }
        }
    }

    @SuppressLint("SetJavaScriptEnabled")
    private fun attachBridge(targetWebView: WebView) {
        targetWebView.settings.javaScriptEnabled = true
        targetWebView.settings.domStorageEnabled = true
        targetWebView.removeJavascriptInterface("AndroidNative")
        targetWebView.addJavascriptInterface(AndroidNative(targetWebView), "AndroidNative")
    }

    private fun navigateTo(rawInput: String) {
        val trimmed = rawInput.trim()
        if (trimmed.isEmpty()) return
        val normalized = if (
            trimmed.startsWith("http://", ignoreCase = true) ||
            trimmed.startsWith("https://", ignoreCase = true) ||
            trimmed.startsWith("file://", ignoreCase = true) ||
            trimmed.startsWith("about:", ignoreCase = true)
        ) {
            trimmed
        } else if (trimmed.contains(".") && !trimmed.contains(" ")) {
            "https://$trimmed"
        } else {
            "https://duckduckgo.com/?q=${Uri.encode(trimmed)}"
        }
        urlInput.setText(normalized)
        webView.loadUrl(normalized)
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
            val jsCode = """
                (function() {
                  var out = document.getElementById('aiOutput');
                  if (out) {
                    out.textContent += '\n' + $escaped + '\n';
                    out.scrollTop = out.scrollHeight;
                  }
                })();
            """.trimIndent()

            mainHandler.post {
                try {
                    webView.evaluateJavascript(jsCode, null)
                } catch (_: Exception) {
                }
            }
        }
    }
}
