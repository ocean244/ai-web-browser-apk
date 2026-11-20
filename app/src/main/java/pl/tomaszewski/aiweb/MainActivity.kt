package pl.tomaszewski.aiweb

import android.annotation.SuppressLint
import android.content.Intent
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
import android.widget.ProgressBar
import android.widget.ScrollView
import android.widget.TextView
import androidx.activity.OnBackPressedCallback
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.launch
import java.net.URLEncoder

class MainActivity : AppCompatActivity() {

    private lateinit var webView: WebView
    private lateinit var urlInput: EditText
    private lateinit var progressBar: ProgressBar
    private lateinit var aiPanel: ScrollView
    private lateinit var aiOutputText: TextView

    @SuppressLint("SetJavaScriptEnabled")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        webView = findViewById(R.id.webView)
        urlInput = findViewById(R.id.urlInput)
        progressBar = findViewById(R.id.progressBar)
        aiPanel = findViewById(R.id.aiPanel)
        aiOutputText = findViewById(R.id.aiOutputText)

        val goBtn: Button = findViewById(R.id.goBtn)
        val aiExtractBtn: Button = findViewById(R.id.aiExtractBtn)

        CookieManager.getInstance().setAcceptCookie(true)
        CookieManager.getInstance().setAcceptThirdPartyCookies(webView, true)

        webView.settings.apply {
            javaScriptEnabled = true
            domStorageEnabled = true
            databaseEnabled = true
            loadWithOverviewMode = true
            useWideViewPort = true
            builtInZoomControls = true
            displayZoomControls = false
            mixedContentMode = WebSettings.MIXED_CONTENT_ALWAYS_ALLOW
            userAgentString = userAgentString.replace("; wv", "")
        }

        webView.webChromeClient = object : WebChromeClient() {
            override fun onProgressChanged(view: WebView?, newProgress: Int) {
                progressBar.visibility = if (newProgress in 1..99) View.VISIBLE else View.GONE
                progressBar.progress = newProgress
            }
        }

        webView.webViewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(view: WebView?, request: WebResourceRequest?): Boolean {
                val uri = request?.url ?: return false
                val scheme = uri.scheme?.lowercase().orEmpty()
                if (scheme == "http" || scheme == "https") {
                    return false
                }
                return try {
                    startActivity(Intent(Intent.ACTION_VIEW, uri))
                    true
                } catch (_: Exception) {
                    true
                }
            }

            override fun onPageFinished(view: WebView?, url: String?) {
                if (!url.isNullOrBlank()) {
                    urlInput.setText(url)
                }
            }
        }

        goBtn.setOnClickListener { navigateTo(urlInput.text.toString()) }
        urlInput.setOnEditorActionListener { _, actionId, _ ->
            if (actionId == EditorInfo.IME_ACTION_GO) {
                navigateTo(urlInput.text.toString())
                true
            } else false
        }

        aiExtractBtn.setOnClickListener {
            if (aiPanel.visibility == View.VISIBLE) {
                aiPanel.visibility = View.GONE
                return@setOnClickListener
            }
            aiPanel.visibility = View.VISIBLE
            aiOutputText.text = "Ekstrakcja DOM i analiza AI..."
            webView.evaluateJavascript("(function(){return document.body ? document.body.innerText : '';})();") { raw ->
                val unescaped = raw
                    ?.removeSurrounding("\"")
                    ?.replace("\\n", "\n")
                    ?.replace("\\t", " ")
                    ?.replace("\\\"", "\"")
                    .orEmpty()
                val currentUrl = webView.url.orEmpty()
                lifecycleScope.launch {
                    val result = AiBridgeClient.analyzePage(
                        url = currentUrl,
                        pageText = unescaped,
                        userPrompt = "Podsumuj najważniejsze fakty, linki i dane techniczne."
                    )
                    aiOutputText.text = result
                }
            }
        }

        onBackPressedDispatcher.addCallback(this, object : OnBackPressedCallback(true) {
            override fun handleOnBackPressed() {
                if (aiPanel.visibility == View.VISIBLE) {
                    aiPanel.visibility = View.GONE
                } else if (webView.canGoBack()) {
                    webView.goBack()
                } else {
                    finish()
                }
            }
        })

        val initialUrl = intent?.dataString ?: "https://duck.ai"
        navigateTo(initialUrl)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        intent.dataString?.let { navigateTo(it) }
    }

    private fun navigateTo(rawInput: String) {
        val q = rawInput.trim()
        if (q.isEmpty()) return
        val target = when {
            q.startsWith("http://") || q.startsWith("https://") -> q
            q.contains(".") && !q.contains(" ") -> "https://$q"
            else -> "https://duckduckgo.com/?q=" + URLEncoder.encode(q, "UTF-8")
        }
        webView.loadUrl(target)
    }
}
