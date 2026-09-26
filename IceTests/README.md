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

// TODO: tory {#在真实 GUI 会话中完成人工验收并记录系统版本、显示器布局与对应请求日志；本轮自动测试不证明用户原始故障已复现#}
