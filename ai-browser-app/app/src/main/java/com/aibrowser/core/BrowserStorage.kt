package com.aibrowser.core

import android.content.SharedPreferences
import org.json.JSONArray
import org.json.JSONObject

data class SavedLinkEntry(
    val title: String,
    val url: String,
    val timestamp: Long
)

class BrowserStorage(private val prefs: SharedPreferences) {

    fun loadBookmarks(): MutableList<SavedLinkEntry> = parseList(prefs.getString("bookmarks_json", "[]") ?: "[]")

    fun saveBookmarks(items: List<SavedLinkEntry>) {
        prefs.edit().putString("bookmarks_json", serializeList(items)).apply()
    }

    fun addBookmark(title: String, url: String): MutableList<SavedLinkEntry> {
        val current = loadBookmarks()
        if (url.isNotBlank() && current.none { it.url == url }) {
            current.add(0, SavedLinkEntry(title.ifBlank { url }, url, System.currentTimeMillis()))
            saveBookmarks(current)
        }
        return current
    }

    fun loadHistory(): MutableList<SavedLinkEntry> = parseList(prefs.getString("history_json", "[]") ?: "[]")

    fun recordHistory(title: String, url: String, maxEntries: Int = 200): MutableList<SavedLinkEntry> {
        if (url.isBlank() || url.startsWith("about:")) return loadHistory()
        val current = loadHistory().filterNot { it.url == url }.toMutableList()
        current.add(0, SavedLinkEntry(title.ifBlank { url }, url, System.currentTimeMillis()))
        while (current.size > maxEntries) {
            current.removeAt(current.lastIndex)
        }
        prefs.edit().putString("history_json", serializeList(current)).apply()
        return current
    }

    private fun parseList(raw: String): MutableList<SavedLinkEntry> {
        val out = mutableListOf<SavedLinkEntry>()
        try {
            val arr = JSONArray(raw)
            for (i in 0 until arr.length()) {
                val obj = arr.optJSONObject(i) ?: continue
                val u = obj.optString("url", "")
                if (u.isNotBlank()) {
                    out.add(
                        SavedLinkEntry(
                            title = obj.optString("title", u),
                            url = u,
                            timestamp = obj.optLong("timestamp", 0L)
                        )
                    )
                }
            }
        } catch (_: Exception) {
        }
        return out
    }

    private fun serializeList(items: List<SavedLinkEntry>): String {
        val arr = JSONArray()
        for (item in items) {
            arr.put(
                JSONObject().apply {
                    put("title", item.title)
                    put("url", item.url)
                    put("timestamp", item.timestamp)
                }
            )
        }
        return arr.toString()
    }
}
