package com.aibrowser.core

import org.json.JSONObject

object SseStreamParser {
    fun extractDeltaFromDataLine(line: String): String? {
        val trimmed = line.trim()
        if (!trimmed.startsWith("data:")) return null
        val payload = trimmed.removePrefix("data:").trim()
        if (payload.isEmpty() || payload == "[DONE]") return null
        return try {
            val obj = JSONObject(payload)
            val choices = obj.optJSONArray("choices")
            if (choices != null && choices.length() > 0) {
                val choice = choices.getJSONObject(0)
                val delta = choice.optJSONObject("delta")
                if (delta != null && delta.has("content") && !delta.isNull("content")) {
                    delta.optString("content", "")
                } else {
                    val message = choice.optJSONObject("message")
                    message?.optString("content", "") ?: ""
                }
            } else {
                ""
            }
        } catch (_: Exception) {
            null
        }
    }
}
