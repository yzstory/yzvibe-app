package icu.yzvibe.android.ui

import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Insights
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.adaptive.ExperimentalMaterial3AdaptiveApi
import androidx.compose.material3.adaptive.currentWindowAdaptiveInfo
import androidx.compose.material3.adaptive.navigationsuite.ExperimentalMaterial3AdaptiveNavigationSuiteApi
import androidx.compose.material3.adaptive.navigationsuite.NavigationSuiteDefaults
import androidx.compose.material3.adaptive.navigationsuite.NavigationSuiteScaffold
import androidx.compose.material3.adaptive.navigationsuite.NavigationSuiteScaffoldDefaults
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.tooling.preview.Devices
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import icu.yzvibe.android.core.obj

/**
 * 四种形态因子的预览，用来核对导航区在什么宽度切到侧边栏、页头和卡片会不会被拉散。
 * 官方 adaptive 指南要求改自适应布局前后都能在这几档上看一眼。
 */
@Preview(name = "手机", device = Devices.PHONE, showBackground = true)
@Preview(name = "折叠屏", device = Devices.FOLDABLE, showBackground = true)
@Preview(name = "平板", device = Devices.TABLET, showBackground = true)
@Preview(name = "桌面", device = Devices.DESKTOP, showBackground = true)
annotation class FormFactorPreviews

/** 浅色 / 深色两档，配色改动后先看这里。 */
@Preview(name = "浅色", showBackground = true)
@Preview(name = "深色", showBackground = true, uiMode = 0x21)
annotation class ThemePreviews

@OptIn(ExperimentalMaterial3AdaptiveApi::class, ExperimentalMaterial3AdaptiveNavigationSuiteApi::class)
@FormFactorPreviews
@Composable
private fun NavigationShellPreview() {
    YzTheme {
        NavigationSuiteScaffold(
            layoutType =
                NavigationSuiteScaffoldDefaults.calculateFromAdaptiveInfo(
                    currentWindowAdaptiveInfo()
                ),
            containerColor = MaterialTheme.colorScheme.background,
            navigationSuiteColors =
                NavigationSuiteDefaults.colors(
                    navigationBarContainerColor = MaterialTheme.colorScheme.surface,
                    navigationRailContainerColor = MaterialTheme.colorScheme.surface,
                ),
            navigationSuiteItems = {
                listOf("设备", "会话", "审批", "我").forEachIndexed { i, label ->
                    item(
                        selected = i == 1,
                        onClick = {},
                        icon = { Icon(Icons.Default.Insights, null) },
                        label = { Text(label) },
                        badge = if (i == 2) ({ Text("2") }) else null,
                    )
                }
            },
        ) {
            Column(Modifier.fillMaxSize().padding(20.dp)) {
                Text("会话", style = MaterialTheme.typography.headlineLarge)
                StatusMark("在线")
                Spacer(Modifier.height(12.dp))
                SessionCard(sample, showsPath = true, open = {}, rename = {}, delete = {})
            }
        }
    }
}

@ThemePreviews
@Composable
private fun SessionCardPreview() {
    YzTheme {
        Surface(color = MaterialTheme.colorScheme.background) {
            Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                SessionCard(sample, showsPath = true, open = {}, rename = {}, delete = {})
                SessionCard(
                    obj(
                        "id" to "s2",
                        "title" to "修一下 iOS 的审批弹窗",
                        "agent" to "claude",
                        "status" to "waiting_approval",
                        "cwd" to "/Users/hunter/devops/aigc/YzVibe",
                        "source" to "terminal",
                    ),
                    showsPath = false,
                    open = {},
                    rename = {},
                    delete = {},
                )
            }
        }
    }
}

@ThemePreviews
@Composable
private fun ToastAndSwitchPreview() {
    YzTheme {
        Surface(color = MaterialTheme.colorScheme.background) {
            Column(
                Modifier.padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Toast("已保存到电脑的 OMP", dismiss = {})
                SettingSwitch("按目录分组", "同一个工作目录的会话收在一起", true) {}
                EmptyState("从一个想法开始", "连接电脑后，点右上角新建会话。")
            }
        }
    }
}

private val sample =
    obj(
        "id" to "s1",
        "title" to "把安卓端的导航换成自适应布局",
        "agent" to "codex",
        "status" to "running",
        "branch" to "feature/adaptive-nav",
        "cwd" to "/Users/hunter/devops/aigc/YzVibe/android",
    )
