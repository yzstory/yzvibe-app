package icu.yzvibe.android.core

import java.net.URI
import java.net.URLDecoder
import java.time.Instant
import org.json.JSONArray
import org.json.JSONObject

fun obj(vararg pairs: Pair<String, Any?>) =
    JSONObject().apply { pairs.forEach { put(it.first, it.second ?: JSONObject.NULL) } }

fun JSONArray.objects(): List<JSONObject> = (0 until length()).mapNotNull { optJSONObject(it) }

fun JSONObject.items(key: String): List<JSONObject> = optJSONArray(key)?.objects().orEmpty()

fun JSONObject.str(key: String, fallback: String = ""): String =
    if (isNull(key)) fallback else optString(key, fallback)

fun JSONObject.copy() = JSONObject(toString())

fun List<JSONObject>.upsert(value: JSONObject, key: String = "id"): List<JSONObject> =
    if (any { it.str(key) == value.str(key) })
        map { if (it.str(key) == value.str(key)) value else it }
    else this + value

fun recent(session: JSONObject, now: Instant = Instant.now()): Boolean =
    runCatching { Instant.parse(session.str("updatedAt")) >= now.minusSeconds(7 * 86400) }
        .getOrDefault(false)

data class Device(
    val id: String,
    val name: String,
    val base: String,
    val endpoints: List<String> = emptyList(),
) {
    fun json() =
        obj("id" to id, "name" to name, "base" to base, "endpoints" to JSONArray(endpoints))

    companion object {
        fun from(j: JSONObject) =
            Device(
                j.str("id"),
                j.str("name"),
                j.str("base"),
                j.optJSONArray("endpoints")
                    ?.let { a -> (0 until a.length()).map { a.getString(it) } }
                    .orEmpty(),
            )
    }
}

data class Pairing(val base: String, val token: String) {
    companion object {
        fun parse(raw: String): Pairing {
            val text = raw.trim()
            val data =
                if (text.startsWith("{")) JSONObject(text)
                else {
                    val uri = URI(text)
                    require(
                        uri.scheme == "yzvibe" && uri.host == "pair" ||
                            uri.scheme in listOf("http", "https")
                    ) {
                        "请粘贴配对链接或二维码 JSON"
                    }
                    obj().apply {
                        if (uri.scheme in listOf("http", "https"))
                            put("host", "${uri.scheme}://${uri.rawAuthority}")
                        uri.rawQuery.orEmpty().split('&').forEach { part ->
                            val p = part.split('=', limit = 2)
                            if (p.size == 2) put(p[0], URLDecoder.decode(p[1], "UTF-8"))
                        }
                    }
                }
            val host = data.str("host")
            require(host.isNotBlank()) { "配对信息缺少地址" }
            val base =
                if (host.startsWith("https://") || host.startsWith("http://")) host
                else {
                    val remote = data.str("mode") == "remote" || host.endsWith("trycloudflare.com")
                    "${if (remote) "https" else "http"}://$host${if (remote) "" else ":${data.optInt("port", 19876)}"}"
                }
            validateBase(base)
            return Pairing(
                base.trimEnd('/'),
                data.str("token").also { require(it.isNotBlank()) { "配对口令为空" } },
            )
        }
    }
}

fun validateBase(raw: String) {
    val u = URI(raw)
    require(
        u.scheme in listOf("http", "https") &&
            !u.host.isNullOrBlank() &&
            u.userInfo == null &&
            u.query == null &&
            u.fragment == null &&
            u.path.orEmpty() in listOf("", "/")
    ) {
        "请填写不含口令和路径的连接器地址"
    }
    val h = u.host.lowercase()
    val lan =
        h == "localhost" ||
            h == "[::1]" ||
            h.startsWith("127.") ||
            h.startsWith("192.168.") ||
            h.startsWith("10.") ||
            Regex("172\\.(1[6-9]|2[0-9]|3[01])\\..+").matches(h) ||
            h.endsWith(".local")
    require(u.scheme == "https" || lan) { "公网连接请使用 HTTPS，HTTP 仅用于局域网" }
}

/** A single ordered WS stream applies snapshots before later deltas. Unknown fields survive. */
data class Snapshot(
    val sessions: List<JSONObject> = emptyList(),
    val approvals: List<JSONObject> = emptyList(),
    val messages: Map<String, List<JSONObject>> = emptyMap(),
) {
    fun reduce(e: JSONObject): Snapshot {
        val sid = e.str("sessionId")
        fun messageChange(change: (List<JSONObject>) -> List<JSONObject>) =
            copy(messages = messages + (sid to change(messages[sid].orEmpty())))
        return when (e.str("type")) {
            "sync.snapshot" ->
                copy(
                    sessions = e.items("sessions"),
                    approvals = e.items("approvals").filter { it.str("status") == "pending" },
                    messages =
                        messages +
                            (e.optJSONObject("messages")
                                ?.let { m -> m.keys().asSequence().associateWith { m.items(it) } }
                                .orEmpty()),
                )
            "session.created",
            "session.updated" ->
                e.optJSONObject("session")?.let { copy(sessions = sessions.upsert(it)) } ?: this
            "session.removed" ->
                copy(
                    sessions = sessions.filterNot { it.str("id") == sid },
                    messages = messages - sid,
                )
            "session.status" ->
                copy(
                    sessions =
                        sessions.map {
                            if (it.str("id") == sid) it.copy().put("status", e.str("status"))
                            else it
                        }
                )
            "message.added",
            "message.updated" ->
                e.optJSONObject("message")?.let { m -> messageChange { it.upsert(m) } } ?: this
            "message.delta" ->
                messageChange { list ->
                    val id = e.str("messageId")
                    val m =
                        list.find { it.str("id") == id }?.copy()
                            ?: obj("id" to id, "role" to "assistant", "sessionId" to sid)
                    list.upsert(m.put("text", m.str("text") + e.str("text")).put("streaming", true))
                }
            "message.done" ->
                messageChange { list ->
                    list.map {
                        if (it.str("id") == e.str("messageId")) it.copy().put("streaming", false)
                        else it
                    }
                }
            "tool.call" ->
                messageChange { list ->
                    val id = e.str("messageId")
                    val m =
                        list.find { it.str("id") == id }?.copy()
                            ?: obj("id" to id, "role" to "assistant")
                    val t = e.copy().put("id", e.str("toolId"))
                    list.upsert(m.put("toolCalls", JSONArray(m.items("toolCalls").upsert(t))))
                }
            "approval.requested" -> {
                val a = e.optJSONObject("approval") ?: e.copy().put("id", e.str("approvalId"))
                copy(approvals = approvals.upsert(a))
            }
            "approval.resolved" ->
                copy(
                    approvals =
                        approvals.filterNot {
                            it.str("id", it.str("approvalId")) == e.str("approvalId")
                        }
                )
            else -> this
        }
    }
}
