package icu.yzvibe.android.ui

import android.annotation.SuppressLint
import android.net.Uri
import android.webkit.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.viewinterop.AndroidView
import icu.yzvibe.android.core.*
import java.io.ByteArrayInputStream
import kotlinx.coroutines.runBlocking

private const val PREVIEW_HOST = "page.yzvibe.invalid"
// The renderer has no connector credentials, native bridge, filesystem access or external network.
private const val POLICY =
    "default-src 'self' data: blob:; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline'; connect-src 'self'; frame-src 'none'; object-src 'none'; form-action 'none'; base-uri 'none'"

@SuppressLint("SetJavaScriptEnabled")
@Composable
fun HtmlPreview(
    model: AppModel,
    device: Device,
    sid: String,
    entry: String,
    modifier: Modifier,
    failure: (String) -> Unit,
) {
    val currentFailure by rememberUpdatedState(failure)
    val url = "https://$PREVIEW_HOST/" + Uri.encode(entry.substringAfterLast('/'))
    AndroidView(
        modifier = modifier,
        factory = { context ->
            WebView(context).apply {
                settings.javaScriptEnabled = true
                settings.domStorageEnabled = false
                settings.allowFileAccess = false
                settings.allowContentAccess = false
                settings.javaScriptCanOpenWindowsAutomatically = false
                settings.setSupportMultipleWindows(false)
                settings.mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
                settings.builtInZoomControls = true
                settings.displayZoomControls = false
                webViewClient =
                    object : WebViewClient() {
                        override fun shouldOverrideUrlLoading(
                            view: WebView,
                            request: WebResourceRequest,
                        ): Boolean =
                            request.url.scheme != "https" || request.url.host != PREVIEW_HOST

                        override fun shouldInterceptRequest(
                            view: WebView,
                            request: WebResourceRequest,
                        ): WebResourceResponse {
                            fun blocked() =
                                WebResourceResponse(
                                    "text/plain",
                                    "utf-8",
                                    403,
                                    "Blocked",
                                    emptyMap(),
                                    ByteArrayInputStream(ByteArray(0)),
                                )
                            if (
                                request.url.scheme != "https" ||
                                    request.url.host != PREVIEW_HOST ||
                                    request.method != "GET"
                            )
                                return blocked()
                            return try {
                                val (bytes, mime) =
                                    runBlocking {
                                        model.api.webResource(
                                            device,
                                            sid,
                                            entry,
                                            request.url.path.orEmpty().removePrefix("/"),
                                        )
                                    }
                                WebResourceResponse(
                                    mime,
                                    "utf-8",
                                    200,
                                    "OK",
                                    mapOf(
                                        "Content-Security-Policy" to POLICY,
                                        "Cache-Control" to "no-store",
                                        "X-Content-Type-Options" to "nosniff",
                                    ),
                                    ByteArrayInputStream(bytes),
                                )
                            } catch (e: Exception) {
                                if (request.isForMainFrame)
                                    view.post {
                                        currentFailure(
                                            if (e is ApiError && e.status == 404)
                                                "请更新电脑连接器以启用 HTML 页面预览"
                                            else "页面加载失败：${e.message}"
                                        )
                                    }
                                blocked()
                            }
                        }

                        override fun onReceivedError(
                            view: WebView,
                            request: WebResourceRequest,
                            error: WebResourceError,
                        ) {
                            if (request.isForMainFrame) currentFailure("页面加载失败，可切换源码查看")
                        }
                    }
                loadUrl(url)
            }
        },
        update = {},
        onRelease = {
            it.stopLoading()
            it.loadUrl("about:blank")
            it.destroy()
        },
    )
}
