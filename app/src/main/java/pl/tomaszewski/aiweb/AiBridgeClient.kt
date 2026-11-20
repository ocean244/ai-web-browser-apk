package pl.tomaszewski.aiweb

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import java.util.concurrent.TimeUnit

object AiBridgeClient {
    private val client = OkHttpClient.Builder()
        .connectTimeout(10, TimeUnit.SECONDS)
        .readTimeout(45, TimeUnit.SECONDS)
        .build()

    suspend fun analyzePage(url: String, pageText: String, userPrompt: String): String =
        withContext(Dispatchers.IO) {
            val trimmed = pageText.replace(Regex("\\s+"), " ").trim().take(8000)
            val prompt = "URL: $url\nZadanie: $userPrompt\nTreść strony:\n$trimmed"

            try {
                val json = JSONObject().apply {
                    put("model", "qwen2.5-coder:7b")
                    put("prompt", prompt)
                    put("stream", false)
                }
                val req = Request.Builder()
                    .url("http://127.0.0.1:11434/api/generate")
                    .post(json.toString().toRequestBody("application/json".toMediaType()))
                    .build()

                client.newCall(req).execute().use { resp ->
                    if (resp.isSuccessful) {
                        val body = resp.body?.string().orEmpty()
                        val parsed = JSONObject(body).optString("response", "")
                        if (parsed.isNotBlank()) return@withContext parsed
                    }
                }
            } catch (_: Exception) {
            }

            val sentences = LocalEngineService.rankExtracts(trimmed, 8).joinToString("\n• ", prefix = "• ")
            "TRYB LOKALNY (EKSTRAKT STRONY)\nURL: $url\nSHA256: ${LocalEngineService.sha256(trimmed).take(16)}\n\nKluczowe fragmenty:\n$sentences"
        }
}
