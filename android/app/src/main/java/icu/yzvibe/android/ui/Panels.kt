@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)

package icu.yzvibe.android.ui

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.core.content.FileProvider
import icu.yzvibe.android.core.*
import icu.yzvibe.android.platform.approvalGate
import java.io.File
import java.util.UUID
import kotlin.math.roundToInt
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject

@Composable
fun Approvals(model: AppModel, approvals: List<JSONObject>) {
    val context = LocalContext.current
    LazyColumn(
        Modifier.fillMaxSize().padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        if (approvals.isEmpty()) item { Text("没有待审批的请求", Modifier.padding(24.dp)) }
        items(approvals, key = { it.str("id", it.str("approvalId")) }) { a ->
            val id = a.str("id", a.str("approvalId"))
            var answers by remember(id) { mutableStateOf(mapOf<String, String>()) }
            var rememberRule by remember(id) { mutableStateOf(false) }
            Card {
                Column(Modifier.fillMaxWidth().padding(16.dp)) {
                    Text(a.str("summary"), style = MaterialTheme.typography.titleMedium)
                    Text("风险：${a.str("risk")}", color = Orange)
                    Markdown(a.str("detail"))
                    a.items("questions").forEach { q ->
                        val qid = q.str("id", q.str("question"))
                        Field(answers[qid].orEmpty(), q.str("question", q.str("header"))) {
                            answers = answers + (qid to it)
                        }
                        q.items("options").forEach { option ->
                            TextButton(
                                onClick = { answers = answers + (qid to option.str("label")) }
                            ) {
                                Text(option.str("label"))
                            }
                        }
                    }
                    if (a.items("suggestions").isNotEmpty())
                        Row {
                            Checkbox(rememberRule, { rememberRule = it })
                            Text(a.items("suggestions").first().str("label", "记住此审批规则"))
                        }
                    Row {
                        TextButton(
                            onClick = {
                                model.action("/approvals/$id", body = obj("decision" to "deny"))
                            }
                        ) {
                            Text("拒绝")
                        }
                        Spacer(Modifier.weight(1f))
                        Button(
                            enabled =
                                a.items("questions").all {
                                    answers[it.str("id", it.str("question"))].orEmpty().isNotBlank()
                                },
                            onClick = {
                                approvalGate(context, model::report) {
                                    model.action(
                                        "/approvals/$id",
                                        body =
                                            obj(
                                                "decision" to "allow_once",
                                                "answers" to JSONObject(answers),
                                                "remember" to
                                                    if (rememberRule)
                                                        a.items("suggestions").firstOrNull()
                                                    else null,
                                            ),
                                    )
                                }
                            },
                        ) {
                            Text("允许")
                        }
                    }
                    if (a.items("questions").isEmpty())
                        TextButton(
                            onClick = {
                                approvalGate(context, model::report) {
                                    model.action("/approvals/$id/trust")
                                }
                            }
                        ) {
                            Text("切换此会话到 Trust 并允许")
                        }
                }
            }
        }
    }
}

