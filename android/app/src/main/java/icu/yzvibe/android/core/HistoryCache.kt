package icu.yzvibe.android.core

import java.io.File
import java.security.MessageDigest
import org.json.JSONArray
import org.json.JSONObject

/** Disposable, bounded history. Call on IO; never include pairing credentials. */
class HistoryCache(private val root: File, private val budget: Long = 100L * 1024 * 1024) {
    private fun file(device: String, session: String): File {
        val key =
            MessageDigest.getInstance("SHA-256")
                .digest("$device\n$session".toByteArray())
                .joinToString("") { "%02x".format(it) }
        return File(root, key)
    }

    @Synchronized
    fun load(device: String, session: String): List<JSONObject>? =
        runCatching {
                val target = file(device, session)
                require(target.length() <= budget)
                val record = JSONObject(target.readText())
                require(record.str("device") == device && record.str("session") == session)
                target.setLastModified(System.currentTimeMillis())
                record.items("messages")
            }
            .getOrNull()

    @Synchronized
    fun save(device: String, session: String, messages: List<JSONObject>) {
        runCatching {
            val data =
                obj("device" to device, "session" to session, "messages" to JSONArray(messages))
                    .toString()
                    .toByteArray()
            if (data.size > budget) return
            root.mkdirs()
            val target = file(device, session)
            val tmp = File(root, target.name + ".tmp")
            tmp.writeBytes(data)
            check(tmp.renameTo(target))
            // Rapid writes can share an mtime. Always retain the entry just saved.
            val files =
                root
                    .listFiles()
                    .orEmpty()
                    .sortedWith(compareBy<File> { it == target }.thenBy { it.lastModified() })
            var total = files.sumOf { it.length() }
            for (entry in files) if (total > budget) {
                val size = entry.length()
                if (entry.delete()) total -= size
            }
        }
    }

    @Synchronized
    fun remove(device: String, session: String) {
        file(device, session).delete()
    }
}
