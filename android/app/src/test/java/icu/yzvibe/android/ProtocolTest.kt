package icu.yzvibe.android

import icu.yzvibe.android.core.*
import icu.yzvibe.android.platform.readableBody
import java.time.Instant
import org.json.JSONArray
import org.junit.Assert.*
import org.junit.Test

class ProtocolTest {
    @Test
    fun pairingSupportsLanAndEscapedToken() {
        val p = Pairing.parse("yzvibe://pair?host=192.168.1.2&port=19876&token=a%2Bb&mode=local")
        assertEquals("http://192.168.1.2:19876", p.base)
        assertEquals("a+b", p.token)
    }

    @Test
    fun rejectsCredentialAndPublicCleartextAddress() {
        listOf(
                "https://user:pass@example.com",
                "http://8.8.8.8:19876",
                "https://example.com/?token=secret",
            )
            .forEach { assertTrue(runCatching { validateBase(it) }.isFailure) }
    }

    @Test
    fun snapshotThenDeltaDoesNotDuplicate() {
        val snapshot =
            obj(
                "type" to "sync.snapshot",
                "sessions" to JSONArray(),
                "approvals" to JSONArray(),
                "messages" to obj("s" to JSONArray(listOf(obj("id" to "m", "text" to "你好")))),
            )
        val delta =
            obj("type" to "message.delta", "sessionId" to "s", "messageId" to "m", "text" to "世界")
        assertEquals(
            "你好世界",
            Snapshot().reduce(snapshot).reduce(delta).messages["s"]!!.single().str("text"),
        )
        assertEquals(
            "你好",
            Snapshot().reduce(delta).reduce(snapshot).messages["s"]!!.single().str("text"),
        )
    }

    @Test
    fun unknownToolFieldsAndLateResultsArePreserved() {
        val e =
            obj(
                "type" to "tool.call",
                "sessionId" to "s",
                "messageId" to "m",
                "toolId" to "t",
                "name" to "Shell",
                "output" to "done",
            )
        val s = Snapshot().reduce(e).reduce(e.copy().put("state", "done"))
        assertEquals(1, s.messages["s"]!!.single().items("toolCalls").size)
        assertEquals("done", s.messages["s"]!!.single().items("toolCalls").single().str("output"))
    }

    @Test
    fun activeMeansSevenDaysNotRunning() {
        val now = Instant.parse("2026-09-14T10:00:00Z")
        assertTrue(recent(obj("status" to "idle", "updatedAt" to "2026-09-10T10:00:00Z"), now))
        assertFalse(recent(obj("status" to "running", "updatedAt" to "2026-09-01T10:00:00Z"), now))
    }

    @Test
    fun speechSkipsCommandsAndLogs() {
        assertEquals(
            "完成。\n\n请检查。",
            readableBody("完成。\n```sh\nrm -rf build\n```\nINFO tool complete\n请检查。"),
        )
    }
}
