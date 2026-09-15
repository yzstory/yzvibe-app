package icu.yzvibe.android.core

import android.app.Application
import android.net.Uri
import android.provider.OpenableColumns
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import java.io.File
import java.util.UUID
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import okhttp3.*
import org.json.JSONArray
import org.json.JSONObject

class AppModel(app: Application) : AndroidViewModel(app) {
    private val store = LocalStore(app)
    private val histories = HistoryCache(File(app.cacheDir, "history-v1"))
    private val loadedHistories = mutableSetOf<String>()
    private val historyWrites = mutableMapOf<String, Job>()

    private fun cacheHistory(device: String, id: String) {
        val key = "$device:$id"
        if (historyWrites[key] != null || id !in loadedHistories) return
        historyWrites[key] =
            viewModelScope.launch {
                delay(1000)
                if (state.value.device?.id == device) {
                    val list = state.value.snapshot.messages[id]
                    if (list != null)
                        withContext(Dispatchers.IO) { histories.save(device, id, list) }
                }
                historyWrites.remove(key)
            }
    }

    private val notifications = icu.yzvibe.android.platform.TaskNotifications(app)
    val api = ConnectorApi(store)

    data class State(
        val devices: List<Device> = emptyList(),
        val device: Device? = null,
        val snapshot: Snapshot = Snapshot(),
        val sessionId: String? = null,
        val connection: String = "未连接",
        val loading: Boolean = false,
        val error: String? = null,
        val capabilities: JSONObject = obj(),
        val draft: JSONObject = obj(),
        val outbox: List<JSONObject> = emptyList(),
    )

    private val _state = MutableStateFlow(State())
    val state = _state.asStateFlow()
    private var failures = 0
    private var socket: WebSocket? = null
    private var reconnect: Job? = null
    private var generation = 0
    private var foreground = false
    private val writes = Mutex()
    private val deliveries = Mutex()

    init {
        viewModelScope.launch {
            val devices =
                withContext(Dispatchers.IO) {
                    store.read("devices").items("items").map(Device::from)
                }
            update { copy(devices = devices) }
            devices.firstOrNull()?.let { selectDevice(it) }
        }
    }

    private fun update(block: State.() -> State) {
        _state.value = _state.value.block()
    }

    fun dismissError() = update { copy(error = null) }

    fun report(text: String) = update { copy(error = text) }

    fun launch(block: suspend () -> Unit) =
        viewModelScope.launch {
            try {
                block()
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                report(e.message ?: "操作失败")
            }
        }

    suspend fun call(
        path: String,
        method: String = "GET",
        body: JSONObject? = null,
        query: Map<String, String> = emptyMap(),
    ): Any = api.json(state.value.device ?: error("请先配对电脑"), path, method, body, query)

    fun action(path: String, method: String = "POST", body: JSONObject? = null) = launch {
        call(path, method, body)
        refresh()
    }

    fun pair(raw: String) = launch {
        val p = Pairing.parse(raw)
        val result =
            api.json(
                null,
                "/pair",
                "POST",
                obj("token" to p.token, "phoneName" to android.os.Build.MODEL),
                base = p.base,
            ) as JSONObject
        val d = Device(result.getString("connectorId"), result.str("deviceName", "我的电脑"), p.base)
        withContext(Dispatchers.IO) { store.saveToken(d.id, result.getString("deviceToken")) }
        val list = state.value.devices.filterNot { it.id == d.id } + d
        withContext(Dispatchers.IO) {
            store.write("devices", obj("items" to JSONArray(list.map { it.json() })))
        }
        update { copy(devices = list) }
        selectDevice(d)
    }

    fun editDevice(d: Device, name: String, address: String) = launch {
        validateBase(address)
        val health = api.json(null, "/health", base = address) as JSONObject
        require(health.str("connectorId") == d.id) { "此地址属于另一台电脑，未发送设备凭据" }
        val next = d.copy(name = name.ifBlank { d.name }, base = address.trimEnd('/'))
        val list = state.value.devices.map { if (it.id == d.id) next else it }
        withContext(Dispatchers.IO) {
            store.write("devices", obj("items" to JSONArray(list.map { it.json() })))
        }
        update { copy(devices = list) }
        selectDevice(next)
    }

