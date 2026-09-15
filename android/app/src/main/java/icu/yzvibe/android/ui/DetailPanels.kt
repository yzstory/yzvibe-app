@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)

package icu.yzvibe.android.ui

import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import icu.yzvibe.android.core.*
import java.text.NumberFormat
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import kotlinx.coroutines.CancellationException
import org.json.JSONObject

@Composable
fun DetailCard(title: String, content: @Composable ColumnScope.() -> Unit) {
    Surface(shape = RoundedCornerShape(20.dp), color = MaterialTheme.colorScheme.surface) {
        Column(
            Modifier.fillMaxWidth().padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(title, style = MaterialTheme.typography.titleMedium)
            content()
        }
    }
}

@Composable
fun DetailRow(label: String, value: String) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Text(
            label,
            Modifier.weight(1f),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Text(value, Modifier.weight(1f), style = MaterialTheme.typography.bodyMedium)
    }
}

fun number(data: JSONObject?, key: String): String =
    if (data == null || !data.has(key) || data.isNull(key)) "—"
    else NumberFormat.getIntegerInstance().format(data.optLong(key))

fun dateLabel(raw: String): String =
    runCatching {
            DateTimeFormatter.ofPattern("MM-dd HH:mm:ss")
                .withZone(ZoneId.systemDefault())
                .format(Instant.parse(raw))
        }
        .getOrDefault(raw.ifBlank { "—" })

fun toolStatus(raw: String) =
    when (raw) {
        "done",
        "completed" -> "已完成"
        "error",
        "failed" -> "失败"
        "running" -> "运行中"
        else -> "待确认"
    }

@Composable
fun SourceBlock(text: String, diff: Boolean = false) {
    Surface(
        shape = RoundedCornerShape(12.dp),
        color = MaterialTheme.colorScheme.surfaceContainerHigh,
    ) {
        SelectionContainer {
            Column(
                Modifier.fillMaxWidth()
                    .heightIn(max = 360.dp)
                    .verticalScroll(rememberScrollState())
                    .horizontalScroll(rememberScrollState())
                    .padding(12.dp)
            ) {
                text.lineSequence().forEach { line ->
                    val color =
                        when {
                            diff && line.startsWith('+') -> MaterialTheme.colorScheme.tertiary
                            diff && line.startsWith('-') -> MaterialTheme.colorScheme.error
                            diff && line.startsWith("@@") -> MaterialTheme.colorScheme.primary
                            else -> MaterialTheme.colorScheme.onSurface
                        }
                    Text(
                        line.ifEmpty { " " },
                        fontFamily = FontFamily.Monospace,
                        style = MaterialTheme.typography.bodySmall,
                        color = color,
                    )
                }
            }
        }
    }
}

