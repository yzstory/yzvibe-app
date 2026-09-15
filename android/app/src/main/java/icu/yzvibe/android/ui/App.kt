@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)

package icu.yzvibe.android.ui

import android.Manifest
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.widget.TextView
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.core.*
import androidx.compose.foundation.*
import androidx.compose.foundation.gestures.detectDragGesturesAfterLongPress
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.*
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.*
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.*
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.FileProvider
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.journeyapps.barcodescanner.ScanContract
import com.journeyapps.barcodescanner.ScanOptions
import icu.yzvibe.android.R
import icu.yzvibe.android.core.*
import icu.yzvibe.android.platform.*
import io.noties.markwon.Markwon
import io.noties.markwon.ext.strikethrough.StrikethroughPlugin
import io.noties.markwon.ext.tables.TablePlugin
import java.io.File
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject

val Orange = Color(0xFFFF9D50)

@Composable
fun App(model: AppModel) {
    val state by model.state.collectAsStateWithLifecycle()
    var tab by remember { mutableIntStateOf(1) }
    var pair by remember { mutableStateOf(false) }
    var create by remember { mutableStateOf(false) }
    var welcome by rememberSaveable { mutableStateOf(true) }
    LaunchedEffect(Unit) {
        kotlinx.coroutines.delay(1600)
        welcome = false
    }
    MaterialTheme(
        colorScheme =
            darkColorScheme(
                primary = Orange,
                background = Color(0xFF0B0B0D),
                surface = Color(0xFF1C1C20),
            )
    ) {
        Scaffold(
            bottomBar = {
                if (state.sessionId == null)
                    NavigationBar {
                        listOf(
                                "设备" to Icons.Default.Computer,
                                "会话" to Icons.AutoMirrored.Filled.Chat,
                                "审批" to Icons.Default.VerifiedUser,
                                "我" to Icons.Default.Person,
                            )
                            .forEachIndexed { i, p ->
                                NavigationBarItem(
                                    selected = tab == i,
                                    onClick = { tab = i },
                                    icon = { Icon(p.second, p.first) },
                                    label = { Text(p.first) },
                                )
                            }
                    }
            }
        ) { padding ->
            Column(Modifier.fillMaxSize().padding(padding)) {
                if (state.sessionId != null) Chat(model, state)
                else {
                    Row(
                        Modifier.fillMaxWidth().padding(16.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text(
                            state.device?.name ?: "柚子Vibe",
                            Modifier.weight(1f),
                            fontWeight = FontWeight.Bold,
                        )
                        IconButton(onClick = { model.connect() }) {
                            Icon(Icons.Default.Refresh, "重连")
                        }
                        IconButton(
                            onClick = {
                                if (tab == 0 || state.device == null) pair = true else create = true
                            }
                        ) {
                            Icon(Icons.Default.Add, "添加")
                        }
                    }
                    Text(
                        state.connection,
                        Modifier.padding(horizontal = 20.dp),
                        color = if (state.connection == "在线") Color(0xFF65CD99) else Orange,
                        style = MaterialTheme.typography.labelMedium,
                    )
                    if (state.loading) LinearProgressIndicator(Modifier.fillMaxWidth())
                    when (tab) {
                        0 -> Devices(model, state) { pair = true }
                        1 -> Sessions(model, state) { create = true }
                        2 -> Approvals(model, state.snapshot.approvals)
                        else -> Settings(model)
                    }
                }
            }
        }
        if (welcome)
            androidx.compose.ui.window.Dialog(
                onDismissRequest = { welcome = false },
                properties =
                    androidx.compose.ui.window.DialogProperties(usePlatformDefaultWidth = false),
            ) {
                var arrived by remember { mutableStateOf(false) }
                LaunchedEffect(Unit) { arrived = true }
                val scale by
                    animateFloatAsState(
                        if (arrived) 1f else .75f,
                        spring(dampingRatio = .65f),
                        label = "柚子开场",
                    )
                Surface(
                    Modifier.fillMaxSize().clickable { welcome = false },
                    color = MaterialTheme.colorScheme.background,
                ) {
                    Column(
                        Modifier.fillMaxSize(),
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.Center,
                    ) {
                        Image(
                            painterResource(R.drawable.brand_logo),
                            "柚子Vibe",
                            Modifier.size((100 * scale).dp),
                        )
                        Spacer(Modifier.height(18.dp))
                        Text("灵感在手，随时开工", color = Orange)
                    }
                }
            }
        if (pair) PairSheet(model) { pair = false }
        if (create) NewSession(model, state) { create = false }
        state.error?.let {
            AlertDialog(
                onDismissRequest = model::dismissError,
                title = { Text("提示") },
                text = { Text(it) },
                confirmButton = { TextButton(onClick = model::dismissError) { Text("知道了") } },
            )
        }
    }
}

@Composable
fun Devices(model: AppModel, state: AppModel.State, add: () -> Unit) {
    var edit by remember { mutableStateOf<Device?>(null) }
    var discovery by remember { mutableStateOf(false) }
    var found by remember { mutableStateOf(mapOf<String, String>()) }
    val discoveryContext = LocalContext.current
    val discoveryScope = rememberCoroutineScope()
    DisposableEffect(discovery) {
        val finder =
            LanDiscovery(discoveryContext) { name, address ->
                discoveryScope.launch { found = found + (address to name) }
            }
        if (discovery) finder.start()
        onDispose { finder.close() }
    }
    LazyColumn(
        Modifier.fillMaxSize().padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        items(state.devices, key = { it.id }) { d ->
            Card(onClick = { model.selectDevice(d) }) {
                Row(
                    Modifier.fillMaxWidth().padding(16.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Column(Modifier.weight(1f)) {
                        Text(d.name, fontWeight = FontWeight.Bold)
                        Text(d.base, style = MaterialTheme.typography.bodySmall)
                    }
                    IconButton(onClick = { edit = d }) { Icon(Icons.Default.Edit, "编辑连接配置") }
                }
            }
        }
        item {
            Button(onClick = add) { Text("扫码配对 / 手动添加") }
            TextButton(onClick = { discovery = !discovery }) {
                Text(if (discovery) "停止局域网查找" else "在局域网里找")
            }
        }
        items(found.toList()) { (address, name) ->
            TextButton(
                onClick = {
                    val current = state.device
                    if (current != null) model.editDevice(current, current.name, address) else add()
                }
            ) {
                Text("$name · $address")
            }
        }
    }
    edit?.let { d ->
        var name by remember(d.id) { mutableStateOf(d.name) }
        var base by remember(d.id) { mutableStateOf(d.base) }
        AlertDialog(
            onDismissRequest = { edit = null },
            title = { Text("编辑设备") },
            text = {
                Column {
                    Field(name, "显示名称") { name = it }
                    Field(base, "连接地址") { base = it }
                    Text("更换地址时会先核对电脑身份。", style = MaterialTheme.typography.bodySmall)
                }
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        model.editDevice(d, name, base)
                        edit = null
                    }
                ) {
                    Text("保存")
                }
            },
            dismissButton = { TextButton(onClick = { edit = null }) { Text("取消") } },
        )
    }
}

