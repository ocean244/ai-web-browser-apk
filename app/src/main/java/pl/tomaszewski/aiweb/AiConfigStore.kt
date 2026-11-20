package pl.tomaszewski.aiweb

import android.content.Context
import android.content.SharedPreferences

data class AiConfig(
    val endpoint: String,
    val model: String,
    val apiKey: String,
    val systemPrompt: String,
    val searchEndpoint: String
)

class AiConfigStore(context: Context) {
    private val prefs: SharedPreferences =
        context.getSharedPreferences("aiweb_prod_config", Context.MODE_PRIVATE)

    fun load(): AiConfig {
        return AiConfig(
            endpoint = prefs.getString("endpoint", "https://api.openai.com/v1/chat/completions")
                ?: "https://api.openai.com/v1/chat/completions",
            model = prefs.getString("model", "gpt-4o-mini") ?: "gpt-4o-mini",
            apiKey = prefs.getString("api_key", "") ?: "",
            systemPrompt = prefs.getString(
                "system_prompt",
                "Jesteś bezpośrednim asystentem badawczym i analitykiem sieci Web. Odpowiadaj rzeczowo, precyzyjnie i opieraj się na dostarczonym kontekście stron oraz własnej wiedzy."
            ) ?: "",
            searchEndpoint = prefs.getString("search_endpoint", "https://html.duckduckgo.com/html/?q=")
                ?: "https://html.duckduckgo.com/html/?q="
        )
    }

    fun save(cfg: AiConfig) {
        prefs.edit()
            .putString("endpoint", cfg.endpoint.trim())
            .putString("model", cfg.model.trim())
            .putString("api_key", cfg.apiKey.trim())
            .putString("system_prompt", cfg.systemPrompt)
            .putString("search_endpoint", cfg.searchEndpoint.trim())
            .apply()
    }
}
