package pl.tomaszewski.aiweb

import android.annotation.SuppressLint
import android.os.Bundle
import android.util.Log
import android.webkit.JavascriptInterface
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.Button
import android.widget.EditText
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import org.json.JSONArray
import org.json.JSONObject
import java.net.URLEncoder
import java.util.concurrent.Executors

class MainActivity : AppCompatActivity() {

    private val tag = "AiWebMainActivity"
    private val ioPool = Executors.newCachedThreadPool()

    private lateinit var configStore: AiConfigStore
    private lateinit var aiClient: OpenAiClient
    private lateinit var searchEngine: WebSearchEngine

    private lateinit var webView: WebView
    private lateinit var urlInput: EditText
    private lateinit var endpointInput: EditText
    private lateinit var modelInput: EditText
    private lateinit var apiKeyInput: EditText
    private lateinit var promptInput: EditText
    private lateinit var statusView: TextView
    private lateinit var outputView: TextView

    @Volatile
    private var lastPageText: String = ""
    private var bridgeAttached: Boolean = false

    @SuppressLint("SetJavaScriptEnabled")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        bindViews()

        val initialCfg = configStore.load()
        endpointInput.setText(initialCfg.endpoint)
        modelInput.setText(initialCfg.model)
        apiKeyInput.setText(initialCfg.apiKey)
        if (promptInput.text.isNullOrBlank()) {
            promptInput.setText("{\"messages\":[{\"role\":\"user\",\"content\":\"ping\"}]}")
        }

        bindListeners()

        val startUrl = urlInput.text.toString().trim().let { if (it.isEmpty() || it == "https://app.local/") "file:///android_asset/index.html" else it }
        urlInput.setText(startUrl)

