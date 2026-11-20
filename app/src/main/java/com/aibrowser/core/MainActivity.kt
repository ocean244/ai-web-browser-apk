package com.aibrowser.core

import android.annotation.SuppressLint
import android.content.Context
import android.os.Bundle
import android.view.View
import android.view.inputmethod.EditorInfo
import android.webkit.CookieManager
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.Button
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.io.BufferedReader
import java.io.InputStreamReader
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder

data class BrowserTab(
    val id: Int,
    val webView: WebView,
    val tabButton: Button,
    var title: String = "Duck.ai",
    var url: String = "https://duck.ai/"
)

class MainActivity : AppCompatActivity() {

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private val tabs = mutableListOf<BrowserTab>()
    private var activeTabId: Int = -1
    private var nextTabId: Int = 1

    private lateinit var webContainer: FrameLayout
    private lateinit var tabsStrip: LinearLayout
    private lateinit var aiCard: LinearLayout
    private lateinit var urlInput: EditText
    private lateinit var promptInput: EditText
    private lateinit var aiOutputText: TextView

    private val messagesHistory = JSONArray()

    @SuppressLint("SetJavaScriptEnabled")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        webContainer = findViewById(R.id.webContainer)
        tabsStrip = findViewById(R.id.tabsStrip)
        aiCard = findViewById(R.id.aiCardContainer)
        urlInput = findViewById(R.id.urlInput)
        promptInput = findViewById(R.id.promptInput)
        aiOutputText = findViewById(R.id.aiOutputText)

        val backButton: Button = findViewById(R.id.backButton)
        val newTabButton: Button = findViewById(R.id.newTabButton)
        val goButton: Button = findViewById(R.id.goButton)
        val aiTabButton: Button = findViewById(R.id.aiTabButton)
        val endpointInput: EditText = findViewById(R.id.endpointInput)
        val apiKeyInput: EditText = findViewById(R.id.apiKeyInput)
        val modelInput: EditText = findViewById(R.id.modelInput)
        val saveConfigButton: Button = findViewById(R.id.saveConfigButton)
        val clearChatButton: Button = findViewById(R.id.clearChatButton)
        val injectPageButton: Button = findViewById(R.id.injectPageButton)
        val injectSelectionButton: Button = findViewById(R.id.injectSelectionButton)
        val sendAiButton: Button = findViewById(R.id.sendAiButton)

        val prefs = getSharedPreferences("ai_browser_prefs", Context.MODE_PRIVATE)
        endpointInput.setText(prefs.getString("endpoint", "https://api.openai.com/v1/chat/completions"))
        apiKeyInput.setText(prefs.getString("api_key", ""))
        modelInput.setText(prefs.getString("model", "gpt-4.1-mini"))

        val saveConfig = {
            prefs.edit()
                .putString("endpoint", endpointInput.text.toString().trim())
                .putString("api_key", apiKeyInput.text.toString().trim())
                .putString("model", modelInput.text.toString().trim())
                .apply()
        }

        saveConfigButton.setOnClickListener { saveConfig() }

        clearChatButton.setOnClickListener {
            while (messagesHistory.length() > 0) {
                messagesHistory.remove(0)
            }
            aiOutputText.text = ""
        }

        CookieManager.getInstance().setAcceptCookie(true)

        backButton.setOnClickListener {
            if (aiCard.visibility == View.VISIBLE) {
                showBrowserTab()
                return@setOnClickListener
            }
            val current = getActiveTab()
            if (current != null && current.webView.canGoBack()) {
                current.webView.goBack()
            }
        }

        newTabButton.setOnClickListener {
            createTab("https://duckduckgo.com/", switchToIt = true)
        }

        val navigate = { raw: String ->
            showBrowserTab()
            val trimmed = raw.trim()
            val url = when {
                trimmed.startsWith("http://") || trimmed.startsWith("https://") -> trimmed
                trimmed.contains(".") && !trimmed.contains(" ") -> "https://$trimmed"
                else -> "https://duckduckgo.com/?q=" + URLEncoder.encode(trimmed, "UTF-8")
            }
            val current = getActiveTab() ?: createTab(url, switchToIt = true)
            current.url = url
            urlInput.setText(url)
            current.webView.loadUrl(url)
        }

        goButton.setOnClickListener { navigate(urlInput.text.toString()) }
        urlInput.setOnEditorActionListener { _, actionId, _ ->
            if (actionId == EditorInfo.IME_ACTION_GO || actionId == EditorInfo.IME_ACTION_DONE) {
                navigate(urlInput.text.toString())
                true
            } else false
        }

