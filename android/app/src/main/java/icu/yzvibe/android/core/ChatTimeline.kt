package icu.yzvibe.android.core

import org.json.JSONObject

/** Presentation only: user messages, approvals, attachments and replies retain their boundaries. */
data class TimelineRow(val id: String, val messages: List<JSONObject>, val activity: Boolean)

fun chatTimeline(messages: List<JSONObject>): List<TimelineRow> {
    val rows = mutableListOf<TimelineRow>()
    val pending = mutableListOf<JSONObject>()
    fun flush() {
        if (pending.isNotEmpty()) {
            rows += TimelineRow("activity:${pending.first().str("id")}", pending.toList(), true)
            pending.clear()
        }
    }
    messages.forEach { message ->
        val assistant = message.str("role") in listOf("assistant", "tool")
        val textless = message.str("text").isBlank()
        val tools = message.items("toolCalls")
        val thinking = message.str("thinking")
        val attachments = message.optJSONArray("attachments")?.length() ?: 0
        if (assistant && textless && tools.isEmpty() && thinking.isBlank() && attachments == 0)
            return@forEach
        if (
            assistant &&
                textless &&
                message.str("approvalId").isBlank() &&
                attachments == 0 &&
                (tools.isNotEmpty() || thinking.isNotBlank())
        )
            pending += message
        else {
            flush()
            rows += TimelineRow(message.str("id"), listOf(message), false)
        }
    }
    flush()
    return rows
}
