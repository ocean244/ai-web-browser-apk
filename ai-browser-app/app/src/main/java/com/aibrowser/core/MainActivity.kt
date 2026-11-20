package com.aibrowser.core

import android.annotation.SuppressLint
import android.app.AlertDialog
import android.app.DownloadManager
import android.content.Context
import android.net.Uri
import android.os.Bundle
import android.os.Environment
import android.view.View
import android.view.inputmethod.EditorInfo
import android.webkit.CookieManager
import android.webkit.DownloadListener
import android.webkit.URLUtil
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.Button
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
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
import java.io.ByteArrayInputStream
import java.io.File
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
    private lateinit var scriptsStrip: LinearLayout
    private lateinit var addScriptButton: Button
    private lateinit var aiCard: LinearLayout
    private lateinit var urlInput: EditText
    private lateinit var promptInput: EditText
    private lateinit var aiOutputText: TextView
    private lateinit var storage: BrowserStorage

    private val messagesHistory = JSONArray()

    @SuppressLint("SetJavaScriptEnabled")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        webContainer = findViewById(R.id.webContainer)
        tabsStrip = findViewById(R.id.tabsStrip)
        scriptsStrip = findViewById(R.id.scriptsStrip)
        addScriptButton = findViewById(R.id.addScriptButton)
        aiCard = findViewById(R.id.aiCardContainer)
        urlInput = findViewById(R.id.urlInput)
        promptInput = findViewById(R.id.promptInput)
        aiOutputText = findViewById(R.id.aiOutputText)

        val backButton: Button = findViewById(R.id.backButton)
        val newTabButton: Button = findViewById(R.id.newTabButton)
        val addBookmarkButton: Button = findViewById(R.id.addBookmarkButton)
        val bookmarksButton: Button = findViewById(R.id.bookmarksButton)
        val historyButton: Button = findViewById(R.id.historyButton)
        val exportJsonButton: Button = findViewById(R.id.exportJsonButton)
        val importJsonButton: Button = findViewById(R.id.importJsonButton)
        val goButton: Button = findViewById(R.id.goButton)
        val aiTabButton: Button = findViewById(R.id.aiTabButton)
        val endpointInput: EditText = findViewById(R.id.endpointInput)
        val apiKeyInput: EditText = findViewById(R.id.apiKeyInput)
        val modelInput: EditText = findViewById(R.id.modelInput)
        val bridgePresetButton: Button = findViewById(R.id.bridgePresetButton)
        val saveConfigButton: Button = findViewById(R.id.saveConfigButton)
        val clearChatButton: Button = findViewById(R.id.clearChatButton)
        val injectPageButton: Button = findViewById(R.id.injectPageButton)
        val injectSelectionButton: Button = findViewById(R.id.injectSelectionButton)
        val sendAiButton: Button = findViewById(R.id.sendAiButton)

        val prefs = getSharedPreferences("ai_browser_prefs", Context.MODE_PRIVATE)
        storage = BrowserStorage(prefs)

        endpointInput.setText(prefs.getString("endpoint", "http://127.0.0.1:8080/v1/chat/completions"))
        apiKeyInput.setText(prefs.getString("api_key", ""))
        modelInput.setText(prefs.getString("model", "gpt-4.1-mini"))

        val saveConfig = {
            prefs.edit()
                .putString("endpoint", endpointInput.text.toString().trim())
                .putString("api_key", apiKeyInput.text.toString().trim())
                .putString("model", modelInput.text.toString().trim())
                .apply()
        }

        bridgePresetButton.setOnClickListener {
            endpointInput.setText("http://127.0.0.1:8080/v1/chat/completions")
            saveConfig()
            Toast.makeText(this, "Ustawiono mostek 127.0.0.1:8080", Toast.LENGTH_SHORT).show()
        }

        saveConfigButton.setOnClickListener {
            saveConfig()
            Toast.makeText(this, "Zapisano", Toast.LENGTH_SHORT).show()
        }

        clearChatButton.setOnClickListener {
            while (messagesHistory.length() > 0) {
                messagesHistory.remove(0)
            }
            aiOutputText.text = ""
        }

        addBookmarkButton.setOnClickListener {
            val current = getActiveTab() ?: return@setOnClickListener
            val targetUrl = current.webView.url ?: current.url
            val targetTitle = current.webView.title ?: current.title
            storage.addBookmark(targetTitle, targetUrl)
            Toast.makeText(this, "Dodano zakładkę", Toast.LENGTH_SHORT).show()
        }

        bookmarksButton.setOnClickListener {
            showEntriesDialog("Zakładki", storage.loadBookmarks())
        }

        historyButton.setOnClickListener {
            showEntriesDialog("Historia", storage.loadHistory())
        }

        exportJsonButton.setOnClickListener {
            exportBackupToDownloads()
        }

        importJsonButton.setOnClickListener {
            showImportJsonDialog()
        }

        addScriptButton.setOnClickListener {
            showAddScriptDialog()
        }

        rebuildScriptsBar()

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

            val headerPrefix = if (aiOutputText.text.isEmpty()) "" else "\n"
            aiOutputText.append("${headerPrefix}[USER]: $prompt\n[AI]: ")
            val replyStartIndex = aiOutputText.text.length

            scope.launch {
                val assembled = StringBuilder()
                streamChatCompletions(endpoint, apiKey, model, messagesHistory) { chunk ->
                    assembled.append(chunk)
                    aiOutputText.text = aiOutputText.text.subSequence(0, replyStartIndex).toString() + assembled.toString()
                }
                val finalReply = assembled.toString()
                messagesHistory.put(JSONObject().apply {
                    put("role", "assistant")
                    put("content", finalReply)
                })
                aiOutputText.append("\n")
                sendAiButton.isEnabled = true
            }
        }

        val initialUrl = intent?.data?.toString() ?: "https://duck.ai/"
        createTab(initialUrl, switchToIt = true)
    }

    private fun rebuildScriptsBar() {
        while (scriptsStrip.childCount > 1) {
            scriptsStrip.removeViewAt(1)
        }
        val scripts = storage.loadUserScripts()
        for (s in scripts) {
            val btn = Button(this).apply {
                text = s.name
                minWidth = 0
                setPadding(16, 0, 16, 0)
                setOnClickListener { runUserScriptOnActiveTab(s) }
            }
            scriptsStrip.addView(btn)
        }
    }

    private fun runUserScriptOnActiveTab(script: UserScriptEntry) {
        val current = getActiveTab() ?: return
        val pageUrl = current.webView.url ?: current.url
        current.webView.evaluateJavascript(script.code) { rawJs ->
            val result = unescapeJsString(rawJs)
            val existing = promptInput.text.toString()
            val appended = buildString {
                if (existing.isNotBlank()) append(existing).append("\n\n")
                append("URL: ").append(pageUrl).append("\n")
                append("JS [").append(script.name).append("]:\n").append(result.take(12000))
            }
            promptInput.setText(appended)
            Toast.makeText(this, "JS ${script.name} -> prompt", Toast.LENGTH_SHORT).show()
        }
    }

    private fun showAddScriptDialog() {
        val layout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(32, 16, 32, 0)
        }
        val nameEdit = EditText(this).apply {
            hint = "Nazwa skryptu (np. Nagłówki)"
            maxLines = 1
        }
        val codeEdit = EditText(this).apply {
            hint = "Kod JS zwracający string (np. JSON.stringify(...))"
            minLines = 4
        }
        layout.addView(nameEdit)
        layout.addView(codeEdit)

        AlertDialog.Builder(this)
            .setTitle("Dodaj UserScript")
            .setView(layout)
            .setPositiveButton("ZAPISZ") { _, _ ->
                val name = nameEdit.text.toString().trim()
                val code = codeEdit.text.toString().trim()
                if (name.isNotEmpty() && code.isNotEmpty()) {
                    storage.addOrUpdateScript(name, code)
                    rebuildScriptsBar()
                }
            }
            .setNegativeButton(getString(R.string.choose_host_browser_dialog_quit), null)
            .show()
    }

    private fun exportBackupToDownloads() {
        try {
            val jsonPayload = storage.exportAllToJson()
            val dir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
            if (!dir.exists()) dir.mkdirs()
            val outFile = File(dir, "ai_browser_backup.json")
            outFile.writeText(jsonPayload, Charsets.UTF_8)
            promptInput.setText(jsonPayload)
            Toast.makeText(this, "Eksport: ${outFile.absolutePath}", Toast.LENGTH_LONG).show()
        } catch (e: Exception) {
            Toast.makeText(this, "Błąd eksportu: ${e.message}", Toast.LENGTH_SHORT).show()
        }
    }

    private fun showImportJsonDialog() {
        val input = EditText(this).apply {
            hint = "Wklej JSON (zakładki / historia / userscripts)..."
            minLines = 6
        }
        AlertDialog.Builder(this)
            .setTitle("Import JSON")
            .setView(input)
            .setPositiveButton("IMPORTUJ") { _, _ ->
                val ok = storage.importFromJson(input.text.toString())
                rebuildScriptsBar()
                Toast.makeText(this, if (ok) "Zaimportowano JSON" else "Niepoprawny JSON", Toast.LENGTH_SHORT).show()
            }
            .setNegativeButton(getString(R.string.choose_host_browser_dialog_quit), null)
            .show()
    }

    private fun showEntriesDialog(title: String, entries: List<SavedLinkEntry>) {
        if (entries.isEmpty()) {
            Toast.makeText(this, "$title: brak wpisów", Toast.LENGTH_SHORT).show()
            return
        }
        val labels = entries.map { "${it.title}\n${it.url}" }.toTypedArray()
        AlertDialog.Builder(this)
            .setTitle(title)
            .setItems(labels) { _, which ->
                val chosen = entries[which]
                showBrowserTab()
                val current = getActiveTab() ?: createTab(chosen.url, switchToIt = true)
                current.url = chosen.url
                urlInput.setText(chosen.url)
                current.webView.loadUrl(chosen.url)
            }
            .setNegativeButton(getString(R.string.choose_host_browser_dialog_quit), null)
            .show()
    }

    private fun enqueueDownload(url: String, userAgent: String?, contentDisposition: String?, mimeType: String?) {
        try {
            val uri = Uri.parse(url)
            val fileName = URLUtil.guessFileName(url, contentDisposition, mimeType)
            val cookies = CookieManager.getInstance().getCookie(url)
            val request = DownloadManager.Request(uri).apply {
                if (!mimeType.isNullOrBlank()) setMimeType(mimeType)
                if (!cookies.isNullOrBlank()) addRequestHeader("cookie", cookies)
                if (!userAgent.isNullOrBlank()) addRequestHeader("User-Agent", userAgent)
                setTitle(fileName)
                setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
                setDestinationInExternalPublicDir(Environment.DIRECTORY_DOWNLOADS, fileName)
            }
            val dm = getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
            dm.enqueue(request)
            Toast.makeText(this, "Pobieranie: $fileName", Toast.LENGTH_SHORT).show()
        } catch (e: Exception) {
            Toast.makeText(this, "Błąd pobierania: ${e.message}", Toast.LENGTH_SHORT).show()
        }
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
            setDownloadListener(DownloadListener { dlUrl, ua, cd, mime, _ ->
                enqueueDownload(dlUrl, ua, cd, mime)
            })
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
                override fun shouldInterceptRequest(view: WebView?, request: WebResourceRequest?): WebResourceResponse? {
                    val host = request?.url?.host
                    if (AdDomainFilter.isBlockedHost(host)) {
                        return WebResourceResponse("text/plain", "UTF-8", ByteArrayInputStream(ByteArray(0)))
                    }
                    return super.shouldInterceptRequest(view, request)
                }

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
                        val pageTitle = view?.title ?: t.title
                        storage.recordHistory(pageTitle, loadedUrl)
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

    private suspend fun streamChatCompletions(
        endpoint: String,
        apiKey: String,
        model: String,
        history: JSONArray,
        onChunk: suspend (String) -> Unit
    ) = withContext(Dispatchers.IO) {
        var conn: HttpURLConnection? = null
        try {
            val url = URL(endpoint)
            conn = (url.openConnection() as HttpURLConnection).apply {
                requestMethod = "POST"
                connectTimeout = 15000
                readTimeout = 120000
                doOutput = true
                setRequestProperty("Content-Type", "application/json")
                setRequestProperty("Accept", "text/event-stream")
                if (apiKey.isNotEmpty()) {
                    setRequestProperty("Authorization", "Bearer $apiKey")
                }
            }

            val payload = JSONObject().apply {
                put("model", model)
                put("messages", history)
                put("stream", true)
            }.toString()

            OutputStreamWriter(conn.outputStream, Charsets.UTF_8).use { writer ->
                writer.write(payload)
                writer.flush()
            }

            val code = conn.responseCode
            val stream = if (code in 200..299) conn.inputStream else conn.errorStream
            if (code !in 200..299) {
                val errBody = BufferedReader(InputStreamReader(stream, Charsets.UTF_8)).use { it.readText() }
                withContext(Dispatchers.Main) { onChunk("HTTP $code: $errBody") }
                return@withContext
            }

            val fullRaw = StringBuilder()
            var emittedAnySse = false

            BufferedReader(InputStreamReader(stream, Charsets.UTF_8)).use { reader ->
                var line: String?
                while (reader.readLine().also { line = it } != null) {
                    val currentLine = line ?: continue
                    fullRaw.append(currentLine).append('\n')
                    val delta = SseStreamParser.extractDeltaFromDataLine(currentLine)
                    if (!delta.isNullOrEmpty()) {
                        emittedAnySse = true
                        withContext(Dispatchers.Main) { onChunk(delta) }
                    }
                }
            }

            if (!emittedAnySse && fullRaw.isNotEmpty()) {
                val rawText = fullRaw.toString().trim()
                val fallback = try {
                    val json = JSONObject(rawText)
                    val choices = json.optJSONArray("choices")
                    if (choices != null && choices.length() > 0) {
                        choices.getJSONObject(0).optJSONObject("message")?.optString("content", rawText) ?: rawText
                    } else rawText
                } catch (_: Exception) {
                    rawText
                }
                withContext(Dispatchers.Main) { onChunk(fallback) }
            }
        } catch (e: Exception) {
            withContext(Dispatchers.Main) { onChunk("ERR: ${e.message}") }
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