        webView.post {
            configureWebView(startUrl)
        }
        Log.i(tag, "onCreate completed, views attached")
    }

    private fun bindViews() {
        configStore = AiConfigStore(this)
        aiClient = OpenAiClient(configStore)
        searchEngine = WebSearchEngine(configStore)

        webView = findViewById(R.id.webView)
        urlInput = findViewById(R.id.urlInput)
        endpointInput = findViewById(R.id.endpointInput)
        modelInput = findViewById(R.id.modelInput)
        apiKeyInput = findViewById(R.id.apiKeyInput)
        promptInput = findViewById(R.id.promptInput)
        statusView = findViewById(R.id.statusView)
        outputView = findViewById(R.id.outputView)
    }

    private fun bindListeners() {
        findViewById<Button>(R.id.goButton).setOnClickListener {
            navigateOrSearch(urlInput.text.toString())
        }

        findViewById<Button>(R.id.testAiButton).setOnClickListener {
            persistInputsToConfig()
            val rawPrompt = promptInput.text.toString().trim()
            val userText = extractUserTextFromPrompt(rawPrompt)
            runAiQuery(userText, usePageContext = false)
        }

        findViewById<Button>(R.id.searchAndAskButton)?.setOnClickListener {
            persistInputsToConfig()
            val query = urlInput.text.toString().trim().ifEmpty {
                extractUserTextFromPrompt(promptInput.text.toString())
            }
            runSearchAndAi(query)
        }
    }

    @SuppressLint("SetJavaScriptEnabled")
    private fun configureWebView(startUrl: String) {
        webView.settings.javaScriptEnabled = true
        webView.settings.domStorageEnabled = true
        webView.settings.mixedContentMode = WebSettings.MIXED_CONTENT_ALWAYS_ALLOW
        webView.webChromeClient = WebChromeClient()
        webView.webViewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(view: WebView?, request: WebResourceRequest?): Boolean {
                val targetUrl = request?.url?.toString() ?: return false
                urlInput.setText(targetUrl)
                return false
            }

            override fun onPageFinished(view: WebView?, url: String?) {
                super.onPageFinished(view, url)
                Log.i(tag, "onPageFinished: $url")
                statusView.text = "Status: LOADED | Bridge: AndroidNative"
                val currentUrl = url ?: ""
                if (currentUrl.startsWith("http")) {
                    ioPool.execute {
                        val fetched = searchEngine.fetchUrlText(currentUrl)
                        if (fetched.optBoolean("ok")) {
                            lastPageText = fetched.optString("text", "")
                        }
                    }
                }
            }
        }
        if (!bridgeAttached) {
            webView.addJavascriptInterface(AndroidNativeBridge(), "AndroidNative")
            bridgeAttached = true
            Log.i(tag, "Bridge AndroidNative attached")
        }
        webView.loadUrl(startUrl)
    }

    override fun onStart() {
        super.onStart()
        Log.i(tag, "onStart")
    }

    override fun onResume() {
        super.onResume()
        Log.i(tag, "onResume")
    }

    override fun onPause() {
        super.onPause()
        Log.i(tag, "onPause")
    }

    override fun onStop() {
        super.onStop()
        Log.i(tag, "onStop")
    }

    override fun onDestroy() {
        ioPool.shutdownNow()
        super.onDestroy()
    }

    private fun persistInputsToConfig() {
        val current = configStore.load()
        configStore.save(
            current.copy(
                endpoint = endpointInput.text.toString().trim().ifEmpty { current.endpoint },
                model = modelInput.text.toString().trim().ifEmpty { current.model },
                apiKey = apiKeyInput.text.toString().trim()
            )
        )
    }

    private fun navigateOrSearch(input: String) {
        val raw = input.trim()
        if (raw.isEmpty()) return
        val isUrl = raw.startsWith("http://") || raw.startsWith("https://") ||
            (!raw.contains(" ") && raw.contains("."))
        val finalUrl = if (isUrl) {
            if (raw.startsWith("http")) raw else "https://$raw"
        } else {
            val cfg = configStore.load()
            val enc = URLEncoder.encode(raw, "UTF-8")
            if (cfg.searchEndpoint.contains("q=")) "${cfg.searchEndpoint}$enc" else "${cfg.searchEndpoint}?q=$enc"
        }
        urlInput.setText(finalUrl)
        webView.loadUrl(finalUrl)
    }

    private fun extractUserTextFromPrompt(raw: String): String {
        if (raw.startsWith("{")) {
            try {
                val obj = JSONObject(raw)
                val msgs = obj.optJSONArray("messages")
                if (msgs != null && msgs.length() > 0) {
                    val last = msgs.optJSONObject(msgs.length() - 1)
                    val content = last?.optString("content", "")
                    if (!content.isNullOrBlank()) return content
                }
            } catch (_: Exception) {
            }
        }
        return raw.ifEmpty { "ping" }
    }

    private fun runAiQuery(userText: String, usePageContext: Boolean) {
        val ep = endpointInput.text.toString().trim()
        val mdl = modelInput.text.toString().trim()
        val key = apiKeyInput.text.toString().trim()
        val ctx = if (usePageContext) lastPageText else ""

        runOnUiThread { statusView.text = "Status: AI_RUNNING | Bridge: AndroidNative" }

        ioPool.execute {
            val res = aiClient.chatCompletion(
                userPrompt = userText,
                contextText = ctx,
                overrideEndpoint = ep,
                overrideModel = mdl,
                overrideApiKey = key
            )
            val replyContent = res.optString("content", "")
            val formatted = if (res.optBoolean("ok") && replyContent.isNotEmpty()) {
                val synthetic = JSONObject()
                    .put("id", "ai-live")
                    .put(
                        "choices",
                        JSONArray().put(
                            JSONObject().put(
                                "message",
                                JSONObject().put("role", "assistant").put("content", replyContent)
                            )
                        )
                    )
                "[TEST] $synthetic"
            } else {
                "[ERR] $res"
            }

            runOnUiThread {
                statusView.text = if (res.optBoolean("ok")) {
                    "Status: TEST_OK | Bridge: AndroidNative"
                } else {
                    "Status: AI_ERR | Bridge: AndroidNative"
                }
                outputView.text = formatted
                webView.evaluateJavascript(
                    "if(window.onNativeAiResult){window.onNativeAiResult(${JSONObject.quote(res.toString())});}",
                    null
                )
            }
        }
    }

    private fun runSearchAndAi(query: String) {
        if (query.isBlank()) return
        runOnUiThread { statusView.text = "Status: SEARCH_AI | Bridge: AndroidNative" }

        ioPool.execute {
            val searchRes = searchEngine.search(query, limit = 6)
            val resultsArr = searchRes.optJSONArray("results")
            val sb = StringBuilder()
            if (resultsArr != null) {
                for (i in 0 until minOf(resultsArr.length(), 3)) {
                    val item = resultsArr.optJSONObject(i) ?: continue
                    val rUrl = item.optString("url", "")
                    val rTitle = item.optString("title", "")
                    if (rUrl.isNotEmpty()) {
                        val page = searchEngine.fetchUrlText(rUrl, maxChars = 3500)
                        sb.append("SOURCE: $rTitle ($rUrl)\n")
                        sb.append(page.optString("text", "")).append("\n\n")
                    }
                }
            }
            val aiRes = aiClient.chatCompletion(
                userPrompt = "Na podstawie poniższych wyników wyszukiwania sieciowego odpowiedz precyzyjnie na zapytanie: $query",
                contextText = sb.toString(),
                overrideEndpoint = endpointInput.text.toString().trim(),
                overrideModel = modelInput.text.toString().trim(),
                overrideApiKey = apiKeyInput.text.toString().trim()
            )
            val answer = if (aiRes.optBoolean("ok")) aiRes.optString("content", "") else aiRes.toString()
            runOnUiThread {
                statusView.text = if (aiRes.optBoolean("ok")) {
                    "Status: SEARCH_OK | Bridge: AndroidNative"
                } else {
                    "Status: SEARCH_ERR | Bridge: AndroidNative"
                }
                outputView.text = "[SEARCH+AI] $answer"
            }
        }
    }

    inner class AndroidNativeBridge {
        @JavascriptInterface
        fun ping(): String {
            return JSONObject()
                .put("ok", true)
                .put("bridge", "AndroidNative")
                .put("model", modelInput.text.toString())
                .toString()
        }

        @JavascriptInterface
        fun setConfig(endpoint: String, model: String, apiKey: String, systemPrompt: String): String {
            val current = configStore.load()
            configStore.save(
                current.copy(
                    endpoint = endpoint.ifBlank { current.endpoint },
                    model = model.ifBlank { current.model },
                    apiKey = apiKey,
                    systemPrompt = systemPrompt.ifBlank { current.systemPrompt }
                )
            )
            runOnUiThread {
                endpointInput.setText(endpoint.ifBlank { current.endpoint })
                modelInput.setText(model.ifBlank { current.model })
                apiKeyInput.setText(apiKey)
            }
            return JSONObject().put("ok", true).toString()
        }

        @JavascriptInterface
        fun askAi(prompt: String, includePageContext: Boolean): String {
            val ctx = if (includePageContext) lastPageText else ""
            val res = aiClient.chatCompletion(
                userPrompt = prompt,
                contextText = ctx,
                overrideEndpoint = endpointInput.text.toString().trim(),
                overrideModel = modelInput.text.toString().trim(),
                overrideApiKey = apiKeyInput.text.toString().trim()
            )
            return res.toString()
        }

        @JavascriptInterface
        fun webSearch(query: String, limit: Int): String {
            return searchEngine.search(query, limit.coerceIn(1, 15)).toString()
        }

        @JavascriptInterface
        fun fetchPage(url: String): String {
            return searchEngine.fetchUrlText(url).toString()
        }
    }
}