    fun selectDevice(d: Device) {
        loadedHistories.clear()
        generation++
        socket?.cancel()
        reconnect?.cancel()
        update {
            copy(
                device = d,
                sessionId = null,
                snapshot = Snapshot(),
                draft = obj(),
                capabilities = obj(),
                connection = "正在连接",
                loading = true,
            )
        }
        launch {
            loadOutbox(d)
            val health = api.json(null, "/health", base = d.base) as JSONObject
            require(health.str("connectorId") == d.id) { "连接地址的电脑身份已变化，请重新配对" }
            val endpoints =
                health
                    .optJSONArray("endpoints")
                    ?.let { a -> (0 until a.length()).map { a.getString(it) } }
                    .orEmpty()
            if (state.value.device?.id == d.id) {
                val next = d.copy(endpoints = endpoints)
                val list = state.value.devices.map { if (it.id == d.id) next else it }
                withContext(Dispatchers.IO) {
                    store.write("devices", obj("items" to JSONArray(list.map { it.json() })))
                }
                update { copy(device = next, devices = list) }
            }
            val c = api.json(d, "/agents") as JSONObject
            if (state.value.device?.id == d.id) update { copy(capabilities = c) }
        }
        if (foreground) connect()
    }

    fun foreground(active: Boolean) {
        foreground = active
        if (active && state.value.device != null) connect()
        else {
            generation++
            socket?.cancel()
            socket = null
            reconnect?.cancel()
        }
    }

    fun connect() {
        val d = state.value.device ?: return
        reconnect?.cancel()
        socket?.cancel()
        val ticket = ++generation
        update { copy(connection = "正在重连", loading = snapshot.sessions.isEmpty()) }
        socket =
            api.socket(
                d,
                object : WebSocketListener() {
                    override fun onOpen(ws: WebSocket, r: Response) {
                        viewModelScope.launch {
                            if (ticket != generation) {
                                ws.cancel()
                                return@launch
                            }
                            loadedHistories.clear()
                            failures = 0
                            update { copy(connection = "在线") }
                            refresh()
                        }
                    }

                    override fun onMessage(ws: WebSocket, text: String) {
                        viewModelScope.launch {
                            if (ticket != generation) return@launch
                            try {
                                val event = JSONObject(text)
                                update {
                                    copy(
                                        snapshot = snapshot.reduce(event),
                                        loading =
                                            if (event.str("type") == "sync.snapshot") false
                                            else loading,
                                    )
                                }
                                if (event.str("type") == "sync.snapshot") {
                                    event.optJSONObject("messages")?.keys()?.forEach { id ->
                                        loadedHistories.add(id)
                                        cacheHistory(d.id, id)
                                    }
                                } else if (event.str("type") == "session.removed") {
                                    val id = event.str("sessionId")
                                    loadedHistories.remove(id)
                                    historyWrites.remove("${d.id}:$id")?.cancel()
                                    withContext(Dispatchers.IO) { histories.remove(d.id, id) }
                                } else {
                                    val id =
                                        event.str("sessionId").ifBlank {
                                            event
                                                .optJSONObject("message")
                                                ?.str("sessionId")
                                                .orEmpty()
                                        }
                                    if (id.isNotBlank()) cacheHistory(d.id, id)
                                }
                                notifications.update(state.value.snapshot)
                                if (event.str("type") == "sync.snapshot") reconcileAll(d)
                            } catch (e: Exception) {
                                report("同步数据失败：${e.message}")
                            }
                        }
                    }

                    override fun onFailure(ws: WebSocket, t: Throwable, r: Response?) =
                        disconnected(r)

                    override fun onClosed(ws: WebSocket, code: Int, reason: String) =
                        disconnected(null)

                    private fun disconnected(r: Response?) {
                        viewModelScope.launch {
                            if (ticket != generation) return@launch
                            loadedHistories.clear()
                            val invalid = r?.code == 401
                            val expired = r?.code in listOf(404, 410, 530)
                            update {
                                copy(
                                    connection =
                                        if (invalid) "配对已失效"
                                        else if (expired) "原地址不可用，请更新地址" else "正在重连 · 检查网络与电脑",
                                    loading = false,
                                )
                            }
                            if (!invalid && foreground) {
                                reconnect =
                                    viewModelScope.launch {
                                        delay(
                                            (1000L shl (++failures).coerceAtMost(6)).coerceAtMost(
                                                60000L
                                            )
                                        )
                                        if (ticket == generation) {
                                            recoverEndpoint(d)
                                            if (ticket == generation) connect()
                                        }
                                    }
                            }
                        }
                    }
                },
            )
    }

