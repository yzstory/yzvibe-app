package icu.yzvibe.android.ui

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.widget.VideoView
import androidx.compose.foundation.Image
import androidx.compose.foundation.gestures.detectTransformGestures
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import icu.yzvibe.android.core.*
import java.io.File
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

@Composable
fun ZoomImage(file: File, compact: Boolean = false) {
    var bitmap by remember(file.path) { mutableStateOf<Bitmap?>(null) }
    var scale by remember { mutableFloatStateOf(1f) }
    var offset by remember { mutableStateOf(Offset.Zero) }
    LaunchedEffect(file.path) {
        bitmap =
            withContext(Dispatchers.IO) {
                val options = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                BitmapFactory.decodeFile(file.path, options)
                options.inSampleSize =
                    (maxOf(options.outWidth, options.outHeight) / if (compact) 600 else 2000)
                        .coerceAtLeast(1)
                options.inJustDecodeBounds = false
                BitmapFactory.decodeFile(file.path, options)
            }
    }
    bitmap?.let { image ->
        Image(
            image.asImageBitmap(),
            "图片预览，可双指缩放",
            Modifier.fillMaxWidth()
                .height(if (compact) 150.dp else 350.dp)
                .clipToBounds()
                .pointerInput(compact) {
                    if (!compact)
                        detectTransformGestures { _, pan, zoom, _ ->
                            scale = (scale * zoom).coerceIn(1f, 5f)
                            val moved = offset + pan
                            val x = size.width * (scale - 1) / 2
                            val y = size.height * (scale - 1) / 2
                            offset = Offset(moved.x.coerceIn(-x, x), moved.y.coerceIn(-y, y))
                        }
                }
                .graphicsLayer {
                    scaleX = scale
                    scaleY = scale
                    translationX = offset.x
                    translationY = offset.y
                },
            contentScale = ContentScale.Fit,
        )
    }
}

@Composable
fun InlineImage(model: AppModel, sid: String, path: String, open: () -> Unit) {
    val context = androidx.compose.ui.platform.LocalContext.current
    var file by remember(path) { mutableStateOf<File?>(null) }
    var error by remember(path) { mutableStateOf(false) }
    LaunchedEffect(path) {
        try {
            val d = model.state.value.device ?: return@LaunchedEffect
            val target = File(context.cacheDir, "preview/thumbnail-${java.util.UUID.randomUUID()}")
            file =
                model.api.download(
                    d,
                    "/files/download",
                    mapOf("sessionId" to sid, "path" to path),
                    target,
                )
        } catch (e: Exception) {
            if (e is kotlinx.coroutines.CancellationException) throw e
            error = true
        }
    }
    Card(onClick = open, modifier = Modifier.fillMaxWidth()) {
        if (file != null) ZoomImage(file!!, true)
        else if (error) Text("图片暂不可用，点击重试", Modifier.padding(12.dp))
        else LinearProgressIndicator(Modifier.fillMaxWidth())
    }
}

@Composable
fun Video(file: File) {
    AndroidView(
        factory = { context ->
            VideoView(context).apply {
                setVideoPath(file.path)
                setMediaController(
                    android.widget.MediaController(context).also { it.setAnchorView(this) }
                )
                setOnPreparedListener { seekTo(1) }
            }
        },
        modifier = Modifier.fillMaxWidth().height(300.dp),
        onRelease = { it.stopPlayback() },
    )
}

fun localImageReferences(text: String): List<String> =
    Regex("!?\\[[^]]*]\\(([^)]+)\\)|`([^`\\n]+)`")
        .findAll(text)
        .map { it.groupValues[1].ifBlank { it.groupValues[2] } }
        .filter {
            !it.startsWith("http:") &&
                !it.startsWith("https:") &&
                it.substringAfterLast('.').lowercase() in
                    listOf("png", "jpg", "jpeg", "webp", "gif")
        }
        .distinct()
        .take(6)
        .toList()

/** Turn inline file references into links while leaving command/code blocks intact. */
fun linkLocalFiles(text: String): String {
    var fence: String? = null
    return text
        .lineSequence()
        .map { line ->
            val trimmed = line.trimStart()
            val marker =
                when {
                    trimmed.startsWith("```") -> "```"
                    trimmed.startsWith("~~~") -> "~~~"
                    else -> null
                }
            if (marker != null) {
                if (fence == null) fence = marker else if (fence == marker) fence = null
                line
            } else if (fence != null) line
            else
                Regex(
                        "`([^`\\n]+\\.(?:md|markdown|png|jpe?g|webp|gif|mp4|mov|webm|pdf))`",
                        RegexOption.IGNORE_CASE,
                    )
                    .replace(line) { match ->
                        val path = match.groupValues[1]
                        if (path.startsWith("http") || path.contains("\u0000")) match.value
                        else
                            "[${path.replace("]", "\\]")}](file://${android.net.Uri.encode(path, "/~.")})"
                    }
        }
        .joinToString("\n")
}
