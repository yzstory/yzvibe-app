package icu.yzvibe.android

import icu.yzvibe.android.core.*
import kotlinx.coroutines.runBlocking
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.Assert.*
import org.junit.Test

class ApiTest {
    @Test
    fun credentialsStayInHeadersAndWritesDoNotFollowRedirects() = runBlocking {
        val server = MockWebServer()
        val other = MockWebServer()
        server.start()
        other.start()
        try {
            server.enqueue(
                MockResponse().setResponseCode(307).addHeader("Location", other.url("/"))
            )
            val api = ConnectorApi { "test-secret" }
            val d = Device("d", "test", server.url("/").toString())
            val error =
                runCatching {
                        api.json(
                            d,
                            "/sessions/s/deliveries",
                            "POST",
                            obj("clientMessageId" to "id"),
                        )
                    }
                    .exceptionOrNull() as ApiError
            assertEquals(307, error.status)
            val request = server.takeRequest()
            assertEquals("Bearer test-secret", request.getHeader("Authorization"))
            assertFalse(request.path!!.contains("secret"))
            assertEquals(0, other.requestCount)
        } finally {
            server.shutdown()
            other.shutdown()
        }
    }

    @Test
    fun retainsErrorCodeForSafeDeliveryReconciliation() = runBlocking {
        val server = MockWebServer()
        server.start()
        try {
            val api = ConnectorApi { "token" }
            val d = Device("d", "test", server.url("/").toString())
            for (code in listOf("delivery_missing", "session_missing")) {
                server.enqueue(
                    MockResponse()
                        .setResponseCode(404)
                        .setBody(obj("error" to "missing", "code" to code).toString())
                )
                val e =
                    runCatching { api.json(d, "/sessions/s/deliveries/id") }.exceptionOrNull()
                        as ApiError
                assertEquals(code, e.code)
            }
        } finally {
            server.shutdown()
        }
    }

    @Test
    fun fileQueriesPreserveReservedCharacters() {
        val url =
            ConnectorApi { "" }
                .url(
                    "http://127.0.0.1:19876",
                    "/files/stat",
                    mapOf("path" to "图片/a #1&2.md", "sessionId" to "s"),
                )
        assertEquals("图片/a #1&2.md", url.queryParameter("path"))
        assertEquals(2, url.querySize)
    }
}