        aiTabButton.setOnClickListener {
            if (aiCard.visibility == View.VISIBLE) showBrowserTab() else showAiTab()
        }

        injectPageButton.setOnClickListener {
            val current = getActiveTab() ?: return@setOnClickListener
            val pageUrl = current.webView.url ?: current.url
            current.webView.evaluateJavascript(
                "(function(){ return (document.body && document.body.innerText) ? document.body.innerText.slice(0, 12000) : ''; })()"
            ) { rawJs ->
                val extracted = unescapeJsString(rawJs)
                val existing = promptInput.text.toString()
                val appended = buildString {
                    if (existing.isNotBlank()) append(existing).append("\n\n")
                    append("URL: ").append(pageUrl).append("\n")
                    append("TREŚĆ:\n").append(extracted)
                }
                promptInput.setText(appended)
            }
        }

        injectSelectionButton.setOnClickListener {
            val current = getActiveTab() ?: return@setOnClickListener
            val pageUrl = current.webView.url ?: current.url
            current.webView.evaluateJavascript(
                "(function(){ return window.getSelection ? window.getSelection().toString() : ''; })()"
            ) { rawJs ->
                val selected = unescapeJsString(rawJs)
                val existing = promptInput.text.toString()
                val appended = buildString {
                    if (existing.isNotBlank()) append(existing).append("\n\n")
                    append("URL: ").append(pageUrl).append("\n")
                    append("ZAZNACZENIE:\n").append(selected)
                }
                promptInput.setText(appended)
            }
        }

        sendAiButton.setOnClickListener {
            saveConfig()
            val endpoint = endpointInput.text.toString().trim()
            val apiKey = apiKeyInput.text.toString().trim()
            val model = modelInput.text.toString().trim()
            val prompt = promptInput.text.toString().trim()
            if (endpoint.isEmpty() || prompt.isEmpty()) return@setOnClickListener

            messagesHistory.put(JSONObject().apply {
                put("role", "user")
                put("content", prompt)
            })
            promptInput.setText("")
            sendAiButton.isEnabled = false
            aiOutputText.append("\n[USER]: $prompt\n[AI]: ...\n")

            scope.launch {
                val reply = callChatCompletions(endpoint, apiKey, model, messagesHistory)
                messagesHistory.put(JSONObject().apply {
                    put("role", "assistant")
                    put("content", reply)
                })
                val currentText = aiOutputText.text.toString()
                aiOutputText.text = currentText.replaceLastOccurrence("[AI]: ...\n", "[AI]: $reply\n")
                sendAiButton.isEnabled = true
            }
        }