    private suspend fun recoverEndpoint(d: Device) {
        for (address in d.endpoints.filter { it != d.base }) {
            try {
                validateBase(address)
                val health = api.json(null, "/health", base = address) as JSONObject
                if (health.str("connectorId") != d.id || state.value.device?.id != d.id) continue
                val next = d.copy(base = address)
                val list = state.value.devices.map { if (it.id == d.id) next else it }
                withContext(Dispatchers.IO) {
                    store.write("devices", obj("items" to JSONArray(list.map { it.json() })))
                }
                update { copy(device = next, devices = list) }
                return
            } catch (e: Exception) {
                if (e is CancellationException) throw e
            }
        }
    }

    fun refresh() {
        socket?.send(
            obj(
                    "type" to "sync.request",
                    "sessionIds" to JSONArray(listOfNotNull(state.value.sessionId)),
                )
                .toString()
        )
    }

    fun openSession(id: String?) {
        update {
            copy(sessionId = id, draft = obj(), loading = id != null && id !in loadedHistories)
        }
        val d = state.value.device ?: return
        launch {
            val draft =
                writes.withLock {
                    withContext(Dispatchers.IO) {
                        val key = "draft:${d.id}:$id"
                        val saved = store.read(key)
                        val pending = store.read("outbox:${d.id}").items("items")
                        if (
                            saved.str("deliveryId").isNotBlank() &&
                                pending.any { it.str("clientMessageId") == saved.str("deliveryId") }
                        ) {
                            store.write(key, obj())
                            obj()
                        } else saved
                    }
                }
            if (
                state.value.device?.id == d.id &&
                    state.value.sessionId == id &&
                    state.value.draft.length() == 0
            )
                update { copy(draft = draft) }
        }
        if (id != null && id !in loadedHistories) {
            launch {
                val cached = withContext(Dispatchers.IO) { histories.load(d.id, id) }
                if (state.value.device?.id == d.id && state.value.sessionId == id) {
                    if (cached != null && !state.value.snapshot.messages.containsKey(id)) {
                        update {
                            copy(
                                snapshot =
                                    snapshot.copy(messages = snapshot.messages + (id to cached))
                            )
                        }
                    }
                    if (id !in loadedHistories) refresh()
                }
            }
        }
    }

    fun draft(text: String) {
        val next = state.value.draft.copy().put("text", text)
        saveDraft(next)
    }

    private fun saveDraft(next: JSONObject) {
        next.put("deliveryId", UUID.randomUUID().toString())
        val d = state.value.device ?: return
        val s = state.value.sessionId ?: return
        update { copy(draft = next) }
        launch {
            writes.withLock {
                withContext(Dispatchers.IO) { store.write("draft:${d.id}:$s", next) }
            }
        }
    }

    fun removeAttachment(id: String) =
        saveDraft(
            state.value.draft
                .copy()
                .put(
                    "attachments",
                    JSONArray(
                        state.value.draft.items("attachments").filterNot { it.str("id") == id }
                    ),
                )
        )

    fun attach(uri: Uri) {
        val deviceId = state.value.device?.id ?: return
        val sessionId = state.value.sessionId ?: return
        launch {
            val item =
                withContext(Dispatchers.IO) {
                    val resolver = getApplication<Application>().contentResolver
                    var name = "附件"
                    resolver
                        .query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
                        ?.use { if (it.moveToFirst()) name = it.getString(0) }
                    val id = UUID.randomUUID().toString()
                    val file =
                        File(getApplication<Application>().filesDir, "attachments/$id").apply {
                            parentFile?.mkdirs()
                        }
                    try {
                        resolver.openInputStream(uri)!!.use { input ->
                            file.outputStream().use { out ->
                                val b = ByteArray(8192)
                                var total = 0
                                while (true) {
                                    val n = input.read(b)
                                    if (n < 0) break
                                    total += n
                                    require(total <= 20 * 1024 * 1024) { "附件不能超过 20 MB" }
                                    out.write(b, 0, n)
                                }
                            }
                        }
                    } catch (e: Exception) {
                        file.delete()
                        throw e
                    }
                    obj(
                        "id" to id,
                        "name" to name,
                        "path" to file.path,
                        "mime" to (resolver.getType(uri) ?: "application/octet-stream"),
                    )
                }
            writes.withLock {
                val key = "draft:$deviceId:$sessionId"
                val active =
                    state.value.device?.id == deviceId && state.value.sessionId == sessionId
                val old =
                    if (active) state.value.draft
                    else withContext(Dispatchers.IO) { store.read(key) }
                require(old.items("attachments").size < 6) { "每条消息最多 6 个附件" }
                val next =
                    old.copy()
                        .put("deliveryId", UUID.randomUUID().toString())
                        .put("attachments", JSONArray(old.items("attachments") + item))
                withContext(Dispatchers.IO) { store.write(key, next) }
                if (active) update { copy(draft = next) }
            }
        }
    }

