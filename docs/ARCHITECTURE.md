# YzVibe 架构

YzVibe 将手机交互与桌面执行分开：iOS 是控制端，Node.js 连接器是会话与事件中心，Claude Code / Codex 子进程负责实际编程任务。本文依据当前仓库实现描述。

![1.00](assets/architecture.svg)

## 可编辑总览

下面的 Mermaid 与 SVG 总览表达相同的组件关系；修改架构时应同步更新两者。

```mermaid
flowchart LR
    subgraph Phone["iPhone · 控制端"]
        UI["SwiftUI / AppStore"]
        Client["ConnectorClient · REST + WS"]
        Keychain["Keychain · 设备凭据"]
        UI <--> Client
        Client --- Keychain
    end
    Access["LAN / Tailscale / HTTPS 隧道"]
    subgraph Desktop["用户电脑 · 执行端"]
        Server["Node.js 连接器 · 鉴权 / REST / WebSocket"]
        Store["Store · 会话 / 消息 / 审批 / 设备"]
        Rules["审批规则"]
        Claude["Claude 驱动 · stream-json"]
        Codex["Codex App Server · thread / turn"]
        Bridge["MCP approve 桥"]
        Files["文件浏览 / 下载 / 图片上传"]
        Disk[("~/.yzvibe/ 与工作目录")]
        History["终端历史导入 · transcripts"]
        Push["Push · APNs HTTP/2"]
        Server <--> Store
        Store <--> Disk
        Server <--> Files
        Files <--> Disk
        Server --> Claude
        Server --> Codex
        Claude -->|事件| Store
        Codex -->|事件| Store
        Claude <-->|权限请求与决定| Bridge
        Bridge <-->|内部 HTTP| Server
        Store <--> Rules
        History --> Store
        Store -->|事件| Push
    end
    Client <--> Access
    Access <-->|REST / WebSocket| Server
    APNs["Apple APNs · 可选通知"]
    Push --> APNs
    APNs --> UI
    Model["Agent 配置的模型服务"]
    Claude <--> Model
    Codex <--> Model
```

## 组件与源码

| 层         | 主要职责                           | 入口                                                                                                                |
| --------- | ------------------------------ | ----------------------------------------------------------------------------------------------------------------- |
| iOS 展示与状态 | 设备、会话、聊天、审批、文件；事件合并与前台恢复       | [AppStore.swift](../ios/Sources/YzVibeKit/Store/AppStore.swift)、[Features](../ios/Sources/YzVibeKit/Features)     |
| iOS 通信    | REST、WebSocket、配对和 Keychain 凭据 | [ConnectorClient.swift](../ios/Sources/YzVibeKit/Networking/ConnectorClient.swift)                                |
| 连接器入口     | 进程管理、访问方式、配对展示                 | [CLI](../connector/bin/yzvibe.js)、[daemon.js](../connector/src/daemon.js)、[tunnel.js](../connector/src/tunnel.js) |
| API 与事件   | 路由、设备鉴权、Agent 调度、WS 广播         | [server.js](../connector/src/server.js)                                                                           |
| 状态与持久化    | 会话、消息、审批、设备和规则                 | [store.js](../connector/src/store.js)、[rules.js](../connector/src/rules.js)                                       |
| Agent 适配  | CLI 子进程生命周期与事件翻译               | [claude.js](../connector/src/agents/claude.js)、[codex-app-server.js](../connector/src/agents/codex-app-server.js)                       |
| 权限桥       | 将 Claude MCP 权限请求转成等待手机决定的请求   | [mcp-approve.js](../connector/src/mcp-approve.js)                                                                 |
| 文件与历史     | 文件边界、图片上传、终端历史扫描与翻译            | [files.js](../connector/src/files.js)、[transcripts.js](../connector/src/transcripts.js)                           |
| 通知与维护     | APNs、空闲进程回收、过期资源清理             | [push.js](../connector/src/push.js)、[cleanup.js](../connector/src/cleanup.js)                                     |