@Composable
fun PairSheet(model: AppModel, close: () -> Unit) {
    var raw by remember { mutableStateOf("") }
    val scan =
        rememberLauncherForActivityResult(ScanContract()) {
            it.contents?.let { value -> raw = value }
        }
    ModalBottomSheet(onDismissRequest = close) {
        Column(
            Modifier.padding(24.dp).imePadding(),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text("连接你的电脑", style = MaterialTheme.typography.headlineSmall)
            Text("在电脑运行 npx yzvibe@latest qr，然后扫描二维码或粘贴配对链接。")
            Field(raw, "配对链接 / JSON") { raw = it }
            OutlinedButton(
                onClick = {
                    scan.launch(
                        ScanOptions()
                            .setDesiredBarcodeFormats(ScanOptions.QR_CODE)
                            .setPrompt("扫描柚子Vibe配对码")
                            .setBeepEnabled(false)
                    )
                }
            ) {
                Text("扫描二维码")
            }
            Button(
                onClick = {
                    model.pair(raw)
                    close()
                },
                enabled = raw.isNotBlank(),
            ) {
                Text("配对")
            }
            Spacer(Modifier.height(20.dp))
        }
    }
}

@Composable
fun Sessions(model: AppModel, state: AppModel.State, create: () -> Unit) {
    var search by remember { mutableStateOf("") }
    var active by remember { mutableStateOf(false) }
    var collapsed by remember { mutableStateOf(setOf<String>()) }
    var rename by remember { mutableStateOf<JSONObject?>(null) }
    val groups =
        state.snapshot.sessions
            .filter {
                (!active || recent(it)) && (it.str("title") + it.str("cwd")).contains(search, true)
            }
            .sortedByDescending { it.str("updatedAt") }
            .groupBy { it.str("cwd") }
    Column(Modifier.padding(horizontal = 16.dp)) {
        Field(search, "搜索会话或路径") { search = it }
        Row(verticalAlignment = Alignment.CenterVertically) {
            FilterChip(active, { active = !active }, label = { Text("近七天") })
            Spacer(Modifier.weight(1f))
            IconButton(
                onClick = {
                    collapsed = if (collapsed.containsAll(groups.keys)) emptySet() else groups.keys
                }
            ) {
                Icon(
                    if (collapsed.containsAll(groups.keys)) Icons.Default.UnfoldMore
                    else Icons.Default.UnfoldLess,
                    "展开或收拢全部",
                )
            }
            IconButton(onClick = create) { Icon(Icons.Default.Edit, "新建会话") }
        }
        LazyColumn(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            groups.forEach { (cwd, sessions) ->
                item(key = "group:$cwd") {
                    TextButton(
                        onClick = {
                            collapsed = if (cwd in collapsed) collapsed - cwd else collapsed + cwd
                        }
                    ) {
                        Text(
                            "${if (cwd in collapsed) "›" else "⌄"} ${cwd.substringAfterLast('/')}  ·  ${sessions.size}"
                        )
                    }
                }
                if (cwd !in collapsed)
                    items(sessions, key = { it.str("id") }) { s ->
                        Card(onClick = { model.openSession(s.str("id")) }) {
                            Column(Modifier.fillMaxWidth().padding(16.dp)) {
                                Row(verticalAlignment = Alignment.CenterVertically) {
                                    Agent(s.str("agent"))
                                    if (s.str("status") in listOf("running", "waiting_approval")) {
                                        Spacer(Modifier.width(8.dp))
                                        CircularProgressIndicator(
                                            Modifier.size(12.dp),
                                            strokeWidth = 2.dp,
                                        )
                                    }
                                    Spacer(Modifier.weight(1f))
                                    var menu by remember { mutableStateOf(false) }
                                    Box {
                                        IconButton(onClick = { menu = true }) {
                                            Icon(Icons.Default.MoreHoriz, "会话操作")
                                        }
                                        DropdownMenu(menu, { menu = false }) {
                                            DropdownMenuItem(
                                                text = { Text("重命名") },
                                                onClick = {
                                                    rename = s
                                                    menu = false
                                                },
                                            )
                                            DropdownMenuItem(
                                                text = { Text("删除 / 隐藏") },
                                                onClick = {
                                                    model.action(
                                                        "/sessions/${s.str("id")}",
                                                        "DELETE",
                                                    )
                                                    menu = false
                                                },
                                            )
                                        }
                                    }
                                }
                                Text(
                                    s.str("title", "新会话"),
                                    fontWeight = FontWeight.Bold,
                                    maxLines = 2,
                                )
                                Text(
                                    cwd,
                                    style = MaterialTheme.typography.bodySmall,
                                    color = Color.Gray,
                                    maxLines = 1,
                                )
                            }
                        }
                    }
            }
            if (groups.isEmpty()) item { Text("暂无会话，点击右上角新建。", Modifier.padding(24.dp)) }
        }
    }
    rename?.let { s ->
        var title by remember(s) { mutableStateOf(s.str("title")) }
        AlertDialog(
            onDismissRequest = { rename = null },
            title = { Text("重命名会话") },
            text = { Field(title, "显示名称") { title = it } },
            confirmButton = {
                TextButton(
                    onClick = {
                        model.launch {
                            model.call("/sessions/${s.str("id")}", "PATCH", obj("title" to title))
                            model.refresh()
                            rename = null
                        }
                    }
                ) {
                    Text("保存")
                }
            },
            dismissButton = { TextButton(onClick = { rename = null }) { Text("取消") } },
        )
    }
}

