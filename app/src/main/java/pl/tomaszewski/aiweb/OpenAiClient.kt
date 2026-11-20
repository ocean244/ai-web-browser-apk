package pl.tomaszewski.aiweb

import org.json.JSONArray
import org.json.JSONObject
import java.io.BufferedReader
import java.io.InputStreamReader
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL

class OpenAiClient(private val store: AiConfigStore) {

    fun chatCompletion(
        userPrompt: String,
        contextText: String = "",
        overrideEndpoint: String? = null,
        overrideModel: String? = null,
        overrideApiKey: String? = null
    ): JSONObject {
        val cfg = store.load()
        val targetUrl = (overrideEndpoint?.takeIf { it.isNotBlank() } ?: cfg.endpoint).trim()
        val model = (overrideModel?.takeIf { it.isNotBlank() } ?: cfg.model).trim()
        val apiKey = (overrideApiKey?.takeIf { it.isNotBlank() } ?: cfg.apiKey).trim()

        if (targetUrl.isEmpty()) {
            return JSONObject().put("ok", false).put("error", "Brak URL endpointu API")
        }
        if (model.isEmpty()) {
            return JSONObject().put("ok", false).put("error", "Brak nazwy modelu")
        }

        val messages = JSONArray()
        if (cfg.systemPrompt.isNotBlank()) {
            messages.put(
                JSONObject()
                    .put("role", "system")
                    .put("content", cfg.systemPrompt)
            )
        }

        val finalUserContent = if (contextText.isNotBlank()) {
            "KONTEKST ZE STRONY / WYSZUKIWANIA:\n${contextText.take(12000)}\n\nZADANIE:\n$userPrompt"
        } else {
            userPrompt
        }

        messages.put(
            JSONObject()
                .put("role", "user")
                .put("content", finalUserContent)
        )

        val body = JSONObject()
            .put("model", model)
            .put("messages", messages)
            .put("temperature", 0.3)

        var conn: HttpURLConnection? = null
        try {
            val url = URL(targetUrl)
            conn = (url.openConnection() as HttpURLConnection).apply {
                requestMethod = "POST"
                connectTimeout = 20000
                readTimeout = 60000
                doOutput = true
                setRequestProperty("Content-Type", "application/json; charset=utf-8")
                setRequestProperty("Accept", "application/json")
                if (apiKey.isNotEmpty()) {
                    setRequestProperty("Authorization", "Bearer $apiKey")
                }
            }

            OutputStreamWriter(conn.outputStream, Charsets.UTF_8).use { writer ->
                writer.write(body.toString())
                writer.flush()
            }

            val code = conn.responseCode
            val stream = if (code in 200..299) conn.inputStream else conn.errorStream
            val rawResponse = if (stream != null) {
                BufferedReader(InputStreamReader(stream, Charsets.UTF_8)).use { it.readText() }
            } else {
                ""
            }

            if (code !in 200..299) {
                return JSONObject()
                    .put("ok", false)
                    .put("status", code)
                    .put("error", "HTTP $code")
                    .put("raw", rawResponse)
            }

            val parsed = JSONObject(rawResponse)
            val choices = parsed.optJSONArray("choices")
            val content = choices
                ?.optJSONObject(0)
                ?.optJSONObject("message")
                ?.optString("content", "")
                ?: ""

            return JSONObject()
                .put("ok", true)
                .put("status", code)
                .put("model", model)
                .put("content", content)
                .put("raw", parsed)
        } catch (e: Exception) {
            return JSONObject()
                .put("ok", false)
                .put("error", e.message ?: e.javaClass.simpleName)
        } finally {
            conn?.disconnect()
        }
    }
}
