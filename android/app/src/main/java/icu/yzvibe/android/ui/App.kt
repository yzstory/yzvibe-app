@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)

package icu.yzvibe.android.ui

import android.Manifest
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.widget.TextView
import androidx.activity.BackEventCompat
import androidx.activity.compose.PredictiveBackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.*
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.*
import androidx.compose.foundation.gestures.detectDragGesturesAfterLongPress
import androidx.compose.foundation.interaction.DragInteraction
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.*
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.material3.adaptive.ExperimentalMaterial3AdaptiveApi
import androidx.compose.material3.adaptive.currentWindowAdaptiveInfo
import androidx.compose.material3.adaptive.navigationsuite.ExperimentalMaterial3AdaptiveNavigationSuiteApi
import androidx.compose.material3.adaptive.navigationsuite.NavigationSuiteDefaults
import androidx.compose.material3.adaptive.navigationsuite.NavigationSuiteScaffold
import androidx.compose.material3.adaptive.navigationsuite.NavigationSuiteScaffoldDefaults
import androidx.compose.material3.adaptive.navigationsuite.NavigationSuiteType
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.*
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.*
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.TextOverflow
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
import kotlin.coroutines.cancellation.CancellationException
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject

/**
 * `NavigationSuiteScaffold` 不会把系统栏 inset 传进内容区（官方 adaptive 指南明确要求各屏自己处理），
 * 所以这里统一下发：导航区占用的那条边已经由导航区自己吃掉，剩下几边留给页面。
 */
val LocalScreenInsets = compositionLocalOf { WindowInsets(0, 0, 0, 0) }

/** 底部 inset，给列表的 contentPadding 用，避免把 Modifier.padding 加到滚动容器上裁掉内容。 */
@Composable
fun screenBottomInset(): androidx.compose.ui.unit.Dp =
    with(LocalDensity.current) { LocalScreenInsets.current.getBottom(this).toDp() }

private val TabItems =
    listOf(
        "设备" to Icons.Default.Computer,
        "会话" to Icons.AutoMirrored.Filled.Chat,
        "审批" to Icons.Default.VerifiedUser,
        "我" to Icons.Default.Person,
    )