    private suspend fun loadOutbox(d: Device) {
        val items = withContext(Dispatchers.IO) { store.read("outbox:${d.id}").items("items") }
        if (state.value.device?.id == d.id) update { copy(outbox = items) }
    }

    private suspend fun persistOutbox(d: Device, items: List<JSONObject>) {
        withContext(Dispatchers.IO) {
            store.write("outbox:${d.id}", obj("items" to JSONArray(items)))
        }
        if (state.value.device?.id == d.id) update { copy(outbox = items) }
    }

    fun send(mode: String = "auto") = launch {
        val d = state.value.device ?: return@launch
        val sid = state.value.sessionId ?: return@launch
        val draft = state.value.draft
        if (draft.str("text").isBlank() && draft.items("attachments").isEmpty()) return@launch
        require(draft.str("text").length <= 64000) { "消息过长，请拆分到 64000 字符以内" }
        deliveries.withLock {
            val delivery =
                obj(
                    "clientMessageId" to
                        draft.str("deliveryId").ifBlank { UUID.randomUUID().toString() },
                    "sessionId" to sid,
                    "text" to draft.str("text"),
                    "files" to JSONArray(draft.items("attachments")),
                    "mode" to mode,
                    "state" to "pending",
                )
            val pending =
                withContext(Dispatchers.IO) { store.read("outbox:${d.id}").items("items") }
            persistOutbox(d, pending.upsert(delivery, "clientMessageId"))
            writes.withLock {
                withContext(Dispatchers.IO) { store.write("draft:${d.id}:$sid", obj()) }
                if (
                    state.value.sessionId == sid &&
                        state.value.device?.id == d.id &&
                        state.value.draft.toString() == draft.toString()
                )
                    update { copy(draft = obj()) }
            }
        }
        reconcileAll(d)
    }

    fun retryDelivery() = launch { state.value.device?.let { reconcileAll(it) } }

    private suspend fun reconcileAll(d: Device) =
        deliveries.withLock {
            var items = withContext(Dispatchers.IO) { store.read("outbox:${d.id}").items("items") }
            for (original in items.toList()) {
                val pending = original.copy()
                val id = pending.str("clientMessageId")
                val path = "/sessions/${pending.str("sessionId")}/deliveries"
                try {
                    var receipt: JSONObject? =
                        try {
                            api.json(d, "$path/$id") as JSONObject
                        } catch (e: ApiError) {
                            if (e.status == 404 && e.code == "delivery_missing") null else throw e
                        }
                    if (receipt == null) {
                        val files = pending.items("files").map { it.copy() }
                        for (file in files) if (file.str("uploadId").isBlank()) {
                            file.put(
                                "uploadId",
                                api.upload(
                                    d,
                                    File(file.str("path")),
                                    file.str("name"),
                                    file.str("mime"),
                                ),
                            )
                            pending.put("files", JSONArray(files))
                            items =
                                items.map {
                                    if (it.str("clientMessageId") == id) pending.copy() else it
                                }
                            persistOutbox(d, items)
                        }
                        receipt =
                            api.json(
                                d,
                                path,
                                "POST",
                                obj(
                                    "clientMessageId" to id,
                                    "text" to pending.str("text"),
                                    "mode" to pending.str("mode"),
                                    "attachments" to JSONArray(files.map { it.str("uploadId") }),
                                ),
                            ) as JSONObject
                    }
                    // Once the connector acknowledges durable acceptance, it owns the queue.
                    items = items.filterNot { it.str("clientMessageId") == id }
                    persistOutbox(d, items)
                } catch (e: Exception) {
                    if (e is CancellationException) throw e
                    items =
                        items.map {
                            if (it.str("clientMessageId") == id)
                                pending.put("state", "待确认").put("error", e.message ?: "网络异常")
                            else it
                        }
                    persistOutbox(d, items)
                }
            }
        }

    override fun onCleared() {
        generation++
        socket?.cancel()
        reconnect?.cancel()
    }
}
