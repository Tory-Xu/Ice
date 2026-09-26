# Ice Bar 故障恢复验证

运行自动化测试（同时编译 Debug 应用）：

```sh
rtk proxy xcodebuild test -project Ice.xcodeproj -scheme Ice -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath /tmp/Ice-recovery-build CODE_SIGNING_ALLOWED=NO
```

`IceTests` 是不启动主应用的 XCTest 目标，直接编译应用使用的 `RefreshCache` 和 `PresentationRequest`。受控闭包模拟读取失败、排序失败和异步等待，不依赖当前菜单栏内容，不修改已安装应用或设置。

覆盖短暂读取/排序失败后相同窗口 ID 重试、成功空缓存复用、旧缓存失败与新缓存成功交错、两段准备等待中关闭、连续点击立即取消、新请求替代旧请求、窗口显示失败，以及显示过程中关闭。它们验证缓存提交和请求生命周期，不等同于 WindowServer 或真实 GUI 故障复现。

诊断日志：

```sh
rtk proxy /usr/bin/log stream --level debug --predicate 'subsystem == "com.jordanbaird.Ice" AND (category == "ControlItem" OR category == "MenuBarSection" OR category == "MenuBarItemManager" OR category == "IceBar")'
```

按请求 UUID 关联 toggle/show、准备、缓存读取和排序耗时、图片缓存耗时、目标屏幕、orderFront 后可见性/位置和关闭原因。ControlItem 的原始点击日志用于确认事件入口；定时后台刷新使用独立 UUID。

人工验收须使用本次构建，安装版开发分支的日志不能代替验证：

- 普通点击展开，准备期间再次点击取消，随后再次点击可以展开。
- 快速切换隐藏/始终隐藏区域，只有最后一个请求显示。
- 展开过程中切换桌面或屏幕配置，旧请求不得重新打开面板。
- 全屏、睡眠唤醒、多显示器下重复展开/关闭，检查目标屏幕和窗口位置。
- 打开自动隐藏，准备阶段不得启动计时；关闭后旧的自动隐藏任务不得影响新面板。

// TODO: tory {#继续验证桌面切换、全屏、睡眠唤醒和多显示器；已完成本机普通点击及快速连点验证，但尚未复现最初的间歇性不展开故障#}

## 点击崩溃回归（2026-09-26）

4 份安装版崩溃报告均定位到 `ControlItem.windowID` 的整数转换，再经 `IceBarPanel.updateOrigin` 触发。现在统一使用 `NSWindow.cgWindowID`：负数、零和 UInt32 越界值返回 nil，让面板使用现有备用位置。菜单栏自动隐藏的窗口观察路径也使用同一转换。

同次会话中反复触发缓存失败的窗口 34 实测为 Window Server、layer 24，而菜单栏项目要求 layer 25。`WindowListReader` 区分“读取失败”和“可读取但不属于菜单栏项目”，后者正常过滤。新增 4 项测试覆盖窗口编号边界、系统窗口过滤与真正读取失败后同 ID 重试。

随后在本机 Release 应用上确认：macOS 26 将 HItem/SItem 托管到控制中心，旧命名空间判断导致 `missingHiddenControlItem`。现为 Ice 保留标题恢复身份，对远程 `Item-*` 按窗口区分内存缓存，并在本地窗口编号不可用时查找实际控件窗口；没有合并整个开发分支或更改设置格式。上游也区分了 [ownerPID 和 sourcePID](https://github.com/jordanbaird/Ice/blob/macos-26/Ice/MenuBar/MenuBarItems/MenuBarItem.swift)，本次只补齐已确认影响展开的路径，不声称包含完整 macOS 26 兼容层。

最终 Release 的 13 项 XCTest 通过；真实图形会话中连续 9 次点击，窗口可见性按 1/0 交替，展开尺寸为 1089×43，截图确认图标出现。随后 10 次快速连点最终保持关闭，日志确认在项目缓存/图片缓存等待后丢弃已取消请求。进程存活，无新增 Ice 崩溃报告。面板先计算 hosting view 的 fittingSize 再定位，消除了首次显示时零尺寸/屏幕为空的状态。
