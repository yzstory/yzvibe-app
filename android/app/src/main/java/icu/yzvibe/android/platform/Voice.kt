package icu.yzvibe.android.platform

import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.speech.*
import android.speech.tts.TextToSpeech
import java.util.Locale

interface SpeechProvider {
    fun start(transcript: (String) -> Unit, level: (Float) -> Unit, error: (String) -> Unit)

    fun finish()

    fun cancel()

    fun close()
}

/** Cloud implementations must be explicitly configured; never silently upload audio. */
class OnDeviceSpeech(private val context: Context) : SpeechProvider {
    private var revision = 0
    private var recognizer: SpeechRecognizer? = null

    override fun start(
        transcript: (String) -> Unit,
        level: (Float) -> Unit,
        error: (String) -> Unit,
    ) {
        cancel()
        val ticket = revision
        if (
            Build.VERSION.SDK_INT < 31 || !SpeechRecognizer.isOnDeviceRecognitionAvailable(context)
        ) {
            error("此设备没有可用的离线识别服务，可使用系统键盘语音输入；云端识别尚未配置")
            return
        }
        recognizer =
            SpeechRecognizer.createOnDeviceSpeechRecognizer(context).apply {
                setRecognitionListener(
                    object : RecognitionListener {
                        override fun onReadyForSpeech(p: Bundle?) {}

                        override fun onBeginningOfSpeech() {}

                        override fun onRmsChanged(v: Float) {
                            if (ticket == revision) level((v / 10).coerceIn(0f, 1f))
                        }

                        override fun onBufferReceived(b: ByteArray?) {}

                        override fun onEndOfSpeech() {}

                        override fun onError(code: Int) {
                            if (ticket != revision) return
                            error(
                                if (
                                    code == SpeechRecognizer.ERROR_NO_MATCH ||
                                        code == SpeechRecognizer.ERROR_SPEECH_TIMEOUT
                                )
                                    "没有识别到语音"
                                else "语音识别失败（$code）"
                            )
                        }

                        override fun onResults(b: Bundle?) {
                            if (ticket != revision) return
                            b?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                                ?.firstOrNull()
                                ?.let(transcript)
                        }

                        override fun onPartialResults(b: Bundle?) {
                            if (ticket != revision) return
                            b?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                                ?.firstOrNull()
                                ?.let(transcript)
                        }

                        override fun onEvent(t: Int, p: Bundle?) {}
                    }
                )
                startListening(
                    Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH)
                        .putExtra(
                            RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                            RecognizerIntent.LANGUAGE_MODEL_FREE_FORM,
                        )
                        .putExtra(
                            RecognizerIntent.EXTRA_LANGUAGE,
                            Locale.getDefault().toLanguageTag(),
                        )
                        .putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
                        .putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, true)
                )
            }
    }

    override fun finish() {
        recognizer?.stopListening()
    }

    override fun cancel() {
        revision++
        recognizer?.cancel()
        recognizer?.destroy()
        recognizer = null
    }

    override fun close() = cancel()
}

fun readableBody(raw: String): String =
    raw.replace(Regex("(?s)```.*?(?:```|$)|~~~.*?(?:~~~|$)"), "")
        .lineSequence()
        .filterNot {
            it.trimStart().startsWith("$") ||
                it.matches(Regex("^\\s*(INFO|WARN|ERROR|DEBUG|TRACE)\\b.*"))
        }
        .joinToString("\n")
        .replace(Regex("!?\\[([^]]*)]\\([^)]*\\)"), "$1")
        .replace(Regex("[`#*_|>]"), " ")
        .trim()

class Reader(context: Context, private val error: (String) -> Unit) {
    private var ready = false
    private val tts = TextToSpeech(context) { ready = it == TextToSpeech.SUCCESS }

    fun read(text: String) {
        if (!ready) {
            error("系统朗读服务未就绪")
            return
        }
        val value = readableBody(text)
        if (value.isBlank()) return
        tts.stop()
        value.chunked(3000).forEachIndexed { i, chunk ->
            tts.speak(
                chunk,
                if (i == 0) TextToSpeech.QUEUE_FLUSH else TextToSpeech.QUEUE_ADD,
                null,
                "body-$i",
            )
        }
    }

    fun stop() = tts.stop()

    fun close() = tts.shutdown()
}
