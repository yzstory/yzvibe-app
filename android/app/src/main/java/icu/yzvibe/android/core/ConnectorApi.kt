package icu.yzvibe.android.core

import java.io.File
import java.net.URLEncoder
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.*
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody
import okio.source
import org.json.JSONObject
import org.json.JSONTokener

class ApiError(val status: Int, val code: String, message: String) : Exception(message)

class ConnectorApi(private val tokenProvider: (Device) -> String) {
    constructor(store: LocalStore) : this({ device -> store.token(device.id) })

    val http =
        OkHttpClient.Builder()
            .followRedirects(false)
            .followSslRedirects(false)
            .connectTimeout(8, TimeUnit.SECONDS)
            .readTimeout(30, TimeUnit.SECONDS)
            .pingInterval(25, TimeUnit.SECONDS)
            .build()

    fun url(base: String, path: String, query: Map<String, String> = emptyMap()): HttpUrl =
        (base.trimEnd('/') + path)
            .toHttpUrl()
            .newBuilder()
            .apply { query.forEach { (k, v) -> addQueryParameter(k, v) } }
            .build()

    private fun request(d: Device?, base: String, path: String, query: Map<String, String>) =
        Request.Builder().url(url(base, path, query)).apply {
            if (d != null) header("Authorization", "Bearer ${tokenProvider(d)}")
        }

    private fun Response.checked(): Response {
        if (!isSuccessful) {
            val text = body?.string().orEmpty()
            val j = runCatching { JSONObject(text) }.getOrNull()
            throw ApiError(
                code,
                j?.str("code").orEmpty(),
                if (code == 401) "配对已失效，请重新扫码"
                else j?.str("error")?.takeIf { it.isNotBlank() } ?: "连接失败（HTTP $code）",
            )
        }
        return this
    }

    suspend fun json(
        d: Device?,
        path: String,
        method: String = "GET",
        body: JSONObject? = null,
        query: Map<String, String> = emptyMap(),
        base: String = d!!.base,
    ): Any =
        withContext(Dispatchers.IO) {
            val r =
                request(d, base, path, query)
                    .method(
                        method,
                        if (method in listOf("GET", "HEAD")) null
                        else
                            (body ?: obj())
                                .toString()
                                .toRequestBody("application/json".toMediaType()),
                    )
                    .build()
            http.newCall(r).execute().use { response ->
                val text = response.checked().body?.string().orEmpty()
                if (text.isBlank()) obj() else JSONTokener(text).nextValue()
            }
        }

    suspend fun download(d: Device, path: String, query: Map<String, String>, target: File): File =
        withContext(Dispatchers.IO) {
            http.newCall(request(d, d.base, path, query).build()).execute().use { response ->
                response.checked()
                target.parentFile?.mkdirs()
                val temp = File(target.path + ".part")
                try {
                    response.body!!.byteStream().use { input ->
                        temp.outputStream().use { input.copyTo(it) }
                    }
                    check(temp.renameTo(target))
                    target
                } finally {
                    temp.delete()
                }
            }
        }

    suspend fun webResource(
        d: Device,
        sid: String,
        entry: String,
        resource: String,
    ): Pair<ByteArray, String> =
        withContext(Dispatchers.IO) {
            http
                .newCall(
                    request(
                            d,
                            d.base,
                            "/files/web-preview",
                            mapOf("sessionId" to sid, "entry" to entry, "resource" to resource),
                        )
                        .build()
                )
                .execute()
                .use { response ->
                    response.checked()
                    val bytes =
                        response.body!!.byteStream().use { input ->
                            val out = java.io.ByteArrayOutputStream()
                            val buffer = ByteArray(8192)
                            while (true) {
                                val count = input.read(buffer)
                                if (count < 0) break
                                require(out.size() + count <= 20 * 1024 * 1024) { "页面资源超过 20 MB" }
                                out.write(buffer, 0, count)
                            }
                            out.toByteArray()
                        }
                    require(bytes.size <= 20 * 1024 * 1024) { "页面资源超过 20 MB" }
                    bytes to
                        response
                            .header("Content-Type", "application/octet-stream")!!
                            .substringBefore(';')
                }
        }

    suspend fun upload(d: Device, file: File, name: String, mime: String): String =
        withContext(Dispatchers.IO) {
            require(file.length() <= 20 * 1024 * 1024) { "单个附件最多 20 MB" }
            val body =
                object : RequestBody() {
                    override fun contentType() = mime.toMediaType()

                    override fun contentLength() = file.length()

                    override fun writeTo(sink: okio.BufferedSink) {
                        file.inputStream().use { sink.writeAll(it.source()) }
                    }
                }
            http
                .newCall(
                    request(d, d.base, "/uploads", emptyMap())
                        .header("X-Filename", URLEncoder.encode(name, "UTF-8").replace("+", "%20"))
                        .post(body)
                        .build()
                )
                .execute()
                .use { JSONObject(it.checked().body!!.string()).getString("id") }
        }

    fun socket(d: Device, listener: WebSocketListener) =
        http.newWebSocket(request(d, d.base, "/ws", emptyMap()).build(), listener)
}
