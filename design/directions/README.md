# YzVibe 视觉方向对比

> **已选定：方向 B「焦橙纸感」**（2026-09-11）。规范见 [docs/DESIGN.md](../../docs/DESIGN.md)，
> 实现见 `ios/Sources/YzVibeKit/Design/`。本目录保留为选型记录。

四个候选方向，同样两个核心屏（会话列表 / 聊天与审批）。四个方案的**结构都已换成苹果原生**（系统大标题、List 分组、系统 Tab 栏），差异在中性色、材质和橙色的用法。

| | 方向 | 一句话 | 预览 |
|---|---|---|---|
| A | 原生优先 | 橙色只做 tint 和填充，不承担文字对比 | [A-native.png](A-native.png) |
| B | 焦橙纸感 | 系统结构 + 暖纸中性 + 一个焦橙实心 | [B-terracotta.png](B-terracotta.png) |
| C | 液态玻璃 | 深色为底，iOS 26 玻璃浮层，亮橙发光 | [C-glass.png](C-glass.png) |
| D | 现状修正 | 保留装饰球与五色，只修对比度和结构 | [D-current-fixed.png](D-current-fixed.png) |

- 浏览器打开 `index.html` 看完整对比（含色板、对比度实测值、适合 / 代价 / 工作量）。
- 改设计：编辑 `build.py` 后 `python3 build.py` 重新生成 `index.html`。
- 重出 PNG：`python3 _shots.py` 生成临时页，再用 headless Chrome 截图（见 git 历史里的命令）。

选定方向后，把结论同步回 `docs/DESIGN.md`，再改 `ios/Sources/YzVibeKit/Design/Theme.swift` 与 `design/canvas/build.py`。
