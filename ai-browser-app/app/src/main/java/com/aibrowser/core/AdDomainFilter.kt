package com.aibrowser.core

object AdDomainFilter {
    private val blockedSuffixes = listOf(
        "doubleclick.net",
        "googlesyndication.com",
        "googleadservices.com",
        "adservice.google.com",
        "pagead2.googlesyndication.com",
        "googletagmanager.com",
        "googletagservices.com",
        "scorecardresearch.com",
        "taboola.com",
        "outbrain.com",
        "criteo.com",
        "adnxs.com",
        "pubmatic.com",
        "rubiconproject.com",
        "openx.net",
        "casalemedia.com",
        "moatads.com",
        "serving-sys.com",
        "zedo.com",
        "popads.net",
        "propellerads.com"
    )

    fun isBlockedHost(host: String?): Boolean {
        val normalized = host?.trim()?.lowercase()?.trimEnd('.') ?: return false
        if (normalized.isEmpty()) return false
        for (suffix in blockedSuffixes) {
            if (normalized == suffix || normalized.endsWith(".$suffix")) {
                return true
            }
        }
        return false
    }
}
