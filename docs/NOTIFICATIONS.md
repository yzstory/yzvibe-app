# 完成通知

聊天继续逐段显示进度、工具调用和最终回复。`message.done` 仅用于结束消息流；不会触发通知。

连接器在成功结束一个实际运行的任务后发送一次 `run.completed`，包含 sessionId、runId、messageId、最终 text。Codex 优先使用 final_answer，忽略 commentary/plan；无 phase 的旧协议及 Claude 使用本轮最后一条非空助手回复。失败、中断、重复 idle 和历史同步不产生完成通知。通知内容为会话名与最终回复前 150 字。

有 APNs 注册且连接器推送就绪的手机由 APNs 负责通知，即便 WebSocket 在线；完成事件中的 remote=true 禁止该手机再发本地通知。未配置远程推送时在线手机保留本地通知，并按 runId 去重。

认证接口 `PATCH /devices/notifications` 接收布尔值 notifyOnApproval、notifyOnReply，只更新认证手机，单独持久化，不随 token 更新或注销清除。旧手机未同步时保持原默认开启行为。静默状态更新和 Live Activity 不受这两个开关影响。

App 在开关变化、启动、重连及重同步时串行同步偏好，避免快速切换被较早请求覆盖。同步失败在设置页提供重试；离线电脑在恢复连接前仍可能按旧设置发送通知。关闭时清理已展示和待发的相应本地通知，前台展示也重新检查开关。已被 APNs 接受的在途通知无法撤回。

需要同时更新 App 和连接器。旧连接器会显示通知设置待同步，不能声称其远程通知开关已生效。

验证：连接器 103 项、iOS 118 项全部通过；使用模拟 APNs 验证发送，尚未进行新版真机后台推送验证或 TestFlight 上传。
