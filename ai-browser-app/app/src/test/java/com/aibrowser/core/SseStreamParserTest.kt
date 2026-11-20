package com.aibrowser.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class SseStreamParserTest {

    @Test
    fun parsesDeltaContent() {
        val line = """data: {"choices":[{"delta":{"content":"Hello "}}]}"""
        assertEquals("Hello ", SseStreamParser.extractDeltaFromDataLine(line))
    }

    @Test
    fun returnsNullOnDoneMarker() {
        assertNull(SseStreamParser.extractDeltaFromDataLine("data: [DONE]"))
    }

    @Test
    fun blocksAdDomainsAndSubdomains() {
        assertTrue(AdDomainFilter.isBlockedHost("doubleclick.net"))
        assertTrue(AdDomainFilter.isBlockedHost("stats.g.doubleclick.net"))
        assertFalse(AdDomainFilter.isBlockedHost("duck.ai"))
    }
}
