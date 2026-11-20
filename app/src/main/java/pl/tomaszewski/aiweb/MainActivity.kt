package pl.tomaszewski.aiweb

import android.annotation.SuppressLint
import android.content.Intent
import android.graphics.Color
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.text.InputType
import android.util.Log
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.WindowInsets
import android.view.inputmethod.EditorInfo
import android.webkit.ConsoleMessage
import android.webkit.JavascriptInterface
import android.webkit.WebChromeClient
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.Button
import android.widget.EditText
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

    companion object {
        private const val TAG = "AiWebMainActivity"
        private const val BRIDGE_NAME = "AndroidNative"
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private val ioThread = HandlerThread("AiBridgeIoThread").apply { start() }
    private val bgHandler = Handler(ioThread.looper)

    private lateinit var rootLayout: LinearLayout
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
          <link rel="icon" href="data:," />
          <title>AI Web Browser</title>
          <style>
            * { box-sizing: border-box; }
            body {
              margin: 0;
              padding: 16px;
              background: #0d1117;
              color: #e6edf3;
              font-family: sans-serif;
              line-height: 1.45;
            }
            .box {
              background: #161b22;
              border: 1px solid #30363d;
              border-radius: 10px;
              padding: 14px;
            }
            h1 { margin: 0 0 8px 0; font-size: 19px; color: #58a6ff; }
            .row { margin: 8px 0; font-size: 14px; }
            button {
              background: #238636;
              color: #ffffff;
              border: none;
              border-radius: 8px;
              padding: 10px 14px;
              font-size: 14px;
              margin-right: 8px;
              margin-top: 6px;
            }
            pre {
              background: #090c10;
              border: 1px solid #262c36;
              border-radius: 8px;
              padding: 10px;
              color: #7ee787;
              font-size: 12px;
              white-space: pre-wrap;
              min-height: 80px;
              margin-top: 10px;
            }
          </style>
        </head>
        <body>
          <div class="box">
            <h1>AI Web Browser — Gotowy</h1>
            <div class="row">Mostek: <span id="bridgeStatus">sprawdzanie...</span></div>
            <button type="button" onclick="pingBridge()">Test Bridge</button>
            <button type="button" onclick="goExample()">Otwórz example.com</button>
            <pre id="webConsole">Inicjalizacja strony startowej...</pre>
          </div>
          <script>
            (function() {
              var st = document.getElementById('bridgeStatus');
              var hasBridge = !!(window.AndroidNative && typeof window.AndroidNative.postChatCompletion === 'function');
              if (st) {
                st.textContent = hasBridge ? 'AKTYWNY (AndroidNative)' : 'BRAK';
              }
            })();
            function logWeb(msg) {
              var el = document.getElementById('webConsole');
              if (el) {
                el.textContent += '\n' + msg;
              }
            }
            function pingBridge() {
              if (!window.AndroidNative) {
                logWeb('[ERR] window.AndroidNative == null');
                return;
              }
              var out = window.AndroidNative.postChatCompletion('', '', '', '');
              logWeb('[PING] ' + out);
            }
            function goExample() {
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
        Log.i(TAG, "onCreate start")

        buildUserInterface()
        setupWebView()
        loadHomePage()

        Log.i(TAG, "onCreate completed, views attached")
    }

    override fun onStart() {
        super.onStart()
        Log.i(TAG, "onStart")
    }

    override fun onResume() {
        super.onResume()
        Log.i(TAG, "onResume")
        if (::webView.isInitialized) {
            attachBridge(webView)
            webView.onResume()
            webView.resumeTimers()
        }
    }

    override fun onPause() {
        Log.i(TAG, "onPause")
        if (::webView.isInitialized) {
            webView.onPause()
        }
        super.onPause()
    }

    override fun onStop() {
        Log.i(TAG, "onStop")
        super.onStop()
    }

    override fun onDestroy() {
        Log.i(TAG, "onDestroy")
        if (::webView.isInitialized) {
            webView.removeJavascriptInterface(BRIDGE_NAME)
            webView.destroy()
        }
        ioThread.quitSafely()
        super.onDestroy()
    }

    private fun loadHomePage() {
        webView.loadDataWithBaseURL(
            "https://app.local/",
            defaultHomeHtml,
            "text/html",
            "UTF-8",
            null
        )
    }

    private fun buildUserInterface() {
        rootLayout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(Color.parseColor("#0D1117"))
            visibility = View.VISIBLE
            layoutParams = ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
            setPadding(20, 136, 20, 96)
        }

        rootLayout.setOnApplyWindowInsetsListener { v, insets ->
            val topPad = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                val sysTop = insets.getInsets(WindowInsets.Type.systemBars()).top
                if (sysTop > 132) sysTop else 132
            } else {
                @Suppress("DEPRECATION")
                if (insets.systemWindowInsetTop > 132) insets.systemWindowInsetTop else 132
            }
            val bottomPad = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                val sysBot = insets.getInsets(WindowInsets.Type.systemBars()).bottom
                val imeBot = insets.getInsets(WindowInsets.Type.ime()).bottom
                val maxBot = if (sysBot > imeBot) sysBot else imeBot
                if (maxBot > 90) maxBot else 90
            } else {
                @Suppress("DEPRECATION")
                if (insets.systemWindowInsetBottom > 90) insets.systemWindowInsetBottom else 90
            }
            v.setPadding(20, topPad, 20, bottomPad)
            insets
        }

        val navRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            visibility = View.VISIBLE
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            )
        }

        fun createNavButton(label: String, action: () -> Unit): Button = Button(this).apply {
            text = label
            setTextColor(Color.WHITE)
            setBackgroundColor(Color.parseColor("#21262D"))
            visibility = View.VISIBLE
            minWidth = 0
            minimumWidth = 0
            setPadding(20, 12, 20, 12)
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            ).apply {
                marginEnd = 8
            }
            setOnClickListener { action() }
        }

        val btnBack = createNavButton("<") {
            if (::webView.isInitialized && webView.canGoBack()) {
                webView.goBack()
            }
        }
        val btnFwd = createNavButton(">") {
            if (::webView.isInitialized && webView.canGoForward()) {
                webView.goForward()
            }
        }
        val btnHome = createNavButton("Home") {
            if (::webView.isInitialized) {
                loadHomePage()
            }
        }

        urlInput = EditText(this).apply {
            hint = "https://example.com"
            setText("https://example.com")
            setTextColor(Color.WHITE)
            setHintTextColor(Color.parseColor("#8B949E"))
            setBackgroundColor(Color.parseColor("#161B22"))
            visibility = View.VISIBLE
            inputType = InputType.TYPE_TEXT_VARIATION_URI
            imeOptions = EditorInfo.IME_ACTION_GO
            setSingleLine(true)
            setPadding(18, 14, 18, 14)
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

        val btnGo = createNavButton("Idź") {
            navigateTo(urlInput.text.toString())
        }

        navRow.addView(btnBack)
        navRow.addView(btnFwd)
        navRow.addView(btnHome)
        navRow.addView(urlInput)
        navRow.addView(btnGo)

        statusText = TextView(this).apply {
            text = "Status: UI_READY | Bridge: $BRIDGE_NAME"
            setTextColor(Color.parseColor("#58A6FF"))
            setBackgroundColor(Color.parseColor("#11161D"))
            visibility = View.VISIBLE
            textSize = 13f
            setPadding(12, 10, 12, 10)
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            ).apply {
                topMargin = 8
                bottomMargin = 8
            }
        }

        webView = WebView(this).apply {
            visibility = View.VISIBLE
            setBackgroundColor(Color.parseColor("#0D1117"))
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                0,
                1f
            )
        }

        val aiPanel = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(Color.parseColor("#161B22"))
            visibility = View.VISIBLE
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
            visibility = View.VISIBLE
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            )
        }

        aiPromptInput = EditText(this).apply {
            hint = """{"messages":[{"role":"user","content":"ping"}]}"""
            setText("""{"messages":[{"role":"user","content":"ping"}]}""")
            setTextColor(Color.WHITE)
            setHintTextColor(Color.parseColor("#8B949E"))
            setBackgroundColor(Color.parseColor("#0D1117"))
            visibility = View.VISIBLE
            setSingleLine(true)
            setPadding(16, 12, 16, 12)
            layoutParams = LinearLayout.LayoutParams(
                0,
                ViewGroup.LayoutParams.WRAP_CONTENT,
                1f
            ).apply {
                marginEnd = 8
            }
        }

        val btnTestAi = Button(this).apply {
            text = "Test AI"
            setTextColor(Color.WHITE)
            setBackgroundColor(Color.parseColor("#238636"))
            visibility = View.VISIBLE
            setPadding(18, 12, 18, 12)
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            )
            setOnClickListener {
                val payload = aiPromptInput.text.toString()
                bgHandler.post {
                    val res = AndroidNative(webView).postChatCompletion("", "", "", payload)
                    mainHandler.post {
                        aiOutputView.append("\n[TEST] $res")
                        statusText.text = "Status: TEST_OK | Bridge: $BRIDGE_NAME"
                    }
                }
            }
        }

        aiRow.addView(aiPromptInput)
        aiRow.addView(btnTestAi)

        val logScroll = ScrollView(this).apply {
            visibility = View.VISIBLE
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                240
            ).apply {
                topMargin = 8
            }
        }

        aiOutputView = TextView(this).apply {
            text = "[READY] MainActivity UI widoczne. Mostek: $BRIDGE_NAME"
            setTextColor(Color.parseColor("#E6EDF3"))
            setBackgroundColor(Color.parseColor("#090C10"))
            visibility = View.VISIBLE
            textSize = 12f
            setPadding(12, 10, 12, 10)
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            )
        }

        logScroll.addView(aiOutputView)
        aiPanel.addView(aiRow)
        aiPanel.addView(logScroll)

        rootLayout.addView(navRow)
        rootLayout.addView(statusText)
        rootLayout.addView(webView)
        rootLayout.addView(aiPanel)

        setContentView(rootLayout)
    }

    @SuppressLint("SetJavaScriptEnabled")
    private fun setupWebView() {
        webView.settings.apply {
            javaScriptEnabled = true
            domStorageEnabled = true
            databaseEnabled = true
            loadWithOverviewMode = true
            useWideViewPort = true
            cacheMode = WebSettings.LOAD_DEFAULT
            mixedContentMode = WebSettings.MIXED_CONTENT_COMPATIBILITY_MODE
            userAgentString = "$userAgentString AiWebBrowser/1.2"
        }

        attachBridge(webView)

        webView.webChromeClient = object : WebChromeClient() {
            override fun onProgressChanged(view: WebView?, newProgress: Int) {
                super.onProgressChanged(view, newProgress)
                mainHandler.post {
                    statusText.text = "Status: WebView ${newProgress}% | Bridge: $BRIDGE_NAME"
                }
            }

            override fun onConsoleMessage(consoleMessage: ConsoleMessage?): Boolean {
                consoleMessage?.let {
                    Log.d(TAG, "JS[${it.messageLevel()}]: ${it.message()} (${it.sourceId()}:${it.lineNumber()})")
                }
                return super.onConsoleMessage(consoleMessage)
            }
        }

        webView.webViewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(
                view: WebView?,
                request: WebResourceRequest?
            ): Boolean {
                val url = request?.url?.toString().orEmpty()
                if (url.isNotEmpty()) {
                    mainHandler.post { urlInput.setText(url) }
                }
                return false
            }

            override fun onPageFinished(view: WebView?, url: String?) {
                super.onPageFinished(view, url)
                val currentUrl = url.orEmpty()
                Log.i(TAG, "onPageFinished: $currentUrl")
                mainHandler.post {
                    if (currentUrl.isNotEmpty() && !currentUrl.startsWith("data:")) {
                        urlInput.setText(currentUrl)
                    }
                    statusText.text = "Status: LOADED | Bridge: $BRIDGE_NAME"
                }
            }

            override fun onReceivedError(
                view: WebView?,
                request: WebResourceRequest?,
                error: WebResourceError?
            ) {
                super.onReceivedError(view, request, error)
                val desc = error?.description?.toString().orEmpty()
                val reqUrl = request?.url?.toString().orEmpty()
                val isMainFrame = request?.isForMainFrame ?: true
                if (!isMainFrame || reqUrl.endsWith("/favicon.ico", ignoreCase = true)) {
                    Log.w(TAG, "Ignored subresource error ($reqUrl): $desc")
                    return
                }
                Log.e(TAG, "WebView error ($reqUrl): $desc")
                mainHandler.post {
                    statusText.text = "Status: WEB_ERR | $desc"
                    aiOutputView.append("\n[WEB_ERR] $reqUrl -> $desc")
                }
            }
        }
    }

    @SuppressLint("SetJavaScriptEnabled")
    private fun attachBridge(target: WebView) {
        target.settings.javaScriptEnabled = true
        target.settings.domStorageEnabled = true
        target.removeJavascriptInterface(BRIDGE_NAME)
        target.addJavascriptInterface(AndroidNative(target), BRIDGE_NAME)
        Log.i(TAG, "Bridge $BRIDGE_NAME attached")
    }

    private fun navigateTo(raw: String) {
        val trimmed = raw.trim()
        if (trimmed.isEmpty()) return
        val url = when {
            trimmed.startsWith("http://", ignoreCase = true) ||
                trimmed.startsWith("https://", ignoreCase = true) ||
                trimmed.startsWith("file://", ignoreCase = true) ||
                trimmed.startsWith("about:", ignoreCase = true) -> trimmed
            trimmed.contains(".") && !trimmed.contains(" ") -> "https://$trimmed"
            else -> "https://duckduckgo.com/?q=${Uri.encode(trimmed)}"
        }
        Log.i(TAG, "navigateTo: $url")
        urlInput.setText(url)
        webView.loadUrl(url)
    }

    inner class AndroidNative(private val targetWebView: WebView) {

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
                    } else {
                        targetWebView.loadUrl(cleanUrl)
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "openExternalUrl failed", e)
                    emitJsError("openExternalUrl: ${e.message ?: "error"}")
                }
            }
        }

        @JavascriptInterface
        fun goBack() {
            mainHandler.post {
                try {
                    if (targetWebView.canGoBack()) {
                        targetWebView.goBack()
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "goBack failed", e)
                }
            }
        }

        @JavascriptInterface
        fun goForward() {
            mainHandler.post {
                try {
                    if (targetWebView.canGoForward()) {
                        targetWebView.goForward()
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "goForward failed", e)
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
            val url = endpoint?.trim().orEmpty()
            if (url.isEmpty()) {
                return JSONObject().put("error", "Brak endpointu AI").toString()
            }
            val rawPayload = payloadJson?.trim().orEmpty()
            if (rawPayload.isEmpty()) {
                return JSONObject().put("error", "Pusty ładunek JSON").toString()
            }

            val bodyJson = try {
                val obj = JSONObject(rawPayload)
                if (!model.isNullOrBlank()) {
                    obj.put("model", model.trim())
                }
                obj.toString()
            } catch (e: Exception) {
                return JSONObject().put("error", "Błędny JSON: ${e.message}").toString()
            }

            return try {
                val mediaType = "application/json; charset=utf-8".toMediaType()
                val reqBody = bodyJson.toRequestBody(mediaType)
                val reqBuilder = Request.Builder()
                    .url(url)
                    .post(reqBody)
                    .header("Content-Type", "application/json")
                    .header("Accept", "application/json")

                val token = apiKey?.trim().orEmpty()
                if (token.isNotEmpty()) {
                    reqBuilder.header("Authorization", "Bearer $token")
                }

                httpClient.newCall(reqBuilder.build()).execute().use { resp ->
                    val respText = resp.body?.string().orEmpty()
                    if (!resp.isSuccessful) {
                        JSONObject()
                            .put("error", "HTTP ${resp.code}: ${resp.message} ${respText.take(400)}")
                            .toString()
                    } else if (respText.isBlank()) {
                        JSONObject().put("error", "Pusta odpowiedź endpointu").toString()
                    } else {
                        respText
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "postChatCompletion failed", e)
                JSONObject()
                    .put("error", "${e.javaClass.simpleName}: ${e.message ?: "network error"}")
                    .toString()
            }
        }

        private fun emitJsError(msg: String) {
            val quoted = JSONObject.quote("[BRIDGE] $msg")
            val script = """
                (function() {
                  var el = document.getElementById('webConsole');
                  if (el) {
                    el.textContent += '\n' + $quoted;
                  }
                })();
            """.trimIndent()
            mainHandler.post {
                try {
                    targetWebView.evaluateJavascript(script, null)
                } catch (_: Exception) {
                }
            }
        }
    }
}
