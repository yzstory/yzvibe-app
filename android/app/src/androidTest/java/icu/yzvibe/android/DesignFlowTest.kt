package icu.yzvibe.android

import android.content.Intent
import android.graphics.Bitmap
import android.net.Uri
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import org.junit.Assume.assumeTrue
import org.junit.Rule
import org.junit.Test

/** Runs against tools/mock-connector.mjs; credentials arrive only via instrumentation arguments. */
class DesignFlowTest {
    @get:Rule val ui = createAndroidComposeRule<MainActivity>()

    private fun visible(text: String) =
        ui.onAllNodesWithText(text).fetchSemanticsNodes().isNotEmpty()

    private fun await(text: String) = ui.waitUntil(20_000) { visible(text) }

    private fun capture(name: String) {
        ui.waitForIdle()
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val directory = File(context.getExternalFilesDir(null), "design-review").apply { mkdirs() }
        android.os.SystemClock.sleep(600) // Let the emulator present the completed frame.
        val bitmap = ui.onRoot().captureToImage().asAndroidBitmap()
        File(directory, "$name.png").outputStream().use {
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)
        }
        bitmap.recycle()
    }

    @Test
    fun navigationSearchDraftAndApproval() {
        val pair = InstrumentationRegistry.getArguments().getString("pairUri")
        assumeTrue("Start the isolated mock connector and provide pairUri", !pair.isNullOrBlank())
        ui.activity.runOnUiThread {
            ui.activity.startActivity(
                Intent(ui.activity, MainActivity::class.java)
                    .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
                    .setData(Uri.parse(pair))
            )
        }
        await("Android 联调会话")
        ui.waitUntil(10_000) { !visible("灵感在手，随时开工") }
        ui.onNodeWithText("提示").assertDoesNotExist()
        capture("sessions")
        ui.onNodeWithText("搜索会话或路径").performTextInput("草稿保留")
        ui.onNodeWithText("Android 联调会话").assertDoesNotExist()
        ui.onNodeWithText("草稿保留测试").assertIsDisplayed()
        ui.onNodeWithContentDescription("清除搜索").performClick()
        ui.onNodeWithText("Android 联调会话").performClick()
        await("发消息给 codex")
        capture("chat")
        ui.onNodeWithText("发消息给 codex").performTextInput("视觉回归草稿")
        ui.onNodeWithContentDescription("返回").performClick()
        await("Android 联调会话")
        ui.onNodeWithText("Android 联调会话").performClick()
        ui.onNodeWithText("视觉回归草稿").assertExists()
        ui.onNode(hasSetTextAction()).performTextReplacement("deploy_test")
        ui.onNodeWithContentDescription("发送").performClick()
        ui.onNodeWithContentDescription("返回").performClick()
        ui.onAllNodesWithText("审批").onLast().performClick()
        await("允许一次")
        capture("approval")
        ui.onNodeWithText("拒绝").performClick()
        await("暂时没有待审批")
        ui.onAllNodesWithText("会话").onLast().performClick()
        ui.onNodeWithText("Android 联调会话").performClick()
        await("发消息给 codex")
        capture("conversation")
        ui.onNodeWithContentDescription("返回").performClick()
        ui.onAllNodesWithText("我").onLast().performClick()
        await("安全与提醒")
        capture("settings")
        ui.onAllNodesWithText("设备").onLast().performClick()
        await("当前设备")
        capture("devices")
    }
}
