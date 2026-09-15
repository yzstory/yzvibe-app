@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)

package icu.yzvibe.android.ui

import android.content.Intent
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import icu.yzvibe.android.core.*
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject

@Composable
fun DeviceConfigurationPanel(model: AppModel, original: Device, close: () -> Unit) {
    val state by model.state.collectAsStateWithLifecycle()
    val device = state.devices.find { it.id == original.id } ?: original
    var name by remember { mutableStateOf(device.name) }
    var address by remember { mutableStateOf(device.base) }
    var error by remember { mutableStateOf<String?>(null) }
    var busy by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    ModalBottomSheet(
        onDismissRequest = { if (!busy) close() },
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
    ) {
        LazyColumn(
            Modifier.fillMaxHeight(.92f).imePadding(),
            contentPadding = PaddingValues(20.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            item { Text("设备配置", style = MaterialTheme.typography.headlineSmall) }
            item { Field(name, "设备名称") { name = it } }
            item {
                DetailCard("连接认证") {
                    DetailRow("认证方式", "设备 Token · Bearer")
                    Text(
                        "配对凭据加密保存在 Android Keystore。切换同一台电脑的地址会沿用凭据，无需填写 Token。",
                        style = MaterialTheme.typography.bodySmall,
                    )
                }
            }
            item { Text("选择连接", style = MaterialTheme.typography.titleMedium) }
            items((listOf(device.base) + device.endpoints).distinct()) { endpoint ->
                OutlinedButton(
                    onClick = { address = endpoint },
                    enabled = !busy,
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Column(Modifier.weight(1f)) {
                        Text(if (endpoint.startsWith("https")) "HTTPS 连接" else "局域网连接")
                        Text(endpoint, style = MaterialTheme.typography.bodySmall)
                    }
                    if (address == endpoint) Icon(Icons.Default.CheckCircle, null)
                }
            }
            item { Field(address, "完整连接地址（含端口）") { address = it } }
            item { Text("保存前会验证电脑身份和认证；失败时保留原连接。", style = MaterialTheme.typography.bodySmall) }
            error?.let { item { Text(it, color = MaterialTheme.colorScheme.error) } }
            item {
                Button(
                    enabled = !busy && name.isNotBlank() && address.isNotBlank(),
                    onClick = {
                        scope.launch {
                            busy = true
                            error = null
                            try {
                                model.switchDeviceEndpoint(device, name.trim(), address.trim())
                                close()
                            } catch (e: CancellationException) {
                                throw e
                            } catch (e: Exception) {
                                error = e.message
                            } finally {
                                busy = false
                            }
                        }
                    },
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Text(if (busy) "正在验证连接…" else "保存")
                }
            }
        }
    }
}

@Composable
fun DeviceDiagnosticsPanel(model: AppModel, original: Device, close: () -> Unit) {
    val state by model.state.collectAsStateWithLifecycle()
    val device = state.devices.find { it.id == original.id } ?: original
    var checks by remember { mutableStateOf<List<JSONObject>>(emptyList()) }
    var report by remember { mutableStateOf<JSONObject?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    var revision by remember { mutableIntStateOf(0) }
    var busy by remember { mutableStateOf(false) }
    var switching by remember { mutableStateOf(false) }
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val addresses = (listOf(device.base) + device.endpoints).distinct().take(6)
    LaunchedEffect(device.base, revision) {
        busy = true
        error = null
        checks = emptyList()
        report = null
        try {
            addresses.forEachIndexed { index, address ->
                val start = System.nanoTime()
                var version = ""
                val status =
                    try {
                        validateBase(address)
                        val health = model.api.json(null, "/health", base = address) as JSONObject
                        require(health.str("connectorId") == device.id) { "电脑身份不符" }
                        version = health.str("version")
                        model.api.json(device, "/sessions", base = address)
                        "身份与认证通过"
                    } catch (e: CancellationException) {
                        throw e
                    } catch (e: Exception) {
                        when {
                            e is ApiError && e.status == 401 -> "配对失效"
                            e.message == "电脑身份不符" -> "电脑身份不符"
                            else -> "无法连接"
                        }
                    }
                checks =
                    checks +
                        obj(
                            "index" to index,
                            "status" to status,
                            "version" to version,
                            "latencyMs" to (System.nanoTime() - start) / 1_000_000,
                        )
            }
            report = model.api.json(device, "/diagnostics") as JSONObject
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            error = e.message
        } finally {
            busy = false
        }
    }
    ModalBottomSheet(
        onDismissRequest = { if (!switching) close() },
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
    ) {
        LazyColumn(
            Modifier.fillMaxHeight(.92f).imePadding(),
            contentPadding = PaddingValues(20.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            item { Text("连接诊断", style = MaterialTheme.typography.headlineSmall) }
            item {
                DetailCard(device.name) {
                    DetailRow(
                        "连接状态",
                        if (state.device?.id == device.id) state.connection else "未选中",
                    )
                    if (busy) LinearProgressIndicator(Modifier.fillMaxWidth())
                }
            }
            items(checks, key = { it.optInt("index") }) { check ->
                val address = addresses.getOrNull(check.optInt("index")) ?: ""
                DetailCard(check.str("status")) {
                    Text(address, style = MaterialTheme.typography.bodySmall)
                    DetailRow("响应耗时", "${check.optLong("latencyMs")} ms")
                    if (address == device.base)
                        Text("当前使用", color = MaterialTheme.colorScheme.primary)
                    else
                        TextButton(
                            enabled = !busy && !switching,
                            onClick = {
                                scope.launch {
                                    switching = true
                                    error = null
                                    try {
                                        model.switchDeviceEndpoint(device, device.name, address)
                                    } catch (e: CancellationException) {
                                        throw e
                                    } catch (e: Exception) {
                                        error = e.message
                                    } finally {
                                        switching = false
                                    }
                                }
                            },
                        ) {
                            Text("使用此连接")
                        }
                }
            }
            report?.let { d ->
                item {
                    DetailCard("连接器") {
                        DetailRow("版本", d.str("version", "—"))
                        DetailRow("协议版本", number(d, "protocolVersion"))
                    }
                }
                items(d.items("agents")) { agent ->
                    DetailCard(agent.str("id")) {
                        DetailRow(
                            "可用状态",
                            if (agent.optBoolean("available")) "可运行 ${agent.str("version")}"
                            else "不可用",
                        )
                        DetailRow(
                            "本机认证",
                            when (agent.str("authentication")) {
                                "logged_in" -> "已登录"
                                "logged_out" -> "未登录"
                                else -> "未知"
                            },
                        )
                        Text(agent.str("advice"), style = MaterialTheme.typography.bodySmall)
                    }
                }
                item {
                    DetailCard("通知与待办") {
                        val push = d.optJSONObject("push")
                        DetailRow(
                            "电脑推送配置",
                            if (push?.optBoolean("configured") == true) "已配置" else "未配置",
                        )
                        Text("Android 厂商后台推送尚未配置。", style = MaterialTheme.typography.bodySmall)
                        DetailRow("待发送消息", number(d.optJSONObject("storage"), "pendingMessages"))
                        DetailRow(
                            "接收结果待确认",
                            number(d.optJSONObject("storage"), "uncertainMessages"),
                        )
                    }
                }
            }
            error?.let { item { Text(it, color = MaterialTheme.colorScheme.error) } }
            item {
                Row {
                    TextButton(enabled = !busy && !switching, onClick = { revision++ }) {
                        Text("重新检查")
                    }
                    TextButton(
                        enabled = !busy && checks.isNotEmpty(),
                        onClick = {
                            // Strict allowlist: never export addresses, names, credentials, advice
                            // or raw errors.
                            val safe =
                                obj(
                                    "checks" to JSONArray(checks),
                                    "version" to report?.str("version"),
                                    "protocolVersion" to report?.optInt("protocolVersion"),
                                    "storage" to
                                        obj(
                                            "sessions" to
                                                report
                                                    ?.optJSONObject("storage")
                                                    ?.optInt("sessions"),
                                            "pendingMessages" to
                                                report
                                                    ?.optJSONObject("storage")
                                                    ?.optInt("pendingMessages"),
                                            "uncertainMessages" to
                                                report
                                                    ?.optJSONObject("storage")
                                                    ?.optInt("uncertainMessages"),
                                        ),
                                    "agents" to
                                        JSONArray(
                                            report?.items("agents").orEmpty().map {
                                                obj(
                                                    "id" to it.str("id"),
                                                    "available" to it.optBoolean("available"),
                                                    "authentication" to it.str("authentication"),
                                                )
                                            }
                                        ),
                                )
                            context.startActivity(
                                Intent.createChooser(
                                    Intent(Intent.ACTION_SEND)
                                        .setType("text/plain")
                                        .putExtra(Intent.EXTRA_TEXT, safe.toString(2)),
                                    "导出脱敏诊断",
                                )
                            )
                        },
                    ) {
                        Text("导出诊断")
                    }
                }
            }
            item {
                Text(
                    "导出仅包含检查状态、版本和数量，不包含地址、设备名称、凭据及会话正文。",
                    style = MaterialTheme.typography.bodySmall,
                )
            }
        }
    }
}
