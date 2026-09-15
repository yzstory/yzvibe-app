package icu.yzvibe.android

import android.content.Intent
import android.graphics.Bitmap
import android.net.Uri
import android.view.View
import android.webkit.WebView
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.test.espresso.Espresso
import androidx.test.espresso.UiController
import androidx.test.espresso.ViewAction
import androidx.test.espresso.matcher.ViewMatchers.isAssignableFrom
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.util.concurrent.atomic.AtomicReference
import org.hamcrest.Matcher
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Rule
import org.junit.Test

class ParityFlowTest {
    @get:Rule val ui = createAndroidComposeRule<MainActivity>()

    private fun await(text: String) =
        ui.waitUntil(30_000) { ui.onAllNodesWithText(text).fetchSemanticsNodes().isNotEmpty() }

    private fun panel(text: String) {
        ui.onNodeWithContentDescription("更多").performClick()
        ui.onNodeWithText(text).performClick()
    }

    private fun capture(name: String) {
        ui.waitForIdle()
        android.os.SystemClock.sleep(600)
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val file = File(context.getExternalFilesDir(null), "parity-review/$name.png")
        file.parentFile!!.mkdirs()
        // Compose captureToImage resolves the Activity window for Material modal sheets.
        // Capture the composited display so Dialog windows and WebViews are included.
        val bitmap = InstrumentationRegistry.getInstrumentation().uiAutomation.takeScreenshot()
        file.outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
        bitmap.recycle()
    }

    private fun javascript(script: String): String {
        val result = AtomicReference<String?>(null)
        Espresso.onView(isAssignableFrom(WebView::class.java))
            .perform(
                object : ViewAction {
                    override fun getConstraints(): Matcher<View> =
                        isAssignableFrom(WebView::class.java)

                    override fun getDescription() = "Inspect rendered fixture DOM"

                    override fun perform(controller: UiController, view: View) {
                        (view as WebView).evaluateJavascript(script) { result.set(it) }
                    }
                }
            )
        ui.waitUntil(10_000) { result.get() != null }
        return result.get()!!
    }

    @Test
    fun longTimelineNativePanelsAndHtmlResources() {
        val pair = InstrumentationRegistry.getArguments().getString("pairUri")
        assumeTrue(!pair.isNullOrBlank())
        ui.activity.runOnUiThread {
            ui.activity.startActivity(
                Intent(ui.activity, MainActivity::class.java)
                    .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
                    .setData(Uri.parse(pair))
            )
        }
        await("长会话验收")
        ui.waitUntil(10_000) { ui.onAllNodesWithText("灵感在手，随时开工").fetchSemanticsNodes().isEmpty() }
        ui.onNodeWithText("长会话验收").performClick()
        ui.waitUntil(15_000) {
            ui.onAllNodesWithTag("timeline-bottom").fetchSemanticsNodes().isNotEmpty()
        }
        ui.waitUntil(15_000) {
            runCatching { ui.onNodeWithTag("timeline-bottom").assertIsDisplayed() }.isSuccess
        }
        capture("long-chat-bottom")
        ui.onNodeWithTag("timeline-bottom").assertIsDisplayed()
        ui.onNodeWithContentDescription("返回最新").assertDoesNotExist()
        ui.onNodeWithTag("chat-timeline").performScrollToNode(hasText("工具调用 · 80 项"))
        ui.onNodeWithText("工具调用 · 80 项").assertIsDisplayed()
        capture("long-chat")
        ui.onNodeWithContentDescription("展开工具调用").performClick()
        ui.onNodeWithContentDescription("折叠工具调用").assertExists()
        ui.onNodeWithContentDescription("折叠工具调用").performClick()
        panel("上下文")
        await("37% 已使用")
        capture("context")
        Espresso.pressBack()
        panel("改动")
        await("sample.txt")
        ui.onAllNodesWithText("sample.txt").onFirst().performClick()
        await("+after")
        capture("changes")
        Espresso.pressBack()
        ui.onNode(hasSetTextAction()).performTextInput("check_fixture")
        ui.onNodeWithContentDescription("发送").performClick()
        ui.waitUntil(15_000) {
            ui.onAllNodesWithContentDescription("停止").fetchSemanticsNodes().isNotEmpty()
        }
        ui.waitUntil(15_000) {
            ui.onAllNodesWithContentDescription("停止").fetchSemanticsNodes().isEmpty()
        }
        panel("交付记录")
        await("任务已结束")
        ui.onNodeWithText("查看执行记录").performClick()
        await("工具与检查记录")
        capture("delivery")
        Espresso.pressBack()
        panel("文件")
        await("site")
        ui.onNodeWithText("site").performClick()
        await("index.html")
        ui.onNodeWithText("index.html").performClick()
        await("页面")
        var ready = false
        repeat(30) {
            if (!ready) {
                ready =
                    javascript(
                        "document.querySelector('#state')?.textContent === 'CSS、脚本与图片已加载' && document.querySelector('#art')?.naturalWidth > 0"
                    ) == "true"
                if (!ready) android.os.SystemClock.sleep(200)
            }
        }
        assertTrue("Relative scripts and image must load", ready)
        assertEquals(
            "\"rgb(192, 75, 0)\"",
            javascript("getComputedStyle(document.querySelector('h1')).color"),
        )
        javascript("document.querySelector('button').click()")
        assertEquals("\"交互成功\"", javascript("document.querySelector('#state').textContent"))
        capture("html")
        ui.onNodeWithText("源码").performClick()
        capture("html-source")
        Espresso.pressBack()
        ui.onNodeWithContentDescription("返回").performClick()
        ui.onAllNodesWithText("设备").onLast().performClick()
        ui.onNodeWithText("配置").performClick()
        await("连接认证")
        capture("device-config")
        Espresso.pressBack()
        ui.onNodeWithText("诊断").performClick()
        await("身份与认证通过")
        capture("device-diagnostics")
    }
}
