package com.aibrowser.core

import android.content.SharedPreferences
import org.json.JSONArray
import org.json.JSONObject

data class SavedLinkEntry(
    val title: String,
    val url: String,
    val timestamp: Long
)

data class UserScriptEntry(
    val id: String,
    val name: String,
    val code: String
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

    fun recordHistory(title: String, url: String, maxEntries: Int = 500): MutableList<SavedLinkEntry> {
        if (url.isBlank() || url.startsWith("about:")) return loadHistory()
        val current = loadHistory().filterNot { it.url == url }.toMutableList()
        current.add(0, SavedLinkEntry(title.ifBlank { url }, url, System.currentTimeMillis()))
        while (current.size > maxEntries) {
            current.removeAt(current.lastIndex)
        }
        prefs.edit().putString("history_json", serializeList(current)).apply()
        return current
    }

    fun exportAllToJson(): String {
        return JSONObject().apply {
            put("version", 1)
            put("exportedAt", System.currentTimeMillis())
            put("bookmarks", JSONArray(serializeList(loadBookmarks())))
            put("history", JSONArray(serializeList(loadHistory())))
            put("userscripts", JSONArray(serializeScripts(loadUserScripts())))
        }.toString(2)
    }

    fun importFromJson(jsonText: String): Boolean {
        return try {
            val root = JSONObject(jsonText)
            if (root.has("bookmarks")) {
                val importedBookmarks = parseArray(root.optJSONArray("bookmarks"))
                val merged = (importedBookmarks + loadBookmarks()).distinctBy { it.url }.toMutableList()
                saveBookmarks(merged)
            }
            if (root.has("history")) {
                val importedHistory = parseArray(root.optJSONArray("history"))
                val merged = (importedHistory + loadHistory()).distinctBy { it.url }.take(500).toMutableList()
                prefs.edit().putString("history_json", serializeList(merged)).apply()
            }
            if (root.has("userscripts")) {
                val importedScripts = parseScriptsArray(root.optJSONArray("userscripts"))
                val mergedScripts = (importedScripts + loadUserScripts()).distinctBy { it.id }
                saveUserScripts(mergedScripts)
            }
            true
        } catch (_: Exception) {
            false
        }
    }

    fun loadUserScripts(): MutableList<UserScriptEntry> {
        val raw = prefs.getString("userscripts_json", null)
        if (raw == null) {
            val defaults = defaultScripts()
            saveUserScripts(defaults)
            return defaults.toMutableList()
        }
        return parseScriptsArray(try { JSONArray(raw) } catch (_: Exception) { null }).toMutableList()
    }

    fun saveUserScripts(items: List<UserScriptEntry>) {
        prefs.edit().putString("userscripts_json", serializeScripts(items)).apply()
    }

    fun addOrUpdateScript(name: String, code: String): MutableList<UserScriptEntry> {
        val current = loadUserScripts()
        val id = name.trim().lowercase().replace(Regex("[^a-z0-9]+"), "_").ifBlank { "script_${System.currentTimeMillis()}" }
        val filtered = current.filterNot { it.id == id }.toMutableList()
        filtered.add(0, UserScriptEntry(id = id, name = name.trim().ifBlank { id }, code = code))
        saveUserScripts(filtered)
        return filtered
    }

    private fun defaultScripts(): List<UserScriptEntry> = listOf(
        UserScriptEntry(
            id = "extract_links",
            name = "Linki",
            code = "(function(){ const links = Array.from(document.querySelectorAll('a[href]')).map(a => a.href); return JSON.stringify(Array.from(new Set(links)).slice(0, 200)); })()"
        ),
        UserScriptEntry(
            id = "extract_forms",
            name = "Formularze",
            code = "(function(){ const forms = Array.from(document.forms).map(f => ({ action: f.action || location.href, method: (f.method || 'GET').toUpperCase(), inputs: Array.from(f.elements).map(e => ({ name: e.name || e.id || '', type: e.type || e.tagName.toLowerCase(), value: e.value || '' })) })); return JSON.stringify(forms); })()"
        ),
        UserScriptEntry(
            id = "dark_invert",
            name = "Kontrast",
            code = "(function(){ document.documentElement.style.filter = document.documentElement.style.filter ? '' : 'invert(0.92) hue-rotate(180deg)'; return 'ok'; })()"
        ),
        UserScriptEntry(
            id = "unlock_copy",
            name = "Odblokuj",
            code = "(function(){ ['copy','cut','paste','contextmenu','selectstart'].forEach(ev => window.addEventListener(ev, e => e.stopPropagation(), true)); document.body.style.userSelect='text'; return 'unlocked'; })()"
        )
    )

    private fun parseList(raw: String): MutableList<SavedLinkEntry> {
        return try {
            parseArray(JSONArray(raw)).toMutableList()
        } catch (_: Exception) {
            mutableListOf()
        }
    }

    private fun parseArray(arr: JSONArray?): List<SavedLinkEntry> {
        val out = mutableListOf<SavedLinkEntry>()
        if (arr == null) return out
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

    private fun parseScriptsArray(arr: JSONArray?): List<UserScriptEntry> {
        val out = mutableListOf<UserScriptEntry>()
        if (arr == null) return out
        for (i in 0 until arr.length()) {
            val obj = arr.optJSONObject(i) ?: continue
            val code = obj.optString("code", "")
            if (code.isNotBlank()) {
                val name = obj.optString("name", "JS")
                out.add(
                    UserScriptEntry(
                        id = obj.optString("id", name.lowercase()),
                        name = name,
                        code = code
                    )
                )
            }
        }
        return out
    }

    private fun serializeScripts(items: List<UserScriptEntry>): String {
        val arr = JSONArray()
        for (item in items) {
            arr.put(
                JSONObject().apply {
                    put("id", item.id)
                    put("name", item.name)
                    put("code", item.code)
                }
            )
        }
        return arr.toString()
    }
}
