# WorkRestTimer

一款专为 macOS 设计的智能工作休息计时器应用。通过双模式自动化切换、强制锁屏与智能状态监控，帮助用户有效管理工作节律并强制执行休息策略。
![Uploading Kapture 2026-04-21 at 14.05.21.gif…]()

## 核心特性

* **双模式自动化切换**：应用在“工作阶段”与“休息（锁屏）阶段”之间自动循环。
* **一键启停控制**：界面提供显眼的“开始工作/停止服务”按钮，控制全局逻辑。
* **实时状态显示**：界面精确显示当前阶段（工作中、预警中、休息中、等待解锁）及剩余时间的倒计时（分:秒）。
* **参数自定义配置**：支持自定义工作时长（默认60分钟）、休息时长（默认10分钟）、预警提前时间（默认1分钟）和强制锁屏频率（默认5秒/次）。配置仅在服务停止状态下可调节以防逻辑冲突。
* **锁屏预警功能**：倒计时到达预警时间时自动触发系统通知，支持前台横幅弹出，并具备轮询提醒逻辑（如每15秒一次）确保不会错过。
* **强制休息机制**：进入休息阶段后立即触发 macOS 锁屏，并在休息期间按设定频率循环发送锁屏命令，防止中途手动唤醒。
* **智能状态监控与重置**：后台监测系统锁屏状态。若手动锁屏时长达到休息标准，解锁后自动重置工作计时；休息结束后进入“等待解锁”状态，精准在用户进入桌面瞬间开启新一轮计时。

## 目录结构

项目主体基于 SwiftUI 和标准的 Xcode 结构：

```text
.
├── build.sh                   # 一键自动化构建脚本
├── WorkRestTimer.xcodeproj    # Xcode 项目文件
└── WorkRestTimer              # 源码与资源主目录
    ├── Assets.xcassets        # 静态资源与图标
    ├── ContentView.swift      # 主界面 UI 逻辑
    ├── WorkRestTimerApp.swift # App 核心入口
    ├── Info.plist             # 应用配置清单
    └── function_list.txt      # 原始需求说明文档
```

## 编译与打包

项目提供了一个自动化的构建脚本 `build.sh`，封装了 `xcodebuild` 编译流程，动态获取路径并隔离了 DerivedData。

1. **赋予执行权限**：
   ```bash
   chmod +x build.sh
   ```
2. **执行构建**：
   ```bash
   ./build.sh
   ```
   *构建脚本会自动清理旧产物，屏蔽多余日志，并在编译成功后将 `.app` 文件统一提取至项目根目录的 `dist/` 文件夹中*。

## 技术实现与运行要求

### 运行环境与系统要求
* **macOS 系统版本**：建议 **macOS 13.0 (Ventura) 及以上版本**。项目中深度使用了较新的 SwiftUI UI 修饰符（如 `.formStyle(.grouped)`）以及底层的系统级状态监听机制。
* **脱离沙盒运行 (App Sandbox)**：**编译时必须手动关闭 App Sandbox**。应用需要调用底层私有框架、执行 Shell 进程 (`caffeinate`) 以及监听全局的锁屏状态广播，这些高级系统行为在沙盒环境下会被拦截。

### 必要的系统权限
为确保应用正常运转，运行时需要用户在 macOS“系统设置”中授予以下核心权限：
1. **通知权限 (Notifications)**：必须允许横幅与声音提醒。应用依赖 `UNUserNotificationCenter` 派发休息预警、解锁提示等，代码中已通过代理机制确保即使应用在前台激活状态，横幅也能强制弹出。
2. [cite_start]**自动化/系统事件控制权限 (Apple Events)**：应用包含用于兜底锁屏的 AppleScript 脚本，需在隐私设置中允许其控制“System Events” [cite: 2][cite_start]。(`Info.plist` 已配置说明：“歇一歇”需要控制系统事件以实现自动锁屏提醒 [cite: 2])。

### 核心技术实现亮点
* **无感瞬间锁屏 (私有 API)**：优先通过 `dlopen` 动态加载 macOS 系统底层的私有框架 `/System/Library/PrivateFrameworks/login.framework`，并直接调用 `SACLockScreenImmediate` 内存函数。这种做法实现了毫秒级锁屏，无需繁琐的辅助功能授权。
* **AppleScript 兜底机制**：若私有 API 因系统升级等原因失效，应用会自动降级使用 `NSAppleScript` 模拟系统原生快捷键 (`Cmd + Control + Q`) 进行休眠锁屏。
* **强制唤醒屏幕**：在休息阶段结束时，系统通过 `Process()` 在后台静默执行原生命令 `/usr/bin/caffeinate -u -t 2`，通过模拟底层用户活动主动点亮屏幕，提示用户开启新一轮工作。
* **系统级全局状态广播监听**：应用利用 `DistributedNotificationCenter` 实时监听 `com.apple.screenIsLocked` 与 `com.apple.screenIsUnlocked`，这使得应用能智能识别用户“中途手动离开”的情况，并在解锁时精准计算时间差，自动重置或恢复循环。
* **音频循环反馈**：使用底层的 `NSSound` 结合 GCD (Grand Central Dispatch) 递归延迟调用，在“等待解锁”状态下实现突破常规的系统提示音多次循环播报机制。