## 一次 Claude 审批的往返

```mermaid
sequenceDiagram
    participant Phone as iOS App
    participant Server as 连接器 / Store
    participant Agent as Claude Code
    participant MCP as MCP approve
    participant Apple as Apple APNs
    Phone->>Server: 发送会话消息（REST）
    Server->>Agent: stream-json 输入
    Agent->>MCP: 工具权限请求
    MCP->>Server: 内部审批请求
    alt 命中有效放行规则
        Server-->>MCP: 允许
        Server-->>Phone: 自动允许记录（WebSocket）
    else 等待手机决定
        Server-->>Phone: 待审批事件（WebSocket）
        opt 已配置 APNs
            Server->>Apple: 审批通知
            Apple-->>Phone: 通知 / 跳转入口
        end
        Phone->>Server: 允许 / 拒绝（REST）
        Server-->>MCP: 审批结果
    end
    MCP-->>Agent: 权限决定
    Agent-->>Server: 执行结果 / 对话事件
    Server-->>Phone: 消息与工具卡更新（WebSocket）
```

Codex 生产驱动通过 App Server 的 thread / turn RPC 续聊并处理手机审批。Normal 使用工作目录可写沙箱和 on-request 审批，Plan 使用只读沙箱。旧 exec 驱动保留在源码中，不是当前服务端入口。Mock 驱动用于不依赖模型服务的开发演示。

## 状态、恢复与边界

- **控制与事件**：REST 处理操作和状态查询，WebSocket 推送事件；App 恢复前台后重连并同步消息。APNs 提供通知入口，完整内容仍通过连接器读取。
- **会话生命周期**：Claude 多轮复用进程，空闲回收后使用会话 ID 恢复；Codex 通过 App Server 管理 thread 与 turn。连接器能发现并导入本机终端历史。
- **数据位置**：连接器状态保存在 `~/.yzvibe/`，工作文件保留在项目目录；客户端凭据进入 Keychain。连接器数据目录可通过 `YZVIBE_HOME` 指定。
- **网络边界**：局域网使用 HTTP / WS；HTTPS 隧道在外部入口提供 TLS。Tailscale 是另一种网络可达方式，不是独立的 YzVibe 服务。模型服务与 Apple APNs 均位于用户电脑之外。
- **通知内容**：推送可包含审批或回复摘要，不能将“本地优先”理解成没有外部数据传输。
- **访问控制**：一次性配对码用于签发设备 Token；撤销设备会使其凭据失效。具体接口、鉴权方式和数据模型见 [共享协议](../shared/protocol.md)。

Live Activity 已通过 WidgetKit 扩展和 `SessionActivity.swift` 接入，连接器接收活动 Token 后通过 APNs 更新状态。消息队列、Git 改动视图、命令 / Skill 面板和候选地址切换也已加入主链路。Android 与小程序仍为规划。

本图展示组件关系，不表示所有异常路径均已验证。当前检查发现的问题见 [优化与拓展检查报告](REVIEW.md)。

## 可靠投递与交付记录

Connector 0.1.1 新增 `requests.js` 接收限额与字段验证、`diagnostics.js` 脱敏诊断；Store 将投递接收记录和队列原子保存，并用追加日志恢复流式文本。iOS `AppStoreDelivery.swift` 管理磁盘待发送箱、接收对账和交付记录，WS 快照与增量共用有序通道。详见 [协议补充](../shared/protocol.md#connector-011可靠投递恢复与诊断) 和 [build 11](RELEASE-0.1.0-11.md)。

iOS build 12 的 `AppStoreConnections.swift` 在目标地址身份与 Token 验证成功后提交切换；HTTP 地址版本避免旧故障转移覆盖新选择。`TaskRun` 读取已有消息关联，交付卡放回其所属轮次。详见 [build 12](RELEASE-0.1.0-12.md)。
