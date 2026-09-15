package icu.yzvibe.android

import icu.yzvibe.android.core.*
import java.nio.file.Files
import org.junit.Assert.*
import org.junit.Test

class HistoryCacheTest {
    @Test
    fun survivesRecreationAndSeparatesDevices() {
        val dir = Files.createTempDirectory("history-test").toFile()
        try {
            val cache = HistoryCache(dir)
            cache.save("a", "s", listOf(obj("id" to "m", "text" to "cached")))
            assertEquals("cached", HistoryCache(dir).load("a", "s")?.first()?.str("text"))
            assertNull(cache.load("b", "s"))
            cache.remove("a", "s")
            assertNull(cache.load("a", "s"))
        } finally {
            dir.deleteRecursively()
        }
    }

    @Test
    fun boundsStorageAndIgnoresCorruption() {
        val dir = Files.createTempDirectory("history-test").toFile()
        try {
            val cache = HistoryCache(dir, 1000)
            repeat(8) { cache.save("d", "s$it", listOf(obj("text" to "x".repeat(500)))) }
            assertTrue(dir.listFiles()!!.sumOf { it.length() } <= 1000)
            assertNotNull(cache.load("d", "s7"))
            dir.listFiles()!!.forEach { it.writeText("broken") }
            assertNull(cache.load("d", "s7"))
        } finally {
            dir.deleteRecursively()
        }
    }
}