        val initialUrl = intent?.data?.toString() ?: "https://duck.ai/"
        createTab(initialUrl, switchToIt = true)
    }

    @SuppressLint("SetJavaScriptEnabled")
    private fun createTab(url: String, switchToIt: Boolean): BrowserTab {
        val id = nextTabId++
        val wv = WebView(this).apply {
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            )
            CookieManager.getInstance().setAcceptThirdPartyCookies(this, true)
            settings.apply {
                javaScriptEnabled = true
                domStorageEnabled = true
                databaseEnabled = true
                cacheMode = WebSettings.LOAD_DEFAULT
                mixedContentMode = WebSettings.MIXED_CONTENT_ALWAYS_ALLOW
                loadWithOverviewMode = true
                useWideViewPort = true
                setSupportMultipleWindows(false)
            }
            webChromeClient = object : WebChromeClient() {
                override fun onReceivedTitle(view: WebView?, title: String?) {
                    val t = tabs.find { it.id == id } ?: return
                    if (!title.isNullOrBlank()) {
                        t.title = title.take(18)
                        refreshTabLabels()
                    }
                }
            }
            webViewClient = object : WebViewClient() {
                override fun shouldOverrideUrlLoading(view: WebView?, request: WebResourceRequest?): Boolean {
                    val target = request?.url?.toString() ?: return false
                    val t = tabs.find { it.id == id }
                    t?.url = target
                    if (activeTabId == id) {
                        urlInput.setText(target)
                    }
                    return false
                }

                override fun onPageFinished(view: WebView?, loadedUrl: String?) {
                    val t = tabs.find { it.id == id } ?: return
                    if (!loadedUrl.isNullOrBlank()) {
                        t.url = loadedUrl
                        if (activeTabId == id) {
                            urlInput.setText(loadedUrl)
                        }
                    }
                }
            }
        }

        val btn = Button(this).apply {
            text = "K$id"
            setOnClickListener {
                showBrowserTab()
                switchToTab(id)
            }
            setOnLongClickListener {
                if (tabs.size > 1) {
                    closeTab(id)
                }
                true
            }
        }

        val tab = BrowserTab(id = id, webView = wv, tabButton = btn, url = url)
        tabs.add(tab)
        tabsStrip.addView(btn)
        webContainer.addView(wv)
        wv.loadUrl(url)

        if (switchToIt) {
            switchToTab(id)
        }
        return tab
    }

    private fun switchToTab(id: Int) {
        activeTabId = id
        for (t in tabs) {
            val selected = t.id == id
            t.webView.visibility = if (selected) View.VISIBLE else View.GONE
            t.tabButton.isEnabled = !selected
            if (selected) {
                urlInput.setText(t.url)
            }
        }
        refreshTabLabels()
    }

    private fun closeTab(id: Int) {
        val idx = tabs.indexOfFirst { it.id == id }
        if (idx == -1 || tabs.size <= 1) return
        val target = tabs.removeAt(idx)
        tabsStrip.removeView(target.tabButton)
        webContainer.removeView(target.webView)
        target.webView.destroy()

        if (activeTabId == id) {
            val next = tabs[idx.coerceAtMost(tabs.lastIndex)]
            switchToTab(next.id)
        }
    }

    private fun refreshTabLabels() {
        for (t in tabs) {
            val marker = if (t.id == activeTabId) "*" else ""
            t.tabButton.text = "$marker${t.id}:${t.title}"
        }
    }

    private fun getActiveTab(): BrowserTab? = tabs.find { it.id == activeTabId }

    private fun showBrowserTab() {
        aiCard.visibility = View.GONE
        webContainer.visibility = View.VISIBLE
    }

    private fun showAiTab() {
        webContainer.visibility = View.GONE
        aiCard.visibility = View.VISIBLE
    }

    private fun unescapeJsString(raw: String?): String {
        if (raw == null || raw == "null") return ""
        return try {
            JSONArray("[$raw]").optString(0, raw)
        } catch (_: Exception) {
            raw.trim('"')
        }
    }

    private fun String.replaceLastOccurrence(oldValue: String, newValue: String): String {
        val idx = lastIndexOf(oldValue)
        if (idx == -1) return this
        return replaceRange(idx, idx + oldValue.length, newValue)
    }

    private suspend fun callChatCompletions(
        endpoint: String,
        apiKey: String,
        model: String,
        history: JSONArray
    ): String = withContext(Dispatchers.IO) {
        var conn: HttpURLConnection? = null
        try {
            val url = URL(endpoint)
            conn = (url.openConnection() as HttpURLConnection).apply {
                requestMethod = "POST"
                connectTimeout = 15000
                readTimeout = 60000
                doOutput = true
                setRequestProperty("Content-Type", "application/json")
                if (apiKey.isNotEmpty()) {
                    setRequestProperty("Authorization", "Bearer $apiKey")
                }
            }

            val payload = JSONObject().apply {
                put("model", model)
                put("messages", history)
            }.toString()

            OutputStreamWriter(conn.outputStream, Charsets.UTF_8).use { writer ->
                writer.write(payload)
                writer.flush()
            }

            val code = conn.responseCode
            val stream = if (code in 200..299) conn.inputStream else conn.errorStream
            val body = BufferedReader(InputStreamReader(stream, Charsets.UTF_8)).use { it.readText() }

            if (code !in 200..299) return@withContext "HTTP $code: $body"

            val json = JSONObject(body)
            val choices = json.optJSONArray("choices")
            if (choices != null && choices.length() > 0) {
                val msg = choices.getJSONObject(0).optJSONObject("message")
                msg?.optString("content", body) ?: body
            } else {
                body
            }
        } catch (e: Exception) {
            "ERR: ${e.message}"
        } finally {
            conn?.disconnect()
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onBackPressed() {
        if (aiCard.visibility == View.VISIBLE) {
            showBrowserTab()
            return
        }
        val current = getActiveTab()
        if (current != null && current.webView.canGoBack()) {
            current.webView.goBack()
        } else {
            @Suppress("DEPRECATION")
            super.onBackPressed()
        }
    }

    override fun onDestroy() {
        scope.cancel()
        for (t in tabs) {
            t.webView.destroy()
        }
        tabs.clear()
        super.onDestroy()
    }
}
