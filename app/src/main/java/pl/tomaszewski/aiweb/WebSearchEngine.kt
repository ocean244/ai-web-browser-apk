package pl.tomaszewski.aiweb

import org.json.JSONArray
import org.json.JSONObject
import java.io.BufferedReader
import java.io.InputStreamReader
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLDecoder
import java.net.URLEncoder
import java.util.regex.Pattern

class WebSearchEngine(private val store: AiConfigStore) {

    fun fetchUrlText(targetUrl: String, maxChars: Int = 12000): JSONObject {
        var conn: HttpURLConnection? = null
        try {
            val url = URL(targetUrl)
            conn = (url.openConnection() as HttpURLConnection).apply {
                requestMethod = "GET"
                connectTimeout = 15000
                readTimeout = 25000
                instanceFollowRedirects = true
                setRequestProperty("User-Agent", "Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36")
                setRequestProperty("Accept", "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8")
            }

            val code = conn.responseCode
            val stream = if (code in 200..299) conn.inputStream else conn.errorStream
            val html = if (stream != null) {
                BufferedReader(InputStreamReader(stream, Charsets.UTF_8)).use { it.readText() }
            } else {
                ""
            }

            val title = extractTitle(html)
            val cleanText = htmlToPlainText(html).take(maxChars)

            return JSONObject()
                .put("ok", code in 200..299)
                .put("status", code)
                .put("url", conn.url.toString())
                .put("title", title)
                .put("text", cleanText)
        } catch (e: Exception) {
            return JSONObject()
                .put("ok", false)
                .put("url", targetUrl)
                .put("error", e.message ?: e.javaClass.simpleName)
        } finally {
            conn?.disconnect()
        }
    }

    fun search(query: String, limit: Int = 8): JSONObject {
        val trimmed = query.trim()
        if (trimmed.isEmpty()) {
            return JSONObject().put("ok", false).put("error", "Puste zapytanie wyszukiwania")
        }

        val cfg = store.load()
        val encoded = URLEncoder.encode(trimmed, "UTF-8")
        val searchUrl = if (cfg.searchEndpoint.contains("q=")) {
            "${cfg.searchEndpoint}$encoded"
        } else {
            val sep = if (cfg.searchEndpoint.contains("?")) "&" else "?"
            "${cfg.searchEndpoint}${sep}q=$encoded"
        }

        var conn: HttpURLConnection? = null
        try {
            val url = URL(searchUrl)
            conn = (url.openConnection() as HttpURLConnection).apply {
                requestMethod = "GET"
                connectTimeout = 15000
                readTimeout = 25000
                instanceFollowRedirects = true
                setRequestProperty("User-Agent", "Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36")
            }

            val code = conn.responseCode
            val html = if (conn.inputStream != null) {
                BufferedReader(InputStreamReader(conn.inputStream, Charsets.UTF_8)).use { it.readText() }
            } else {
                ""
            }

            val results = JSONArray()
            val matcher = Pattern.compile(
                "<a[^>]*class=\"[^\"]*result__a[^\"]*\"[^>]*href=\"([^\"]+)\"[^>]*>(.*?)</a>",
                Pattern.DOTALL or Pattern.CASE_INSENSITIVE
            ).matcher(html)

            var count = 0
            while (matcher.find() && count < limit) {
                val rawHref = matcher.group(1) ?: ""
                val rawTitle = matcher.group(2) ?: ""
                val resolvedUrl = unwrapRedirectUrl(rawHref)
                val cleanTitle = stripTags(rawTitle).trim()
                if (resolvedUrl.startsWith("http") && cleanTitle.isNotEmpty()) {
                    results.put(
                        JSONObject()
                            .put("title", cleanTitle)
                            .put("url", resolvedUrl)
                    )
                    count++
                }
            }

            return JSONObject()
                .put("ok", code in 200..299)
                .put("query", trimmed)
                .put("searchUrl", searchUrl)
                .put("count", results.length())
                .put("results", results)
        } catch (e: Exception) {
            return JSONObject()
                .put("ok", false)
                .put("query", trimmed)
                .put("error", e.message ?: e.javaClass.simpleName)
        } finally {
            conn?.disconnect()
        }
    }

    private fun unwrapRedirectUrl(href: String): String {
        val decoded = decodeHtmlEntities(href)
        val uddgMatch = Pattern.compile("[?&]uddg=([^&]+)").matcher(decoded)
        if (uddgMatch.find()) {
            return try {
                URLDecoder.decode(uddgMatch.group(1) ?: decoded, "UTF-8")
            } catch (_: Exception) {
                decoded
            }
        }
        return if (decoded.startsWith("//")) "https:$decoded" else decoded
    }

    private fun extractTitle(html: String): String {
        val m = Pattern.compile("<title[^>]*>(.*?)</title>", Pattern.DOTALL or Pattern.CASE_INSENSITIVE).matcher(html)
        return if (m.find()) stripTags(m.group(1) ?: "").trim() else ""
    }

    private fun htmlToPlainText(html: String): String {
        var s = Pattern.compile("<script[^>]*>.*?</script>", Pattern.DOTALL or Pattern.CASE_INSENSITIVE).matcher(html).replaceAll(" ")
        s = Pattern.compile("<style[^>]*>.*?</style>", Pattern.DOTALL or Pattern.CASE_INSENSITIVE).matcher(s).replaceAll(" ")
        s = Pattern.compile("<[^>]+>").matcher(s).replaceAll(" ")
        s = decodeHtmlEntities(s)
        return s.replace(Regex("\\s+"), " ").trim()
    }

    private fun stripTags(html: String): String {
        return decodeHtmlEntities(html.replace(Regex("<[^>]+>"), " ")).replace(Regex("\\s+"), " ").trim()
    }

    private fun decodeHtmlEntities(input: String): String {
        return input
            .replace("&amp;", "&")
            .replace("&lt;", "<")
            .replace("&gt;", ">")
            .replace("&quot;", "\"")
            .replace("&#39;", "'")
            .replace("&nbsp;", " ")
    }
}
