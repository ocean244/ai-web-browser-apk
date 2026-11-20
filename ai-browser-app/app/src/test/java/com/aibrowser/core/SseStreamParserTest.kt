package com.aibrowser.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
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
}
