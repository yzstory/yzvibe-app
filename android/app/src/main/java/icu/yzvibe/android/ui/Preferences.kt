package icu.yzvibe.android.ui

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.platform.LocalContext
import androidx.core.content.edit

/**
 * 客户端本地偏好，对应 iOS 的 `Settings` / `@AppStorage`。会话数据仍然只存在电脑上，
 * 这里放的是纯展示选项，所以继续用 SharedPreferences，不走加密存储。
 */
@Stable
class Preferences(context: Context) {
    private val store = context.getSharedPreferences(NAME, Context.MODE_PRIVATE)

    var appearance by mutableStateOf(Appearance.of(store.getString("appearance", null)))
        private set

    var groupByFolder by mutableStateOf(store.getBoolean("groupByFolder", true))
        private set

    var showTerminalSessions by mutableStateOf(store.getBoolean("showTerminalSessions", true))
        private set

    var activeOnly by mutableStateOf(store.getBoolean("activeOnly", false))
        private set

    var approvalAuth by mutableStateOf(store.getBoolean("approvalAuth", false))
        private set

    fun appearance(value: Appearance) {
        appearance = value
        store.edit { putString("appearance", value.key) }
    }

    fun groupByFolder(value: Boolean) {
        groupByFolder = value
        store.edit { putBoolean("groupByFolder", value) }
    }

    fun showTerminalSessions(value: Boolean) {
        showTerminalSessions = value
        store.edit { putBoolean("showTerminalSessions", value) }
    }

    fun activeOnly(value: Boolean) {
        activeOnly = value
        store.edit { putBoolean("activeOnly", value) }
    }

    fun approvalAuth(value: Boolean) {
        approvalAuth = value
        store.edit { putBoolean("approvalAuth", value) }
    }

    companion object {
        // ApprovalGate 读的是同一份文件，键名不要改。
        const val NAME = "preferences"
    }
}

val LocalPreferences = staticCompositionLocalOf<Preferences> {
    error("Preferences 必须由 App() 通过 CompositionLocalProvider 提供")
}

@Composable
fun rememberPreferences(): Preferences {
    val context = LocalContext.current
    return remember(context) { Preferences(context.applicationContext) }
}
