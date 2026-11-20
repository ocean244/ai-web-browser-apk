package pl.tomaszewski.aiweb

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.security.MessageDigest

object LocalEngineService {

    suspend fun sha256(input: String): String = withContext(Dispatchers.Default) {
        val bytes = MessageDigest.getInstance("SHA-256").digest(input.toByteArray(Charsets.UTF_8))
        bytes.joinToString("") { "%02x".format(it) }
    }

    suspend fun rankExtracts(rawText: String, maxItems: Int = 6): List<String> =
        withContext(Dispatchers.Default) {
            val cleaned = rawText.replace(Regex("\\s+"), " ").trim()
            if (cleaned.isEmpty()) return@withContext emptyList()

            cleaned.split(Regex("(?<=[.!?])\\s+"))
                .map { it.trim() }
                .filter { it.length in 30..450 }
                .distinct()
                .take(maxItems)
        }
}