@Composable
fun SessionPanel(
    model: AppModel,
    state: AppModel.State,
    session: JSONObject,
    panel: String,
    file: (String) -> Unit,
    navigatePanel: (String) -> Unit,
    close: () -> Unit,
) {
    val sid = session.str("id")
    var data by remember(panel) { mutableStateOf<Any?>(null) }
    var error by remember(panel) { mutableStateOf<String?>(null) }
    val capability = state.capabilities.optJSONObject(session.str("agent")) ?: obj()
    val haptic = LocalHapticFeedback.current
    LaunchedEffect(panel) {
        try {
            data =
                when (panel) {
                    "文件" -> model.call("/files", query = mapOf("sessionId" to sid))
                    "改动" -> model.call("/sessions/$sid/diff", query = mapOf("scope" to "session"))
                    "交付记录" -> model.call("/sessions/$sid/runs", query = mapOf("summary" to "1"))
                    "命令",
                    "技能" -> model.call("/sessions/$sid/commands")
                    "规则" -> model.call("/rules", query = mapOf("sessionId" to sid))
                    "上下文" ->
                        obj(
                            "会话用量" to session.optJSONObject("usage"),
                            "账号用量" to
                                model.call("/quota", query = mapOf("agent" to session.str("agent"))),
                        )
                    else -> obj()
                }
        } catch (e: Exception) {
            error = e.message
        }
    }
    ModalBottomSheet(onDismissRequest = close) {
        Column(Modifier.fillMaxWidth().heightIn(max = 620.dp).padding(20.dp)) {
            Text(panel, style = MaterialTheme.typography.headlineSmall)
            error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
            if (data == null && error == null) CircularProgressIndicator(Modifier.padding(30.dp))
            when (panel) {
                "审批" ->
                    Approvals(model, state.snapshot.approvals.filter { it.str("sessionId") == sid })
                "模型",
                "模式",
                "思考强度" -> {
                    val key =
                        when (panel) {
                            "模型" -> "model"
                            "模式" -> "mode"
                            else -> "effort"
                        }
                    val options =
                        when (key) {
                            "mode" ->
                                JSONArray(
                                    capability
                                        .optJSONObject("modes")
                                        ?.let { modes ->
                                            modes
                                                .keys()
                                                .asSequence()
                                                .map { id ->
                                                    obj(
                                                        "id" to id,
                                                        "label" to
                                                            "$id · ${modes.optJSONObject(id)?.str("description").orEmpty()}",
                                                    )
                                                }
                                                .toList()
                                        }
                                        .orEmpty()
                                )
                            "model" -> capability.optJSONArray("models") ?: JSONArray()
                            else -> {
                                val selected =
                                    capability.items("models").find {
                                        it.str("id") == session.str("model")
                                    }
                                val efforts =
                                    selected?.optJSONArray("efforts")
                                        ?: capability.optJSONArray("efforts")
                                        ?: JSONArray()
                                JSONArray(efforts.toString()).apply {
                                    if (
                                        session.str("agent") != "omp" &&
                                            (0 until length()).none { optString(it) == "ultra" }
                                    )
                                        put("ultra")
                                }
                            }
                        }
                    if (key == "effort") {
                        val available =
                            (0 until options.length()).map {
                                options.optJSONObject(it)?.str("id") ?: options.optString(it)
                            }
                        val values = listOf("") + available.filter { it.isNotEmpty() }
                        var index by remember {
                            mutableIntStateOf(
                                values.indexOf(session.str("effort")).coerceAtLeast(0)
                            )
                        }
                        Text(
                            values.getOrElse(index) { "" }.ifBlank { "默认" },
                            Modifier.padding(16.dp),
                            style = MaterialTheme.typography.titleLarge,
                        )
                        if (values.size > 1)
                            Slider(
                                value = index.toFloat(),
                                onValueChange = {
                                    val next = it.roundToInt()
                                    if (next != index) {
                                        index = next
                                        haptic.performHapticFeedback(
                                            HapticFeedbackType.TextHandleMove
                                        )
                                    }
                                },
                                valueRange = 0f..values.lastIndex.toFloat(),
                                steps = (values.size - 2).coerceAtLeast(0),
                                onValueChangeFinished = {
                                    model.action(
                                        "/sessions/$sid",
                                        "PATCH",
                                        obj(key to values[index].ifBlank { null }),
                                    )
                                },
                            )
                        else Text("当前模型没有可调思考强度")
                    } else
                        LazyColumn {
                            item {
                                TextButton(
                                    onClick = {
                                        model.action("/sessions/$sid", "PATCH", obj(key to null))
                                        close()
                                    }
                                ) {
                                    Text("默认")
                                }
                            }
                            items(options.length()) { i ->
                                val item = options.optJSONObject(i)
                                val id = item?.str("id") ?: options.optString(i)
                                TextButton(
                                    onClick = {
                                        model.action("/sessions/$sid", "PATCH", obj(key to id))
                                        close()
                                    }
                                ) {
                                    Text(item?.str("label", id) ?: id)
                                }
                            }
                        }
                }
                "命令",
                "技能" -> {
                    val j = data as? JSONObject
                    val keys =
                        if (panel == "技能") listOf("skills")
                        else listOf("app", "agentCommands", "prompts")
                    LazyColumn {
                        keys.forEach { key ->
                            items(j?.items(key).orEmpty()) { command ->
                                TextButton(
                                    onClick = {
                                        val value =
                                            if (command.optBoolean("insertAsText"))
                                                "参考 skill「${command.str("name")}」："
                                            else "/${command.str("name")} "
                                        if (key == "app") {
                                            when (command.str("action")) {
                                                "stop" -> model.action("/sessions/$sid/stop")
                                                "new-session" ->
                                                    model.launch {
                                                        val created =
                                                            model.call(
                                                                "/sessions",
                                                                "POST",
                                                                obj(
                                                                    "agent" to session.str("agent"),
                                                                    "cwd" to session.str("cwd"),
                                                                ),
                                                            ) as JSONObject
                                                        model.openSession(created.str("id"))
                                                        close()
                                                    }
                                                else ->
                                                    navigatePanel(
                                                        when (command.str("action")) {
                                                            "diff" -> "改动"
                                                            "files" -> "文件"
                                                            "usage" -> "上下文"
                                                            "model" -> "模型"
                                                            "effort" -> "思考强度"
                                                            "mode" -> "模式"
                                                            "rules" -> "规则"
                                                            else -> "命令"
                                                        }
                                                    )
                                            }
                                        } else {
                                            model.draft(
                                                model.state.value.draft.str("text") + " " + value
                                            )
                                            close()
                                        }
                                    }
                                ) {
                                    Column {
                                        Text(command.str("name", command.str("command")))
                                        Text(
                                            command.str("description"),
                                            style = MaterialTheme.typography.bodySmall,
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
                "文件" ->
                    RemoteFiles(model, sid) {
                        file(it)
                        close()
                    }
                "规则" ->
                    LazyColumn {
                        items((data as? JSONArray)?.objects().orEmpty()) { rule ->
                            Text(rule.str("description"))
                            TextButton(
                                onClick = {
                                    model.action("/rules/${rule.str("id")}", "DELETE")
                                    close()
                                }
                            ) {
                                Text("删除规则")
                            }
                        }
                    }
                "交付记录" ->
                    LazyColumn {
                        items((data as? JSONArray)?.objects().orEmpty()) { run ->
                            var detail by remember { mutableStateOf<JSONObject?>(null) }
                            TextButton(
                                onClick = {
                                    model.launch {
                                        detail =
                                            model.call("/sessions/$sid/runs/${run.str("id")}")
                                                as JSONObject
                                    }
                                }
                            ) {
                                Text("${run.str("status")} · ${run.str("startedAt")}")
                            }
                            detail?.let { Markdown(it.toString(2)) }
                        }
                    }
                else ->
                    Box(Modifier.verticalScroll(rememberScrollState())) {
                        Markdown(
                            when (val d = data) {
                                is JSONObject -> "```json\n${d.toString(2)}\n```"
                                is JSONArray -> d.toString(2)
                                else -> ""
                            },
                            file,
                        )
                    }
            }
            Spacer(Modifier.height(30.dp))
        }
    }
}

@Composable
fun DirectoryPicker(model: AppModel, initial: String, select: (String) -> Unit, close: () -> Unit) {
    var path by remember { mutableStateOf(initial) }
    var data by remember { mutableStateOf(obj()) }
    var error by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(path) {
        try {
            data =
                model.call(
                    "/fs/dirs",
                    query = if (path.isBlank()) emptyMap() else mapOf("path" to path),
                ) as JSONObject
        } catch (e: Exception) {
            error = e.message
        }
    }
    ModalBottomSheet(onDismissRequest = close) {
        Column(Modifier.padding(24.dp).heightIn(max = 550.dp)) {
            Text("选择工作目录")
            Text(data.str("path"))
            error?.let { Text(it) }
            Row {
                TextButton(onClick = { path = data.str("parent", path.substringBeforeLast('/')) }) {
                    Text("上一级")
                }
                Button(onClick = { select(data.str("path", path)) }) { Text("使用此目录") }
            }
            LazyColumn {
                items(data.items("directories").ifEmpty { data.items("entries") }) { d ->
                    TextButton(
                        onClick = { path = d.str("path", "${data.str("path")}/${d.str("name")}") }
                    ) {
                        Icon(Icons.Default.Folder, null)
                        Text(d.str("name"))
                    }
                }
            }
        }
    }
}

@Composable
fun FilePreview(
    model: AppModel,
    sid: String,
    path: String,
    navigate: (String) -> Unit,
    close: () -> Unit,
) {
    val context = LocalContext.current
    var local by remember(path) { mutableStateOf<File?>(null) }
    var body by remember(path) { mutableStateOf<String?>(null) }
    var mime by remember(path) { mutableStateOf("") }
    var error by remember(path) { mutableStateOf<String?>(null) }
    LaunchedEffect(path) {
        try {
            val d = model.state.value.device ?: error("未连接")
            val upload = path.startsWith("upload:")
            val id = path.removePrefix("upload:")
            val meta =
                model.call(
                    if (upload) "/uploads/$id/info" else "/files/stat",
                    query = if (upload) emptyMap() else mapOf("sessionId" to sid, "path" to path),
                ) as JSONObject
            val name = meta.str("filename", meta.str("name", path.substringAfterLast('/')))
            mime = meta.str("mime", "application/octet-stream")
            require(!meta.optBoolean("directory")) { "请选择具体文件" }
            val target = File(context.cacheDir, "preview/${UUID.randomUUID()}/${File(name).name}")
            local =
                model.api.download(
                    d,
                    if (upload) "/uploads/$id" else "/files/download",
                    if (upload) emptyMap() else mapOf("sessionId" to sid, "path" to path),
                    target,
                )
            if (mime.startsWith("text/") || name.endsWith(".md") || name.endsWith(".json"))
                body =
                    withContext(Dispatchers.IO) {
                        require(target.length() <= 2 * 1024 * 1024) { "文本超过 2 MB，请用其他应用打开" }
                        target.readText()
                    }
        } catch (e: Exception) {
            error = e.message
        }
    }
    ModalBottomSheet(onDismissRequest = close) {
        Column(Modifier.fillMaxWidth().heightIn(max = 700.dp).padding(20.dp)) {
            Text(path.substringAfterLast('/'), style = MaterialTheme.typography.titleMedium)
            error?.let { Text(it) }
            if (local == null && error == null) CircularProgressIndicator()
            local?.let { target ->
                val uri =
                    FileProvider.getUriForFile(context, context.packageName + ".files", target)
                Row {
                    TextButton(
                        onClick = {
                            runCatching {
                                    context.startActivity(
                                        Intent(Intent.ACTION_VIEW)
                                            .setDataAndType(uri, mime)
                                            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                    )
                                }
                                .onFailure { model.report("没有可以打开该格式的应用") }
                        }
                    ) {
                        Text("打开 / 播放")
                    }
                    TextButton(
                        onClick = {
                            context.startActivity(
                                Intent.createChooser(
                                    Intent(Intent.ACTION_SEND)
                                        .setType(mime)
                                        .putExtra(Intent.EXTRA_STREAM, uri)
                                        .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION),
                                    "分享文件",
                                )
                            )
                        }
                    ) {
                        Text("分享")
                    }
                }
                if (body != null)
                    Box(Modifier.verticalScroll(rememberScrollState())) {
                        Markdown(body!!) { link ->
                            if (link.startsWith("http://") || link.startsWith("https://"))
                                context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(link)))
                            else {
                                val local =
                                    Uri.decode(link.removePrefix("file://").substringBefore('#'))
                                if (local.isNotBlank())
                                    navigate(
                                        if (local.startsWith('/') || local.startsWith("~")) local
                                        else
                                            path.substringBeforeLast('/', "").let { parent ->
                                                if (parent.isBlank()) local else "$parent/$local"
                                            }
                                    )
                            }
                        }
                    }
                else if (mime.startsWith("image/")) ZoomImage(target)
                else if (mime.startsWith("video/")) Video(target)
            }
            Spacer(Modifier.height(24.dp))
        }
    }
}

@Composable
fun Settings(model: AppModel) {
    val settingsContext = LocalContext.current
    var auth by remember {
        mutableStateOf(
            settingsContext
                .getSharedPreferences("preferences", android.content.Context.MODE_PRIVATE)
                .getBoolean("approvalAuth", false)
        )
    }
    val notificationPermission =
        androidx.activity.compose.rememberLauncherForActivityResult(
            androidx.activity.result.contract.ActivityResultContracts.RequestPermission()
        ) {}
    var panel by remember { mutableStateOf("") }
    var data by remember { mutableStateOf<Any?>(null) }
    Column(Modifier.padding(24.dp).verticalScroll(rememberScrollState())) {
        Text("柚子Vibe · Android", style = MaterialTheme.typography.headlineSmall)
        Row {
            Checkbox(
                auth,
                {
                    auth = it
                    settingsContext
                        .getSharedPreferences("preferences", android.content.Context.MODE_PRIVATE)
                        .edit()
                        .putBoolean("approvalAuth", it)
                        .apply()
                },
            )
            Text("远程审批前验证指纹或锁屏密码")
        }
        Text("语音默认使用设备离线识别；朗读使用 Android 系统 TTS。", Modifier.padding(vertical = 16.dp))
        Text("后台推送尚未配置。当前版本仅在应用保持前台连接时同步，锁屏后请回到应用检查审批。", color = Orange)
        TextButton(
            onClick = {
                if (android.os.Build.VERSION.SDK_INT >= 33)
                    notificationPermission.launch(android.Manifest.permission.POST_NOTIFICATIONS)
            }
        ) {
            Text("开启任务和审批提醒")
        }
        listOf("OMP 模型配置", "审批规则", "连接诊断").forEach { title ->
            TextButton(
                onClick = {
                    model.launch {
                        data =
                            model.call(
                                when (title) {
                                    "OMP 模型配置" -> "/agents/omp/config"
                                    "审批规则" -> "/rules"
                                    else -> "/diagnostics"
                                }
                            )
                        panel = title
                    }
                }
            ) {
                Text(title)
            }
        }
        TextButton(onClick = { model.action("/sessions/hidden", "DELETE") }) { Text("恢复隐藏会话") }
    }
    if (panel == "OMP 模型配置") OmpSettings(model, data as? JSONObject ?: obj()) { panel = "" }
    else if (panel.isNotEmpty())
        ModalBottomSheet(onDismissRequest = { panel = "" }) {
            Column(Modifier.padding(20.dp).verticalScroll(rememberScrollState())) {
                Text(panel)
                if (panel == "审批规则")
                    (data as? JSONArray)?.objects()?.forEach { r ->
                        Text(r.str("description"))
                        TextButton(
                            onClick = {
                                model.action("/rules/${r.str("id")}", "DELETE")
                                panel = ""
                            }
                        ) {
                            Text("删除规则")
                        }
                    }
                else Markdown((data as? JSONObject)?.toString(2).orEmpty())
                Spacer(Modifier.height(30.dp))
            }
        }
}

@Composable
fun OmpSettings(model: AppModel, initial: JSONObject, close: () -> Unit) {
    var config by remember { mutableStateOf(initial) }
    var selected by remember { mutableStateOf<JSONObject?>(null) }
    var base by remember { mutableStateOf("") }
    var name by remember { mutableStateOf("") }
    var key by remember { mutableStateOf("") }
    ModalBottomSheet(onDismissRequest = close) {
        Column(Modifier.padding(24.dp).verticalScroll(rememberScrollState()).imePadding()) {
            Text("OMP 模型配置", style = MaterialTheme.typography.headlineSmall)
            Text("保存到当前电脑的 OMP，密钥不回显；仅进入此页与保存时同步。", Modifier.padding(vertical = 12.dp))
            config.items("models").forEach { m ->
                TextButton(
                    enabled = m.optBoolean("editable"),
                    onClick = {
                        selected = m
                        base = m.str("baseUrl")
                        name = m.str("modelName")
                        key = ""
                    },
                ) {
                    Text(m.str("label", m.str("id")))
                }
            }
            TextButton(
                onClick = {
                    selected = null
                    base = ""
                    name = ""
                    key = ""
                }
            ) {
                Text("添加新模型")
            }
            Field(base, "Base URL") { base = it }
            Field(name, "Model name") { name = it }
            OutlinedTextField(
                key,
                { key = it },
                label = { Text(if (selected == null) "API Key" else "API Key（留空保留）") },
                visualTransformation = PasswordVisualTransformation(),
                modifier = Modifier.fillMaxWidth(),
            )
            Button(
                onClick = {
                    model.launch {
                        val input =
                            obj(
                                "revision" to config.str("revision"),
                                "baseUrl" to base,
                                "modelName" to name,
                                "key" to key,
                            )
                        selected?.let {
                            input
                                .put("providerId", it.str("providerId"))
                                .put("originalModelName", it.str("modelName"))
                        }
                        config = model.call("/agents/omp/config", "POST", input) as JSONObject
                        key = ""
                        model.report("已保存到电脑的 OMP")
                        model.selectDevice(model.state.value.device!!)
                    }
                }
            ) {
                Text("保存到电脑")
            }
            Spacer(Modifier.height(30.dp))
        }
    }
}

@Composable
fun RemoteFiles(model: AppModel, sid: String, open: (String) -> Unit) {
    var folder by remember { mutableStateOf("") }
    var entered by remember { mutableStateOf("") }
    var entries by remember { mutableStateOf(emptyList<JSONObject>()) }
    var error by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(folder) {
        try {
            val result =
                model.call("/files", query = mapOf("sessionId" to sid, "path" to folder))
                    as JSONObject
            entries = result.items("entries")
            entered = folder
            error = null
        } catch (e: Exception) {
            error = e.message
        }
    }
    Field(entered, "文件或目录路径") { entered = it }
    Row {
        TextButton(onClick = { folder = folder.substringBeforeLast('/', "") }) { Text("上一级") }
        TextButton(onClick = { folder = entered }) { Text("浏览目录") }
        Button(onClick = { open(entered) }, enabled = entered.isNotBlank()) { Text("打开文件") }
    }
    error?.let { Text(it) }
    LazyColumn {
        items(entries, key = { it.str("path") }) { e ->
            TextButton(
                onClick = {
                    if (e.str("kind") == "folder") folder = e.str("path") else open(e.str("path"))
                }
            ) {
                Icon(
                    if (e.str("kind") == "folder") Icons.Default.Folder
                    else Icons.Default.Description,
                    null,
                )
                Text(e.str("name"))
            }
        }
    }
}