@Composable
fun Agent(name: String) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Image(
            painterResource(
                when (name) {
                    "claude" -> R.drawable.agent_claude
                    "omp" -> R.drawable.agent_omp
                    else -> R.drawable.agent_codex
                }
            ),
            null,
            Modifier.size(17.dp),
        )
        Text(
            when (name) {
                "claude" -> "Claude Code"
                "omp" -> "OMP"
                else -> "Codex"
            },
            style = MaterialTheme.typography.labelMedium,
        )
    }
}

@Composable
fun Field(value: String, label: String, change: (String) -> Unit) =
    OutlinedTextField(
        value,
        change,
        label = { Text(label) },
        modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp),
        shape = RoundedCornerShape(16.dp),
    )

@Composable
fun NewSession(model: AppModel, state: AppModel.State, close: () -> Unit) {
    var agent by remember { mutableStateOf("codex") }
    var mode by remember { mutableStateOf("normal") }
    var chosenModel by remember { mutableStateOf("") }
    var chosenEffort by remember { mutableStateOf("") }
    var cwd by remember { mutableStateOf(state.snapshot.sessions.firstOrNull()?.str("cwd") ?: "") }
    var first by remember { mutableStateOf("") }
    var continuing by remember { mutableStateOf(false) }
    var directory by remember { mutableStateOf(false) }
    ModalBottomSheet(onDismissRequest = close) {
        Column(Modifier.padding(24.dp).verticalScroll(rememberScrollState()).imePadding()) {
            Text("新建会话", style = MaterialTheme.typography.headlineSmall)
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                listOf("claude", "codex", "omp").forEach { a ->
                    FilterChip(
                        agent == a,
                        {
                            agent = a
                            chosenModel = ""
                            chosenEffort = ""
                        },
                        label = { Agent(a) },
                    )
                }
            }
            Field(cwd, "工作目录，留空使用主目录") { cwd = it }
            TextButton(onClick = { directory = true }) { Text("浏览电脑目录") }
            val caps = state.capabilities.optJSONObject(agent) ?: obj()
            Choice(
                "审批模式",
                mode,
                listOf(
                    "plan" to "Plan · 只读规划",
                    "normal" to "Normal · 按需审批",
                    "trust" to "Trust · 无需审批",
                ),
            ) {
                mode = it
            }
            Choice(
                "模型",
                chosenModel,
                listOf("" to "默认模型") +
                    caps.items("models").map { it.str("id") to it.str("label", it.str("id")) },
            ) {
                chosenModel = it
                chosenEffort = ""
            }
            val levels =
                caps.items("models").find { it.str("id") == chosenModel }?.optJSONArray("efforts")
                    ?: caps.optJSONArray("efforts")
                    ?: JSONArray()
            Choice(
                "思考强度",
                chosenEffort,
                listOf("" to "默认") +
                    (0 until levels.length()).map { levels.getString(it) to levels.getString(it) } +
                    if (agent != "omp") listOf("ultra" to "Ultra") else emptyList(),
            ) {
                chosenEffort = it
            }
            Field(first, "首句消息（可选）") { first = it }
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("继续该目录上次会话", Modifier.weight(1f))
                Switch(continuing, { continuing = it })
            }
            Button(
                onClick = {
                    model.launch {
                        val s =
                            model.call(
                                "/sessions",
                                "POST",
                                obj(
                                    "agent" to agent,
                                    "cwd" to cwd,
                                    "firstMessage" to first,
                                    "continueLast" to continuing,
                                    "mode" to mode,
                                    "model" to chosenModel.ifBlank { null },
                                    "effort" to chosenEffort.ifBlank { null },
                                ),
                            ) as JSONObject
                        model.refresh()
                        model.openSession(s.str("id"))
                        close()
                    }
                }
            ) {
                Text("开始会话")
            }
            Spacer(Modifier.height(30.dp))
        }
    }
    if (directory)
        DirectoryPicker(
            model,
            cwd,
            {
                cwd = it
                directory = false
            },
            { directory = false },
        )
}

