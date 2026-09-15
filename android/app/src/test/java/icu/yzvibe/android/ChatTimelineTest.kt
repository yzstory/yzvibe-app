package icu.yzvibe.android

import icu.yzvibe.android.core.*
import org.json.JSONArray
import org.junit.Assert.*
import org.junit.Test

class ChatTimelineTest {
    private fun message(
        id: String,
        role: String = "assistant",
        text: String = "",
        tool: Boolean = false,
    ) =
        obj(
            "id" to id,
            "role" to role,
            "text" to text,
            "toolCalls" to
                JSONArray(
                    if (tool) listOf(obj("id" to "t$id", "name" to "Shell")) else emptyList<Any>()
                ),
        )

    @Test
    fun groupsLongToolRunsWithoutLosingBoundariesOrIDs() {
        val tools = (1..80).map { message("$it", tool = true) }
        val rows =
            chatTimeline(
                listOf(message("user", "user", "请求")) + tools + message("reply", text = "完成")
            )
        assertEquals(3, rows.size)
        assertTrue(rows[1].activity)
        assertEquals(tools.map { it.str("id") }, rows[1].messages.map { it.str("id") })
        assertEquals("reply", rows.last().id)
        assertEquals(rows[1].id, chatTimeline(tools + message("new", tool = true)).first().id)
    }

    @Test
    fun approvalAttachmentsAndMixedRepliesBreakGroups() {
        val approval = message("approval", tool = true).put("approvalId", "a")
        val attachment =
            message("attachment", tool = true).put("attachments", JSONArray(listOf("file")))
        val mixed = message("mixed", text = "检查说明", tool = true)
        val rows =
            chatTimeline(
                listOf(
                    message("1", tool = true),
                    approval,
                    attachment,
                    mixed,
                    message("2", tool = true),
                )
            )
        assertEquals(5, rows.size)
        assertFalse(rows[1].activity)
        assertFalse(rows[2].activity)
        assertFalse(rows[3].activity)
    }
}