@Composable
fun ToolEntry(tool: JSONObject, file: (String) -> Unit = {}) {
    var open by rememberSaveable(tool.str("id")) { mutableStateOf(false) }
    Column {
        TextButton(onClick = { open = !open }, modifier = Modifier.fillMaxWidth()) {
            Icon(Icons.Default.Terminal, null, Modifier.size(18.dp))
            Spacer(Modifier.width(8.dp))
            Text(
                tool.str("name", "工具"),
                Modifier.weight(1f),
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            Text(
                toolStatus(tool.str("state")),
                color =
                    if (tool.str("state") == "error") MaterialTheme.colorScheme.error
                    else MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Icon(if (open) Icons.Default.ExpandLess else Icons.Default.ExpandMore, null)
        }
        if (open) {
            val detail = tool.str("detail", tool.optJSONObject("input")?.toString(2).orEmpty())
            if (detail.isNotBlank()) SourceBlock(detail)
            if (tool.has("exitCode") && !tool.isNull("exitCode"))
                DetailRow("退出码", tool.optInt("exitCode").toString())
            val output = tool.str("output")
            if (output.isNotBlank()) SourceBlock(output, tool.str("outputKind") == "diff")
            else
                Text(
                    "没有可用的输出记录",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            if (tool.optBoolean("truncated"))
                Text("输出已截断", style = MaterialTheme.typography.bodySmall)
            tool.items("subagents").forEach { agent ->
                DetailRow(agent.str("name", "子代理"), toolStatus(agent.str("status")))
            }
        }
    }
}

@Composable
fun ToolGroup(
    tools: List<JSONObject>,
    id: String,
    thinking: String = "",
    file: (String) -> Unit = {},
) {
    var open by rememberSaveable(id) { mutableStateOf(false) }
    val running = tools.count { it.str("state") == "running" }
    val failed = tools.count { it.str("state") == "error" }
    Surface(
        shape = RoundedCornerShape(16.dp),
        color = MaterialTheme.colorScheme.surfaceContainerHigh,
    ) {
        Column(Modifier.fillMaxWidth().padding(8.dp)) {
            TextButton(onClick = { open = !open }, modifier = Modifier.fillMaxWidth()) {
                Icon(Icons.Default.Terminal, null, Modifier.size(20.dp))
                Spacer(Modifier.width(10.dp))
                Column(Modifier.weight(1f), horizontalAlignment = Alignment.Start) {
                    Text(if (tools.isEmpty()) "思考过程" else "工具调用 · ${tools.size} 项")
                    Text(
                        when {
                            running > 0 -> "$running 项运行中"
                            failed > 0 -> "$failed 项失败"
                            else -> tools.map { it.str("name") }.distinct().joinToString(" · ")
                        },
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                Icon(
                    if (open) Icons.Default.ExpandLess else Icons.Default.ExpandMore,
                    if (open) "折叠工具调用" else "展开工具调用",
                )
            }
            if (open) {
                tools.forEach { tool -> key(tool.str("id")) { ToolEntry(tool, file) } }
                if (thinking.isNotBlank()) SourceBlock(thinking)
            }
        }
    }
}

@Composable
fun ActivityGroup(row: TimelineRow, file: (String) -> Unit) =
    ToolGroup(
        row.messages.flatMap { it.items("toolCalls") },
        row.id,
        row.messages.map { it.str("thinking") }.filter { it.isNotBlank() }.joinToString("\n\n"),
        file,
    )

@Composable
fun ChangesPanel(model: AppModel, sid: String, session: JSONObject) {
    var scope by rememberSaveable(sid) { mutableStateOf("working") }
    var revision by remember { mutableIntStateOf(0) }
    var data by remember(sid, scope) { mutableStateOf<JSONObject?>(null) }
    var error by remember(sid, scope) { mutableStateOf<String?>(null) }
    LaunchedEffect(sid, scope, revision) {
        error = null
        try {
            data = model.call("/sessions/$sid/diff", query = mapOf("scope" to scope)) as JSONObject
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            error = e.message
        }
    }
    LazyColumn(verticalArrangement = Arrangement.spacedBy(14.dp)) {
        item {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                FilterChip(scope == "working", { scope = "working" }, { Text("全部未提交") })
                if (session.str("baseCommit").isNotBlank())
                    FilterChip(scope == "session", { scope = "session" }, { Text("这次会话") })
                IconButton(onClick = { revision++ }) { Icon(Icons.Default.Refresh, "刷新改动") }
            }
        }
        error?.let { item { Text(it, color = MaterialTheme.colorScheme.error) } }
        val d = data
        if (d == null && error == null) item { CircularProgressIndicator() }
        if (d != null) {
            if (!d.optBoolean("repo"))
                item { EmptyState("看不到改动对比", d.str("reason", "这个目录不是 Git 仓库")) }
            else if (d.items("files").isEmpty()) item { EmptyState("工作目录是干净的", "当前范围没有文件改动。") }
            else {
                item {
                    DetailCard(d.str("branch", "文件改动")) {
                        val totals = d.optJSONObject("totals")
                        DetailRow("改动文件", number(totals, "files"))
                        Row(horizontalArrangement = Arrangement.spacedBy(20.dp)) {
                            Text(
                                "+${number(totals, "added")}",
                                color = MaterialTheme.colorScheme.tertiary,
                            )
                            Text(
                                "−${number(totals, "removed")}",
                                color = MaterialTheme.colorScheme.error,
                            )
                        }
                        Text("基线 ${d.str("head", "—")}", style = MaterialTheme.typography.bodySmall)
                    }
                }
                items(d.items("files"), key = { it.str("path") }) { f ->
                    var open by
                        rememberSaveable(sid, scope, f.str("path")) { mutableStateOf(false) }
                    Surface(
                        shape = RoundedCornerShape(16.dp),
                        color = MaterialTheme.colorScheme.surface,
                    ) {
                        Column(Modifier.padding(12.dp)) {
                            TextButton(
                                onClick = { open = !open },
                                modifier = Modifier.fillMaxWidth(),
                            ) {
                                Column(Modifier.weight(1f), horizontalAlignment = Alignment.Start) {
                                    Text(
                                        f.str("path").substringAfterLast('/'),
                                        style = MaterialTheme.typography.titleSmall,
                                    )
                                    Text(
                                        f.str("path"),
                                        maxLines = 2,
                                        style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    )
                                }
                                if (!f.isNull("added"))
                                    Text("+${f.optInt("added")}  −${f.optInt("removed")}")
                                Icon(
                                    if (open) Icons.Default.ExpandLess
                                    else Icons.Default.ExpandMore,
                                    null,
                                )
                            }
                            if (open) {
                                Text(f.str("status"), style = MaterialTheme.typography.labelSmall)
                                if (f.str("diff").isNotBlank()) SourceBlock(f.str("diff"), true)
                                else
                                    Text(
                                        if (f.optBoolean("binary")) "二进制文件，无法显示文本差异"
                                        else "没有可用的文本差异"
                                    )
                            }
                        }
                    }
                }
                if (d.optBoolean("truncated")) item { Text("改动较多，当前仅展示部分内容。") }
            }
        }
    }
}

@Composable
fun RunsPanel(model: AppModel, sid: String, runs: List<JSONObject>, file: (String) -> Unit) {
    LazyColumn(verticalArrangement = Arrangement.spacedBy(14.dp)) {
        if (runs.isEmpty()) item { EmptyState("暂无执行记录", "最近 50 次任务会记录在这里。") }
        items(runs, key = { it.str("id") }) { run ->
            var open by rememberSaveable(run.str("id")) { mutableStateOf(false) }
            var detail by remember(run.str("id")) { mutableStateOf<JSONObject?>(null) }
            var error by remember { mutableStateOf<String?>(null) }
            var retry by remember { mutableIntStateOf(0) }
            LaunchedEffect(open, retry) {
                if (open && detail == null) {
                    error = null
                    try {
                        detail = model.call("/sessions/$sid/runs/${run.str("id")}") as JSONObject
                    } catch (e: CancellationException) {
                        throw e
                    } catch (e: Exception) {
                        error = e.message
                    }
                }
            }
            DetailCard(
                when (run.str("status")) {
                    "completed" -> "任务已结束"
                    "running" -> "进行中"
                    "failed" -> "执行失败"
                    else -> "执行中断 · 待确认"
                }
            ) {
                DetailRow("开始时间", dateLabel(run.str("startedAt")))
                if (run.str("endedAt").isNotBlank())
                    DetailRow("结束时间", dateLabel(run.str("endedAt")))
                TextButton(onClick = { open = !open }) { Text(if (open) "收起执行记录" else "查看执行记录") }
                if (open) {
                    if (detail == null && error == null)
                        CircularProgressIndicator(Modifier.size(24.dp))
                    error?.let {
                        Text(it)
                        TextButton(onClick = { retry++ }) { Text("重试") }
                    }
                    detail?.let { d ->
                        Text(
                            "命令完成不等于检查通过，请展开核对实际输出。",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        if (d.str("summary").isNotBlank()) Markdown(d.str("summary"), file)
                        Text("工具与检查记录", style = MaterialTheme.typography.titleSmall)
                        if (d.items("tools").isEmpty()) Text("本轮没有工具调用记录。")
                        d.items("tools").forEach { tool -> ToolEntry(tool, file) }
                        listOf("files" to "关联文件", "artifacts" to "产物").forEach { (key, label) ->
                            Text(label, style = MaterialTheme.typography.titleSmall)
                            val paths = d.optJSONArray(key)
                            if (paths == null || paths.length() == 0)
                                Text("没有记录", style = MaterialTheme.typography.bodySmall)
                            else
                                (0 until paths.length()).forEach { i ->
                                    val path = paths.optString(i)
                                    TextButton(onClick = { file(path) }) {
                                        Icon(Icons.Default.Description, null)
                                        Spacer(Modifier.width(8.dp))
                                        Text(path)
                                    }
                                }
                        }
                    }
                }
            }
        }
    }
}

/** 占用越高越警示：安全 / 琥珀 / 危险三档，与 iOS `UsageSheet.gaugeColor` 相同的阈值。 */
@Composable
private fun gauge(fraction: Float) =
    when {
        fraction > .85f -> MaterialTheme.colorScheme.error
        fraction > .6f -> MaterialTheme.accents.amber
        else -> MaterialTheme.colorScheme.tertiary
    }

@Composable
fun UsagePanel(session: JSONObject, quota: JSONObject?, refresh: () -> Unit) {
    val usage = session.optJSONObject("usage")
    val turn = usage?.optJSONObject("turn")
    val total = usage?.optJSONObject("total")
    LazyColumn(verticalArrangement = Arrangement.spacedBy(14.dp)) {
        item {
            DetailCard("上下文 · 最近调用") {
                Agent(session.str("agent"))
                Text(
                    turn?.str("model", session.str("model", "默认模型")) ?: session.str("model", "默认模型")
                )
                val known =
                    turn != null &&
                        !turn.isNull("contextTokens") &&
                        turn.optDouble("contextWindow") > 0
                val fraction =
                    if (known)
                        (turn!!.optDouble("contextTokens") / turn.optDouble("contextWindow"))
                            .toFloat()
                            .coerceIn(0f, 1f)
                    else 0f
                Text(
                    if (known) "${(fraction * 100).toInt()}% 已使用" else "暂无上下文占用数据",
                    style = MaterialTheme.typography.titleLarge,
                )
                LinearProgressIndicator(
                    progress = { fraction },
                    modifier = Modifier.fillMaxWidth(),
                    color = gauge(fraction),
                )
                DetailRow(
                    "Tokens",
                    "${number(turn, "contextTokens")} / ${number(turn, "contextWindow")}",
                )
                if (turn != null && !turn.isNull("durationMs"))
                    DetailRow("本轮耗时", "${"%.1f".format(turn.optDouble("durationMs") / 1000)} 秒")
                Text(
                    if (session.str("agent") == "omp") "上下文可能包含估算，窗口来自电脑端模型配置。"
                    else "来自最近一次模型调用；未读取到的数据以 — 表示。",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
        item {
            DetailCard("账号剩余用量") {
                TextButton(onClick = refresh) { Text("刷新账号额度") }
                if (quota == null) Text("正在读取…")
                else {
                    listOf("unavailable", "error", "warning").forEach { key ->
                        if (quota.str(key).isNotBlank())
                            Text(quota.str(key), style = MaterialTheme.typography.bodySmall)
                    }
                    quota.items("limits").forEach { limit ->
                        val percent = limit.optInt("percent").coerceIn(0, 100)
                        DetailRow(limit.str("label", "账号额度"), "剩余 ${100-percent}%")
                        LinearProgressIndicator(
                            progress = { percent / 100f },
                            modifier = Modifier.fillMaxWidth(),
                            color = gauge(percent / 100f),
                        )
                        if (limit.str("resetsAt").isNotBlank())
                            Text(
                                "重置 ${dateLabel(limit.str("resetsAt"))}",
                                style = MaterialTheme.typography.bodySmall,
                            )
                    }
                    quota
                        .optJSONObject("extraUsage")
                        ?.takeIf { it.optBoolean("enabled") }
                        ?.let { extra ->
                            DetailRow(
                                "额外用量",
                                "${extra.optDouble("usedCredits")} / ${if (extra.isNull("monthlyLimit")) "—" else extra.optDouble("monthlyLimit")} ${extra.str("currency")}",
                            )
                        }
                    if (
                        quota.items("limits").isEmpty() &&
                            listOf("unavailable", "error").all { quota.str(it).isBlank() }
                    )
                        Text("当前 Agent 未提供账号额度数据")
                }
            }
        }
        listOf("本轮累计 tokens" to turn, "会话累计 · ${number(total, "turns")} 轮" to total).forEach {
            (label, data) ->
            item {
                DetailCard(label) {
                    listOf(
                            "输入" to "input",
                            "缓存写入" to "cacheWrite",
                            "缓存命中" to "cacheRead",
                            "输出" to "output",
                            "其中思考" to "thinking",
                        )
                        .forEach { (title, key) -> DetailRow(title, number(data, key)) }
                    if (session.str("agent") != "codex" && data != null && !data.isNull("costUSD"))
                        DetailRow("费用（按目录价）", "$${"%.4f".format(data.optDouble("costUSD"))}")
                    if (session.str("agent") == "codex")
                        Text("Codex 不提供费用估算", style = MaterialTheme.typography.bodySmall)
                }
            }
        }
    }
}