@Composable
fun Chat(model: AppModel, state: AppModel.State) {
    val sid = state.sessionId ?: return
    val session = state.snapshot.sessions.find { it.str("id") == sid } ?: obj("id" to sid)
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val list = rememberLazyListState()
    val haptic = LocalHapticFeedback.current
    var menu by remember { mutableStateOf(false) }
    var panel by remember { mutableStateOf("") }
    var filePath by remember { mutableStateOf<String?>(null) }
    var options by remember { mutableStateOf(false) }
    val reader = remember(sid) { Reader(context, model::report) }
    val voice = remember(sid) { OnDeviceSpeech(context) }
    var recording by remember { mutableStateOf(false) }
    var cancelVoice by remember { mutableStateOf(false) }
    var volume by remember { mutableFloatStateOf(0f) }
    var before by remember { mutableStateOf("") }
    val owner = androidx.lifecycle.compose.LocalLifecycleOwner.current
    DisposableEffect(sid, owner) {
        val observer =
            androidx.lifecycle.LifecycleEventObserver { _, event ->
                if (event == androidx.lifecycle.Lifecycle.Event.ON_STOP) {
                    voice.cancel()
                    reader.stop()
                    if (recording) model.draft(before)
                    recording = false
                }
            }
        owner.lifecycle.addObserver(observer)
        onDispose {
            owner.lifecycle.removeObserver(observer)
            voice.close()
            reader.close()
        }
    }
    val permissions =
        rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) {
            if (it) model.report("麦克风已授权，再按住语音即可录入") else model.report("需要麦克风权限才能按住说话")
        }
    val file =
        rememberLauncherForActivityResult(ActivityResultContracts.OpenMultipleDocuments()) {
            it.forEach(model::attach)
        }
    val photo =
        rememberLauncherForActivityResult(ActivityResultContracts.PickMultipleVisualMedia(6)) {
            it.forEach(model::attach)
        }
    val cameraUri = remember {
        FileProvider.getUriForFile(
            context,
            context.packageName + ".files",
            File(context.cacheDir, "camera/capture.jpg").apply { parentFile?.mkdirs() },
        )
    }
    val camera =
        rememberLauncherForActivityResult(ActivityResultContracts.TakePicture()) {
            if (it) model.attach(cameraUri)
        }
    val cameraPermission =
        rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) {
            if (it) camera.launch(cameraUri)
        }
    BackHandler { model.openSession(null) }
    Column(Modifier.fillMaxSize()) {
        Row(
            Modifier.fillMaxWidth().padding(horizontal = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            IconButton(onClick = { model.openSession(null) }) {
                Icon(Icons.AutoMirrored.Filled.ArrowBack, "返回")
            }
            Column(Modifier.weight(1f)) {
                Text(session.str("title", "会话"), maxLines = 1, fontWeight = FontWeight.Bold)
                Agent(session.str("agent"))
                Text(
                    "${state.connection} · ${statusLabel(session.str("status"))}",
                    style = MaterialTheme.typography.labelSmall,
                    color = Color.Gray,
                )
            }
            if (session.str("status") == "running")
                IconButton(onClick = { model.action("/sessions/$sid/stop") }) {
                    Icon(Icons.Default.StopCircle, "停止", tint = Orange)
                }
            IconButton(onClick = { options = true }) { Icon(Icons.Default.MoreHoriz, "更多") }
            DropdownMenu(options, { options = false }) {
                listOf("文件", "改动", "交付记录", "上下文", "审批").forEach { label ->
                    DropdownMenuItem(
                        text = { Text(label) },
                        onClick = {
                            panel = label
                            options = false
                        },
                    )
                }
            }
        }
        if (state.loading) LinearProgressIndicator(Modifier.fillMaxWidth())
        val messages = state.snapshot.messages[sid].orEmpty()
        val follow by remember { derivedStateOf { !list.canScrollForward } }
        var followLatest by remember(sid) { mutableStateOf(true) }
        LaunchedEffect(list, sid) {
            snapshotFlow { list.isScrollInProgress }
                .collect { scrolling -> if (!scrolling) followLatest = !list.canScrollForward }
        }
        LaunchedEffect(messages.lastOrNull()?.toString(), session.items("queue").size) {
            if (followLatest && !list.isScrollInProgress && messages.isNotEmpty())
                list.scrollToItem(messages.lastIndex)
        }
        Box(Modifier.weight(1f)) {
            LazyColumn(
                state = list,
                modifier = Modifier.fillMaxSize(),
                contentPadding = PaddingValues(16.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                items(messages, key = { it.str("id") }) { m ->
                    val user = m.str("role") == "user"
                    Row(
                        Modifier.fillMaxWidth(),
                        horizontalArrangement = if (user) Arrangement.End else Arrangement.Start,
                    ) {
                        Card(
                            Modifier.fillMaxWidth(if (user) .9f else 1f),
                            colors =
                                CardDefaults.cardColors(
                                    containerColor =
                                        if (user) Color(0xFF623D22)
                                        else MaterialTheme.colorScheme.surface
                                ),
                        ) {
                            Column(Modifier.padding(14.dp)) {
                                Markdown(m.str("text")) { link ->
                                    if (link.startsWith("https://") || link.startsWith("http://"))
                                        context.startActivity(
                                            Intent(Intent.ACTION_VIEW, Uri.parse(link))
                                        )
                                    else
                                        filePath =
                                            Uri.decode(
                                                link.removePrefix("file://").substringBefore('#')
                                            )
                                }
                                localImageReferences(m.str("text")).forEach { path ->
                                    InlineImage(model, sid, path) { filePath = path }
                                }
                                m.optJSONArray("attachments")?.let { a ->
                                    (0 until a.length()).forEach { i ->
                                        val attachment = a.optJSONObject(i)
                                        val id = attachment?.str("id") ?: a.optString(i)
                                        TextButton(onClick = { filePath = "upload:$id" }) {
                                            Icon(Icons.Default.AttachFile, null)
                                            Text(attachment?.str("filename", "附件") ?: "查看附件")
                                        }
                                    }
                                }
                                m.items("toolCalls").forEach { t ->
                                    var expanded by remember { mutableStateOf(false) }
                                    TextButton(onClick = { expanded = !expanded }) {
                                        Icon(Icons.Default.Terminal, null)
                                        Text("${t.str("name")} · ${t.str("state")}")
                                    }
                                    if (expanded)
                                        Markdown(
                                            t.str(
                                                "detail",
                                                t.optJSONObject("input")?.toString(2).orEmpty(),
                                            ) + "\n\n```\n${t.str("output")}\n```"
                                        ) {
                                            filePath = it
                                        }
                                }
                                Row {
                                    if (!user)
                                        IconButton(onClick = { reader.read(m.str("text")) }) {
                                            Icon(
                                                Icons.AutoMirrored.Filled.VolumeUp,
                                                "朗读正文",
                                                Modifier.size(20.dp),
                                            )
                                        }
                                    IconButton(
                                        onClick = {
                                            (context.getSystemService(Context.CLIPBOARD_SERVICE)
                                                    as ClipboardManager)
                                                .setPrimaryClip(
                                                    ClipData.newPlainText("消息", m.str("text"))
                                                )
                                            haptic.performHapticFeedback(
                                                HapticFeedbackType.LongPress
                                            )
                                        }
                                    ) {
                                        Icon(Icons.Default.ContentCopy, "复制", Modifier.size(20.dp))
                                    }
                                }
                            }
                        }
                    }
                }
                items(session.items("queue"), key = { "queue:${it.str("id")}" }) { q ->
                    Card {
                        Column(Modifier.padding(12.dp)) {
                            Text(q.str("text"))
                            Row {
                                Text("排队中", Modifier.weight(1f))
                                TextButton(
                                    onClick = {
                                        model.action("/sessions/$sid/queue/${q.str("id")}/send-now")
                                    }
                                ) {
                                    Text("立即引导")
                                }
                                IconButton(
                                    onClick = {
                                        model.action(
                                            "/sessions/$sid/queue/${q.str("id")}",
                                            "DELETE",
                                        )
                                    }
                                ) {
                                    Icon(Icons.Default.Close, "取消排队")
                                }
                            }
                        }
                    }
                }
                if (session.optBoolean("queuePaused"))
                    item {
                        TextButton(onClick = { model.action("/sessions/$sid/queue/resume") }) {
                            Text("继续队列")
                        }
                    }
                items(state.outbox.filter { it.str("sessionId") == sid }) { pending ->
                    Card {
                        Column(Modifier.padding(12.dp)) {
                            Text(pending.str("text"))
                            Text(
                                "${pending.str("state")} · ${pending.str("error")}",
                                color = Orange,
                            )
                            TextButton(onClick = model::retryDelivery) { Text("核对回执并重试") }
                        }
                    }
                }
            }
            if (!follow)
                SmallFloatingActionButton(
                    onClick = {
                        scope.launch {
                            followLatest = true
                            list.animateScrollToItem(
                                (list.layoutInfo.totalItemsCount - 1).coerceAtLeast(0)
                            )
                        }
                    },
                    modifier = Modifier.align(Alignment.BottomEnd).padding(12.dp),
                ) {
                    Icon(Icons.Default.ArrowDownward, "返回最新")
                }
        }
        if (recording)
            Surface(
                color = if (cancelVoice) Color(0xFF873434) else Color(0xFF6A4328),
                shape = RoundedCornerShape(24.dp),
                modifier = Modifier.fillMaxWidth().padding(12.dp),
            ) {
                Column(
                    Modifier.padding(20.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    Text(if (cancelVoice) "松手取消" else "松手转文字 · 上滑取消")
                    LinearProgressIndicator(
                        progress = { volume },
                        modifier = Modifier.padding(top = 10.dp),
                    )
                }
            }
        Card(
            Modifier.fillMaxWidth().padding(10.dp).imePadding(),
            shape = RoundedCornerShape(26.dp),
        ) {
            Column(Modifier.padding(12.dp)) {
                state.draft.items("attachments").forEach { a ->
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(a.str("name"), Modifier.weight(1f), maxLines = 1)
                        IconButton(onClick = { model.removeAttachment(a.str("id")) }) {
                            Icon(Icons.Default.Close, "移除附件")
                        }
                    }
                }
                TextField(
                    state.draft.str("text"),
                    model::draft,
                    Modifier.fillMaxWidth(),
                    placeholder = {
                        Text(
                            if (session.str("status") == "running") "会排在当前任务后面…"
                            else "发消息给 ${session.str("agent")}"
                        )
                    },
                    maxLines = 5,
                    colors =
                        TextFieldDefaults.colors(
                            focusedContainerColor = Color.Transparent,
                            unfocusedContainerColor = Color.Transparent,
                        ),
                )
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Box {
                        IconButton(onClick = { menu = true }) {
                            Icon(Icons.Default.AutoAwesome, "照片、文件、命令与技能")
                        }
                        DropdownMenu(menu, { menu = false }) {
                            listOf("照片", "拍摄", "文件", "命令", "技能").forEach { label ->
                                DropdownMenuItem(
                                    text = { Text(label) },
                                    onClick = {
                                        menu = false
                                        when (label) {
                                            "照片" ->
                                                photo.launch(
                                                    androidx.activity.result.PickVisualMediaRequest(
                                                        ActivityResultContracts.PickVisualMedia
                                                            .ImageOnly
                                                    )
                                                )
                                            "拍摄" ->
                                                cameraPermission.launch(Manifest.permission.CAMERA)
                                            "文件" -> file.launch(arrayOf("*/*"))
                                            else -> panel = label
                                        }
                                    },
                                )
                            }
                        }
                    }
                    Spacer(Modifier.weight(1f))
                    IconButton(
                        onClick = { model.send() },
                        enabled =
                            state.draft.str("text").isNotBlank() ||
                                state.draft.items("attachments").isNotEmpty(),
                    ) {
                        Icon(Icons.AutoMirrored.Filled.Send, "发送", tint = Orange)
                    }
                }
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(4.dp),
                ) {
                    TextButton(onClick = { panel = "模式" }, modifier = Modifier.weight(1f)) {
                        Text(session.str("mode", "默认"), maxLines = 1)
                    }
                    TextButton(onClick = { panel = "模型" }, modifier = Modifier.weight(1.6f)) {
                        Text(session.str("model", "默认模型").substringAfterLast('/'), maxLines = 1)
                    }
                    TextButton(onClick = { panel = "思考强度" }, modifier = Modifier.weight(.8f)) {
                        Text(session.str("effort", "默认"), maxLines = 1)
                    }
                    Surface(
                        shape = RoundedCornerShape(22.dp),
                        color = Color(0xFF29292D),
                        modifier =
                            Modifier.width(76.dp).height(44.dp).pointerInput(sid) {
                                detectDragGesturesAfterLongPress(
                                    onDragStart = {
                                        if (
                                            androidx.core.content.ContextCompat.checkSelfPermission(
                                                context,
                                                Manifest.permission.RECORD_AUDIO,
                                            ) !=
                                                android.content.pm.PackageManager.PERMISSION_GRANTED
                                        )
                                            permissions.launch(Manifest.permission.RECORD_AUDIO)
                                        else {
                                            before = model.state.value.draft.str("text")
                                            recording = true
                                            cancelVoice = false
                                            haptic.performHapticFeedback(
                                                HapticFeedbackType.LongPress
                                            )
                                            voice.start(
                                                { result ->
                                                    if (!cancelVoice)
                                                        model.draft(
                                                            before +
                                                                if (before.isBlank()) result
                                                                else "\n$result"
                                                        )
                                                },
                                                { volume = it },
                                                {
                                                    recording = false
                                                    model.report(it)
                                                },
                                            )
                                        }
                                    },
                                    onDrag = { change, _ ->
                                        cancelVoice = change.position.y < -70
                                        change.consume()
                                    },
                                    onDragEnd = {
                                        if (recording) {
                                            if (cancelVoice) {
                                                voice.cancel()
                                                model.draft(before)
                                            } else voice.finish()
                                        }
                                        recording = false
                                    },
                                    onDragCancel = {
                                        voice.cancel()
                                        if (recording) model.draft(before)
                                        recording = false
                                    },
                                )
                            },
                    ) {
                        Row(
                            Modifier.fillMaxSize(),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.Center,
                        ) {
                            Icon(Icons.Default.Mic, "按住说话", Modifier.size(20.dp), tint = Orange)
                            Text("语音", style = MaterialTheme.typography.labelMedium)
                        }
                    }
                }
            }
        }
    }
    if (panel.isNotEmpty())
        SessionPanel(
            model,
            state,
            session,
            panel,
            { filePath = it },
            { panel = it },
            { panel = "" },
        )
    filePath?.let { path -> FilePreview(model, sid, path, { filePath = it }, { filePath = null }) }
}