@OptIn(
    ExperimentalMaterial3AdaptiveApi::class,
    ExperimentalMaterial3AdaptiveNavigationSuiteApi::class,
    ExperimentalLayoutApi::class,
)
@Composable
fun App(model: AppModel) {
    val state by model.state.collectAsStateWithLifecycle()
    val preferences = rememberPreferences()
    var tab by rememberSaveable { mutableIntStateOf(1) }
    var pair by remember { mutableStateOf(false) }
    var create by remember { mutableStateOf(false) }
    var welcome by rememberSaveable { mutableStateOf(true) }
    LaunchedEffect(Unit) {
        kotlinx.coroutines.delay(1600)
        welcome = false
    }
    CompositionLocalProvider(LocalPreferences provides preferences) {
        YzTheme(preferences.appearance) {
            val chatting = state.sessionId != null
            val keyboard = WindowInsets.isImeVisible
            // 会话内和打字时让出整屏；其余按窗口宽度在底部栏（手机）和侧边栏（平板 / 展开的折叠屏 / 桌面）之间切换。
            val layout =
                if (chatting || keyboard) NavigationSuiteType.None
                else
                    NavigationSuiteScaffoldDefaults.calculateFromAdaptiveInfo(
                        currentWindowAdaptiveInfo()
                    )
            val itemColors =
                NavigationSuiteDefaults.itemColors(
                    navigationBarItemColors =
                        NavigationBarItemDefaults.colors(
                            selectedIconColor = MaterialTheme.colorScheme.primary,
                            selectedTextColor = MaterialTheme.colorScheme.primary,
                            indicatorColor = MaterialTheme.colorScheme.primaryContainer,
                            unselectedIconColor = MaterialTheme.colorScheme.onSurfaceVariant,
                            unselectedTextColor = MaterialTheme.colorScheme.onSurfaceVariant,
                        ),
                    navigationRailItemColors =
                        NavigationRailItemDefaults.colors(
                            selectedIconColor = MaterialTheme.colorScheme.primary,
                            selectedTextColor = MaterialTheme.colorScheme.primary,
                            indicatorColor = MaterialTheme.colorScheme.primaryContainer,
                            unselectedIconColor = MaterialTheme.colorScheme.onSurfaceVariant,
                            unselectedTextColor = MaterialTheme.colorScheme.onSurfaceVariant,
                        ),
                )
            val approvals = state.snapshot.approvals.size
            Box(Modifier.fillMaxSize()) {
                NavigationSuiteScaffold(
                    layoutType = layout,
                    containerColor = MaterialTheme.colorScheme.background,
                    contentColor = MaterialTheme.colorScheme.onBackground,
                    navigationSuiteColors =
                        NavigationSuiteDefaults.colors(
                            navigationBarContainerColor = MaterialTheme.colorScheme.surface,
                            navigationRailContainerColor = MaterialTheme.colorScheme.surface,
                        ),
                    navigationSuiteItems = {
                        TabItems.forEachIndexed { i, (label, icon) ->
                            item(
                                selected = tab == i,
                                onClick = { tab = i },
                                icon = { Icon(icon, null) },
                                label = { Text(label) },
                                badge =
                                    if (i == 2 && approvals > 0) {
                                        { Text(approvals.toString()) }
                                    } else null,
                                colors = itemColors,
                            )
                        }
                    },
                ) {
                    val insets =
                        when (layout) {
                            NavigationSuiteType.NavigationBar ->
                                WindowInsets.safeDrawing.only(
                                    WindowInsetsSides.Horizontal + WindowInsetsSides.Top
                                )
                            NavigationSuiteType.NavigationRail,
                            NavigationSuiteType.NavigationDrawer ->
                                WindowInsets.safeDrawing.only(
                                    WindowInsetsSides.End + WindowInsetsSides.Vertical
                                )
                            else -> WindowInsets.safeDrawing
                        }
                    CompositionLocalProvider(LocalScreenInsets provides insets) {
                        if (chatting) Chat(model, state)
                        else
                            Home(
                                model,
                                state,
                                tab,
                                pair = { pair = true },
                                create = { create = true },
                            )
                    }
                }
                Toast(state.toast, model::dismissToast, Modifier.align(Alignment.TopCenter))
            }
            if (welcome)
                androidx.compose.ui.window.Dialog(
                    onDismissRequest = { welcome = false },
                    properties =
                        androidx.compose.ui.window.DialogProperties(
                            usePlatformDefaultWidth = false,
                            decorFitsSystemWindows = false,
                        ),
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
}

/** 顶部胶囊 Toast，3 秒自动消失，对齐 iOS 的 `ToastView`：一过性提示不抢走当前操作。 */
@Composable
internal fun Toast(text: String?, dismiss: () -> Unit, modifier: Modifier = Modifier) {
    var shown by remember { mutableStateOf("") }
    LaunchedEffect(text) {
        if (text == null) return@LaunchedEffect
        shown = text
        kotlinx.coroutines.delay(3000)
        dismiss()
    }
    AnimatedVisibility(
        visible = text != null,
        modifier = modifier,
        enter = slideInVertically { -it } + fadeIn(),
        exit = slideOutVertically { -it } + fadeOut(),
    ) {
        Surface(
            Modifier.windowInsetsPadding(
                    WindowInsets.safeDrawing.only(
                        WindowInsetsSides.Top + WindowInsetsSides.Horizontal
                    )
                )
                .padding(horizontal = 16.dp, vertical = 8.dp),
            shape = RoundedCornerShape(percent = 50),
            color = MaterialTheme.colorScheme.surfaceContainerHighest,
            contentColor = MaterialTheme.colorScheme.onSurface,
            shadowElevation = 8.dp,
        ) {
            Text(
                shown,
                Modifier.padding(horizontal = 18.dp, vertical = 11.dp),
                style = MaterialTheme.typography.bodyMedium,
            )
        }
    }
}

/** 四个顶层页签共用的页头（设备切换 + 大标题 + 连接状态），对齐 iOS 的导航栏大标题。 */
@Composable
private fun Home(
    model: AppModel,
    state: AppModel.State,
    tab: Int,
    pair: () -> Unit,
    create: () -> Unit,
) {
    var devicesMenu by remember { mutableStateOf(false) }
    Column(
        Modifier.fillMaxSize()
            .windowInsetsPadding(LocalScreenInsets.current.only(WindowInsetsSides.Horizontal))
    ) {
        Column(
            Modifier.windowInsetsPadding(LocalScreenInsets.current.only(WindowInsetsSides.Top))
                .padding(start = 20.dp, end = 16.dp, top = 8.dp, bottom = 8.dp)
        ) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.weight(1f)) {
                    TextButton(
                        onClick = { devicesMenu = true },
                        contentPadding = PaddingValues(0.dp),
                    ) {
                        Text(
                            state.device?.name ?: "选择你的电脑",
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        Icon(
                            Icons.Default.ExpandMore,
                            null,
                            Modifier.size(18.dp),
                            tint = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                    DropdownMenu(devicesMenu, { devicesMenu = false }) {
                        state.devices.forEach { device ->
                            DropdownMenuItem(
                                text = { Text(device.name) },
                                onClick = {
                                    model.selectDevice(device)
                                    devicesMenu = false
                                },
                            )
                        }
                        DropdownMenuItem(
                            text = { Text("添加设备") },
                            onClick = {
                                devicesMenu = false
                                pair()
                            },
                        )
                    }
                }
                IconButton(onClick = { model.connect() }) {
                    Icon(
                        Icons.Default.Refresh,
                        "重连",
                        tint = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Text(
                    TabItems[tab].first,
                    Modifier.weight(1f),
                    style = MaterialTheme.typography.headlineLarge,
                )
                if (tab == 0 || tab == 1)
                    FilledTonalIconButton(
                        onClick = {
                            if (tab == 0 || state.device == null) pair() else create()
                        },
                        colors =
                            IconButtonDefaults.filledTonalIconButtonColors(
                                containerColor = MaterialTheme.colorScheme.primaryContainer,
                                contentColor = Orange,
                            ),
                    ) {
                        Icon(
                            if (tab == 0) Icons.Default.Add else Icons.Default.Edit,
                            if (tab == 0) "添加设备" else "新建会话",
                        )
                    }
            }
            StatusMark(state.connection)
        }
        if (state.loading) LinearProgressIndicator(Modifier.fillMaxWidth())
        when (tab) {
            0 -> Devices(model, state, pair)
            1 -> Sessions(model, state, create)
            2 -> Approvals(model, state.snapshot.approvals)
            else -> Settings(model)
        }
    }
}

@Composable
fun Devices(model: AppModel, state: AppModel.State, add: () -> Unit) {
    val uriHandler = androidx.compose.ui.platform.LocalUriHandler.current
    val appContext = LocalContext.current
    val appVersion = remember {
        val info = appContext.packageManager.getPackageInfo(appContext.packageName, 0)
        "${info.versionName} (${info.longVersionCode})"
    }
    var edit by remember { mutableStateOf<Device?>(null) }
    var diagnostics by remember { mutableStateOf<Device?>(null) }
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
    // 平板 / 展开的折叠屏上排成多列，卡片不会被拉成一条难读的长条。
    LazyVerticalGrid(
        columns = GridCells.Adaptive(320.dp),
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(16.dp, 16.dp, 16.dp, 16.dp + screenBottomInset()),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        item(span = { GridItemSpan(maxLineSpan) }) {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Card(onClick = { uriHandler.openUri("https://vibe.yzcloud.icu/") }) {
                    Row(Modifier.fillMaxWidth().padding(14.dp), verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        Image(painterResource(R.drawable.brand_logo), null, Modifier.size(40.dp))
                        Column(Modifier.weight(1f)) {
                            Text("柚子Vibe · 使用指南", style = MaterialTheme.typography.titleSmall)
                            Text("安装连接器，扫码开始使用", style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                        Icon(Icons.AutoMirrored.Filled.OpenInNew, "打开官网", Modifier.size(20.dp))
                    }
                }
                Text("App $appVersion", style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        items(state.devices, key = { it.id }) { d ->
            Card(
                onClick = { model.selectDevice(d) },
                colors =
                    CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
                border =
                    if (d.id == state.device?.id)
                        BorderStroke(1.dp, MaterialTheme.colorScheme.primary.copy(alpha = .45f))
                    else null,
            ) {
                Row(
                    Modifier.fillMaxWidth().padding(16.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Icon(
                        Icons.Default.Computer,
                        null,
                        Modifier.padding(end = 14.dp).size(28.dp),
                        tint =
                            if (d.id == state.device?.id) Orange
                            else MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(5.dp)) {
                        Text(d.name, style = MaterialTheme.typography.titleMedium)
                        ConnectorVersionLabel(model, d)
                        Text(
                            d.base,
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        if (d.id == state.device?.id)
                            Text(
                                "当前设备",
                                style = MaterialTheme.typography.labelMedium,
                                color = Orange,
                            )
                    }
                    Column {
                        TextButton(onClick = { edit = d }) {
                            Icon(Icons.Default.Settings, null, Modifier.size(18.dp))
                            Text("配置")
                        }
                        TextButton(onClick = { diagnostics = d }) {
                            Icon(Icons.Default.NetworkCheck, null, Modifier.size(18.dp))
                            Text("诊断")
                        }
                    }
                }
            }
        }
        item(span = { GridItemSpan(maxLineSpan) }) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Button(onClick = add) { Text("扫码配对 / 手动添加") }
                TextButton(onClick = { discovery = !discovery }) {
                    Text(if (discovery) "停止局域网查找" else "在局域网里找")
                }
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
    edit?.let { d -> DeviceConfigurationPanel(model, d) { edit = null } }
    diagnostics?.let { d -> DeviceDiagnosticsPanel(model, d) { diagnostics = null } }
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
    val preferences = LocalPreferences.current
    var search by remember { mutableStateOf("") }
    var collapsed by remember { mutableStateOf(setOf<String>()) }
    var rename by remember { mutableStateOf<JSONObject?>(null) }
    val active = preferences.activeOnly
    val matched =
        state.snapshot.sessions
            .filter {
                (!active || recent(it)) &&
                    (preferences.showTerminalSessions || it.str("source") != "terminal") &&
                    (it.str("title") + it.str("cwd")).contains(search, true)
            }
            .sortedByDescending { it.str("updatedAt") }
    // 关掉「按目录分组」时全部放进一个空标题的组，页面结构不变，只是不再出现分组头。
    val groups = if (preferences.groupByFolder) matched.groupBy { it.str("cwd") } else mapOf("" to matched)
    Column(Modifier.padding(horizontal = 20.dp)) {
        OutlinedTextField(
            search,
            { search = it },
            modifier = Modifier.fillMaxWidth(),
            placeholder = { Text("搜索会话或路径") },
            leadingIcon = { Icon(Icons.Default.Search, null) },
            trailingIcon = {
                if (search.isNotEmpty())
                    IconButton(onClick = { search = "" }) { Icon(Icons.Default.Close, "清除搜索") }
            },
            singleLine = true,
            shape = RoundedCornerShape(18.dp),
            colors =
                OutlinedTextFieldDefaults.colors(
                    unfocusedBorderColor = Color.Transparent,
                    focusedBorderColor = Orange,
                    unfocusedContainerColor = MaterialTheme.colorScheme.surfaceContainerHigh,
                    focusedContainerColor = MaterialTheme.colorScheme.surfaceContainerHigh,
                ),
        )
        Row(verticalAlignment = Alignment.CenterVertically) {
            FilterChip(
                active,
                { preferences.activeOnly(!active) },
                label = { Text("近七天") },
                colors =
                    FilterChipDefaults.filterChipColors(
                        selectedContainerColor = MaterialTheme.colorScheme.primaryContainer,
                        selectedLabelColor = Orange,
                    ),
            )
            Spacer(Modifier.weight(1f))
            Text(
                "${groups.values.sumOf { it.size }} 个会话",
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            if (preferences.groupByFolder)
                IconButton(
                    onClick = {
                        collapsed =
                            if (collapsed.containsAll(groups.keys)) emptySet() else groups.keys
                    }
                ) {
                    Icon(
                        if (collapsed.containsAll(groups.keys)) Icons.Default.UnfoldMore
                        else Icons.Default.UnfoldLess,
                        "展开或收拢全部",
                        tint = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
        }
        LazyVerticalGrid(
            columns = GridCells.Adaptive(340.dp),
            contentPadding = PaddingValues(bottom = 24.dp + screenBottomInset()),
            horizontalArrangement = Arrangement.spacedBy(10.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            groups.forEach { (cwd, sessions) ->
                if (cwd.isNotEmpty())
                    item(key = "group:$cwd", span = { GridItemSpan(maxLineSpan) }) {
                        Row(
                            Modifier.fillMaxWidth()
                                .clickable {
                                    collapsed =
                                        if (cwd in collapsed) collapsed - cwd else collapsed + cwd
                                }
                                .heightIn(min = 48.dp)
                                .padding(top = 8.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Icon(
                                if (cwd in collapsed) Icons.Default.ChevronRight
                                else Icons.Default.ExpandMore,
                                null,
                                Modifier.size(18.dp),
                                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                            Spacer(Modifier.width(6.dp))
                            Text(
                                cwd.substringAfterLast('/').ifBlank { cwd },
                                Modifier.weight(1f),
                                style = MaterialTheme.typography.titleSmall,
                                maxLines = 2,
                                overflow = TextOverflow.Ellipsis,
                            )
                            Text(
                                sessions.size.toString(),
                                style = MaterialTheme.typography.labelMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                if (cwd !in collapsed)
                    items(sessions, key = { it.str("id") }) { session ->
                        SessionCard(
                            session,
                            search.isNotEmpty(),
                            { model.openSession(session.str("id")) },
                            { rename = session },
                            { model.action("/sessions/${session.str("id")}", "DELETE") },
                        )
                    }
            }
            if (groups.values.all { it.isEmpty() })
                item(span = { GridItemSpan(maxLineSpan) }) {
                    EmptyState(
                        if (search.isBlank()) "从一个想法开始" else "没有找到会话",
                        if (search.isBlank()) "连接电脑后，点右上角新建会话。" else "试试其他标题或目录关键词。",
                    )
                }
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

@OptIn(ExperimentalLayoutApi::class)
@Composable
internal fun SessionCard(
    session: JSONObject,
    showsPath: Boolean,
    open: () -> Unit,
    rename: () -> Unit,
    delete: () -> Unit,
) {
    var menu by remember { mutableStateOf(false) }
    Card(
        onClick = open,
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(20.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
    ) {
        Column(
            Modifier.padding(start = 16.dp, end = 12.dp, top = 8.dp, bottom = 16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    session.str("title", "新会话"),
                    Modifier.weight(1f),
                    style = MaterialTheme.typography.titleMedium,
                    maxLines = if (LocalDensity.current.fontScale > 1.3f) 4 else 2,
                    overflow = TextOverflow.Ellipsis,
                )
                Box {
                    IconButton(onClick = { menu = true }) {
                        Icon(
                            Icons.Default.MoreHoriz,
                            "会话操作",
                            tint = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                    DropdownMenu(menu, { menu = false }) {
                        DropdownMenuItem(
                            text = { Text("重命名") },
                            onClick = {
                                menu = false
                                rename()
                            },
                        )
                        DropdownMenuItem(
                            text = { Text("删除 / 隐藏") },
                            onClick = {
                                menu = false
                                delete()
                            },
                        )
                    }
                }
            }
            FlowRow(
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                verticalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                Agent(session.str("agent"))
                StatusMark(session.str("status"))
            }
            val branch = session.str("branch")
            if (branch.isNotBlank() || session.str("source") == "terminal") {
                FlowRow(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    if (session.str("source") == "terminal")
                        Text(
                            "终端会话",
                            style = MaterialTheme.typography.labelMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    if (branch.isNotBlank())
                        Text(
                            branch,
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            fontFamily = FontFamily.Monospace,
                            maxLines = 2,
                        )
                }
            }
            if (showsPath)
                Text(
                    session.str("cwd"),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                )
        }
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
            Modifier.size(17.dp)
                .then(
                    if (name == "omp")
                        Modifier.background(Color(0xFF242428), RoundedCornerShape(3.dp))
                            .padding(1.dp)
                    else Modifier
                ),
        )
        Text(
            when (name) {
                "claude" -> "Claude"
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
    // 预测式返回：手势推进时会话页跟着缩放淡出，对齐 iOS 的边缘滑动返回；
    // Android 13 及以下拿不到进度，等价于过去的 BackHandler。
    var back by remember(sid) { mutableFloatStateOf(0f) }
    var backFromLeft by remember(sid) { mutableStateOf(true) }
    PredictiveBackHandler { events ->
        try {
            events.collect {
                back = it.progress
                backFromLeft = it.swipeEdge == BackEventCompat.EDGE_LEFT
            }
            model.openSession(null)
        } catch (cancelled: CancellationException) {
            back = 0f
            throw cancelled
        }
    }
    Column(
        Modifier.fillMaxSize()
            .graphicsLayer {
                val shrink = 1f - .08f * back
                scaleX = shrink
                scaleY = shrink
                translationX = 40.dp.toPx() * back * if (backFromLeft) 1f else -1f
                alpha = 1f - .25f * back
                shape = RoundedCornerShape(28.dp * back)
                clip = back > 0f
            }
            .windowInsetsPadding(LocalScreenInsets.current.only(WindowInsetsSides.Horizontal))
    ) {
        Row(
            Modifier.fillMaxWidth()
                .windowInsetsPadding(LocalScreenInsets.current.only(WindowInsetsSides.Top))
                .padding(horizontal = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            IconButton(onClick = { model.openSession(null) }) {
                Icon(Icons.AutoMirrored.Filled.ArrowBack, "返回")
            }
            Column(Modifier.weight(1f)) {
                Text(
                    session.str("title", "会话"),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    style = MaterialTheme.typography.titleMedium,
                )
                Row(
                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Agent(session.str("agent"))
                    Text(
                        statusLabel(session.str("status")),
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 1,
                    )
                }
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
        val rows = chatTimeline(messages)
        val follow by remember { derivedStateOf { !list.canScrollForward } }
        var followLatest by remember(sid) { mutableStateOf(true) }
        var positioned by remember(sid) { mutableStateOf(false) }
        LaunchedEffect(list, sid) {
            list.interactionSource.interactions.collect { interaction ->
                if (interaction is DragInteraction.Start) followLatest = false
                if (interaction is DragInteraction.Stop) {
                    snapshotFlow { list.isScrollInProgress }.first { !it }
                    followLatest = !list.canScrollForward
                }
            }
        }
        LaunchedEffect(
            sid,
            state.loading,
            rows.size,
            messages.lastOrNull()?.toString(),
            session.items("queue").size,
            state.outbox.size,
        ) {
            if (!state.loading && (!positioned || followLatest) && rows.isNotEmpty()) {
                // Anchor a bottom sentinel, not the top of a potentially very tall final message.
                withFrameNanos {}
                list.scrollToItem(
                    rows.size +
                        session.items("queue").size +
                        (if (session.optBoolean("queuePaused")) 1 else 0) +
                        state.outbox.count { it.str("sessionId") == sid }
                )
                positioned = true
            }
        }
        Box(Modifier.weight(1f)) {
            LazyColumn(
                state = list,
                modifier = Modifier.fillMaxSize().testTag("chat-timeline"),
                contentPadding = PaddingValues(16.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                items(rows, key = { it.id }) { row ->
                    if (row.activity) ActivityGroup(row, file = { filePath = it })
                    else {
                        val m = row.messages.first()
                        val user = m.str("role") == "user"
                        Row(
                            Modifier.fillMaxWidth(),
                            horizontalArrangement = if (user) Arrangement.End else Arrangement.Start,
                        ) {
                            Surface(
                                Modifier.fillMaxWidth(if (user) .9f else 1f),
                                shape =
                                    if (user) RoundedCornerShape(22.dp, 22.dp, 6.dp, 22.dp)
                                    else RoundedCornerShape(0.dp),
                                color =
                                    if (user) MaterialTheme.colorScheme.primary
                                    else Color.Transparent,
                                contentColor =
                                    if (user) MaterialTheme.colorScheme.onPrimary
                                    else MaterialTheme.colorScheme.onSurface,
                            ) {
                                Column(
                                    Modifier.padding(
                                        horizontal = if (user) 16.dp else 4.dp,
                                        vertical = 12.dp,
                                    )
                                ) {
                                    Markdown(m.str("text")) { link ->
                                        if (
                                            link.startsWith("https://") ||
                                                link.startsWith("http://")
                                        )
                                            context.startActivity(
                                                Intent(Intent.ACTION_VIEW, Uri.parse(link))
                                            )
                                        else
                                            filePath =
                                                Uri.decode(
                                                    link
                                                        .removePrefix("file://")
                                                        .substringBefore('#')
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
                                    if (m.items("toolCalls").isNotEmpty())
                                        ToolGroup(
                                            m.items("toolCalls"),
                                            "tools:${m.str("id")}",
                                            file = { filePath = it },
                                        )
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
                                            Icon(
                                                Icons.Default.ContentCopy,
                                                "复制",
                                                Modifier.size(20.dp),
                                            )
                                        }
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
                item(key = "timeline-bottom") {
                    Spacer(Modifier.fillMaxWidth().height(1.dp).testTag("timeline-bottom"))
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
            Modifier.fillMaxWidth()
                .windowInsetsPadding(LocalScreenInsets.current.only(WindowInsetsSides.Bottom))
                .padding(10.dp),
            shape = RoundedCornerShape(26.dp),
            colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
            border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant),
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
                            focusedIndicatorColor = Color.Transparent,
                            unfocusedIndicatorColor = Color.Transparent,
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
                    FilledIconButton(
                        onClick = { model.send() },
                        enabled =
                            state.draft.str("text").isNotBlank() ||
                                state.draft.items("attachments").isNotEmpty(),
                    ) {
                        Icon(Icons.AutoMirrored.Filled.Send, "发送")
                    }
                }
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(4.dp),
                    modifier = Modifier.horizontalScroll(rememberScrollState()),
                ) {
                    TextButton(
                        onClick = { panel = "模式" },
                        colors =
                            ButtonDefaults.textButtonColors(
                                contentColor = MaterialTheme.colorScheme.onSurfaceVariant
                            ),
                    ) {
                        Text(
                            when (val mode = session.str("mode", "默认")) {
                                "normal" -> "按需审批"
                                "plan" -> "只读规划"
                                "trust" -> "信任模式"
                                else -> mode
                            },
                            maxLines = 1,
                        )
                    }
                    TextButton(
                        onClick = { panel = "模型" },
                        colors =
                            ButtonDefaults.textButtonColors(
                                contentColor = MaterialTheme.colorScheme.onSurfaceVariant
                            ),
                    ) {
                        Text(session.str("model", "默认模型").substringAfterLast('/'), maxLines = 1)
                    }
                    TextButton(
                        onClick = { panel = "思考强度" },
                        colors =
                            ButtonDefaults.textButtonColors(
                                contentColor = MaterialTheme.colorScheme.onSurfaceVariant
                            ),
                    ) {
                        Text(session.str("effort", "默认"), maxLines = 1)
                    }
                    Surface(
                        shape = RoundedCornerShape(22.dp),
                        color = MaterialTheme.colorScheme.surfaceContainerHigh,
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
    val ink = LocalContentColor.current.toArgb()
    val linkInk =
        if (LocalContentColor.current == MaterialTheme.colorScheme.onPrimary) ink
        else MaterialTheme.colorScheme.primary.toArgb()
    val codeInk = MaterialTheme.colorScheme.onSurface.toArgb()
    val codeBackground = MaterialTheme.colorScheme.surfaceContainerHigh.toArgb()
    val fontScale = LocalDensity.current.fontScale
    val markwon =
        remember(context, codeBackground, linkInk, codeInk) {
            Markwon.builder(context)
                .usePlugin(TablePlugin.create(context))
                .usePlugin(StrikethroughPlugin.create())
                .usePlugin(
                    object : io.noties.markwon.AbstractMarkwonPlugin() {
                        override fun configureTheme(
                            builder: io.noties.markwon.core.MarkwonTheme.Builder
                        ) {
                            builder
                                .linkColor(linkInk)
                                .codeBackgroundColor(codeBackground)
                                .codeTextColor(codeInk)
                        }

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
                setTextColor(ink)
                textSize = 16f
                setLineSpacing(4f * resources.displayMetrics.density, 1.12f)
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
            it.setTextColor(ink)
            it.setLinkTextColor(linkInk)
            it.textSize = 16f
            val renderKey = listOf(text, ink, linkInk, codeBackground, fontScale)
            if (it.tag != renderKey) {
                markwon.setMarkdown(it, linkLocalFiles(text))
                it.tag = renderKey
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

@Composable
private fun ConnectorVersionLabel(model: AppModel, device: Device) {
    var version by remember(device.id, device.base) { mutableStateOf("读取中…") }
    var revision by remember { mutableIntStateOf(0) }
    LaunchedEffect(device.id, device.base, revision) {
        version = "读取中…"
        try {
            val health = model.api.json(null, "/health", base = device.base) as JSONObject
            version = if (health.str("connectorId") != device.id) "设备身份不符"
                else health.str("version").ifBlank { "版本未知" }
        } catch (e: kotlinx.coroutines.CancellationException) { throw e }
        catch (_: Exception) { version = "暂不可获取" }
    }
    TextButton(onClick = { revision++ }, contentPadding = PaddingValues(0.dp)) {
        Text("连接器 $version", style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}