@Composable
fun Markdown(text: String, link: (String) -> Unit = {}) {
    val currentLink by rememberUpdatedState(link)
    val context = LocalContext.current
    val markwon =
        remember(context) {
            Markwon.builder(context)
                .usePlugin(TablePlugin.create(context))
                .usePlugin(StrikethroughPlugin.create())
                .usePlugin(
                    object : io.noties.markwon.AbstractMarkwonPlugin() {
                        override fun configureConfiguration(
                            builder: io.noties.markwon.MarkwonConfiguration.Builder
                        ) {
                            builder.linkResolver { _, url -> currentLink(url) }
                        }
                    }
                )
                .build()
        }
    AndroidView(
        factory = {
            TextView(it).apply {
                setTextColor(android.graphics.Color.WHITE)
                textSize = 16f
                setTextIsSelectable(true)
                setPadding(0, 0, 0, 0)
                var touchTime = 0L
                var startX = 0f
                var startY = 0f
                setOnTouchListener { _, event ->
                    if (event.action == android.view.MotionEvent.ACTION_DOWN) {
                        touchTime = event.eventTime
                        startX = event.x
                        startY = event.y
                    }
                    if (
                        event.action == android.view.MotionEvent.ACTION_UP &&
                            event.eventTime - touchTime < 300 &&
                            kotlin.math.abs(event.x - startX) + kotlin.math.abs(event.y - startY) <
                                20
                    ) {
                        val spanned = this.text as? android.text.Spanned
                        val line =
                            layout?.getLineForVertical(
                                (event.y - totalPaddingTop + scrollY).toInt()
                            )
                        val offset =
                            line?.let {
                                layout.getOffsetForHorizontal(
                                    it,
                                    event.x - totalPaddingLeft + scrollX,
                                )
                            }
                        val span =
                            offset?.let {
                                spanned
                                    ?.getSpans(it, it, android.text.style.ClickableSpan::class.java)
                                    ?.firstOrNull()
                            }
                        if (span != null) {
                            performClick()
                            span.onClick(this)
                            true
                        } else false
                    } else false
                }
            }
        },
        update = {
            if (it.tag != text) {
                markwon.setMarkdown(it, linkLocalFiles(text))
                it.tag = text
            }
        },
        modifier = Modifier.fillMaxWidth(),
    )
}

fun statusLabel(value: String) =
    when (value) {
        "idle" -> "空闲"
        "running" -> "运行中"
        "waiting_approval" -> "等待审批"
        "error" -> "运行异常"
        "closed" -> "已关闭"
        else -> value
    }

@Composable
fun Choice(
    label: String,
    value: String,
    values: List<Pair<String, String>>,
    choose: (String) -> Unit,
) {
    var expanded by remember { mutableStateOf(false) }
    Box {
        TextButton(onClick = { expanded = true }) {
            Text("$label：${values.find { it.first == value }?.second ?: value}")
            Icon(Icons.Default.ExpandMore, null)
        }
        DropdownMenu(expanded, { expanded = false }) {
            values.forEach { (id, title) ->
                DropdownMenuItem(
                    text = { Text(title) },
                    onClick = {
                        choose(id)
                        expanded = false
                    },
                )
            }
        }
    }
}
