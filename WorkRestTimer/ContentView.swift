import SwiftUI
import UserNotifications
import Combine
import AVFoundation
import Darwin

class AppManager: ObservableObject {
    // --- 用户配置 ---
    @AppStorage("workMinutes") var workMinutes: Int = 60
    @AppStorage("breakMinutes") var breakMinutes: Int = 10
    @AppStorage("warningMinutes") var warningMinutes: Int = 1
    @AppStorage("lockFrequencySeconds") var lockFrequencySeconds: Int = 5
    @AppStorage("selectedSound") var selectedSound: String = "Glass" // 新增：存储选择的声音
    
    // --- 运行状态 ---
    @Published var isRunning: Bool = false
    @Published var remainingSeconds: Int = 0
    @Published var currentPhase: String = "待命"
    
    private var mainTimer: AnyCancellable?
    private var lockReloaderTimer: AnyCancellable?
    private var lockTimestamp: Date?
    private var isBreakTimerFinished: Bool = false
    
    private var audioPlayer: NSSound? // 新增：音频播放器
    private var soundRepeatCount: Int = 0 // 用于记录当前播放次数

    init() {
        setupLockObservers()
    }

    // 1. 请求权限并在成功后启动
    func toggleService() {
        if isRunning {
            stopService()
        } else {
            let center = UNUserNotificationCenter.current()
            center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                DispatchQueue.main.async {
                    self.isRunning = true
                    self.startWorkPhase()
                    if granted {
                        self.sendNotification(title: "服务已开启", body: "工作-锁屏循环已开始，预警功能正常。")
                    } else {
                        print("警告：用户拒绝了通知权限")
                    }
                }
            }
        }
    }

    private func stopService() {
        isRunning = false
        mainTimer?.cancel()
        lockReloaderTimer?.cancel()
        currentPhase = "已停止"
        remainingSeconds = 0
    }

    // 2. 阶段控制
    private func startWorkPhase() {
        mainTimer?.cancel()
        lockReloaderTimer?.cancel()
        isBreakTimerFinished = false
        currentPhase = "工作中"
        remainingSeconds = workMinutes * 60
        runMainLogic()
    }

    private func startBreakPhase() {
        currentPhase = "休息中"
        remainingSeconds = breakMinutes * 60
        isBreakTimerFinished = false
        
        executeLockCommand() // 立即执行第一次锁屏
        
        // 开启强制锁屏循环
        lockReloaderTimer = Timer.publish(every: Double(lockFrequencySeconds), on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.executeLockCommand()
            }
    }

    // 3. 计时器逻辑
    private func runMainLogic() {
        mainTimer = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self else { return }
                
                if self.remainingSeconds > 0 {
                    self.remainingSeconds -= 1
                    
                    // 检查是否到达预警时间
                    if self.currentPhase == "工作中" && self.remainingSeconds == self.warningMinutes * 60 {
                        self.sendNotification(title: "锁屏提醒", body: "电脑将在 \(self.warningMinutes) 分钟后强制锁屏休息。")
                        self.currentPhase = "预警中"
                    }
                } else {
                    // 时间到
                    if self.currentPhase != "休息中" {
                        self.startBreakPhase()
                    } else {
                        // 休息倒计时结束
                        self.mainTimer?.cancel()
                        self.lockReloaderTimer?.cancel() // 停止强制锁屏，允许用户解锁
                        self.isBreakTimerFinished = true
                        self.currentPhase = "等待解锁"
                        
                        self.wakeUpScreen()
                        
                        self.soundRepeatCount = 0
                        self.playSystemSoundRepeating(times: 3)
                        self.sendNotification(title: "休息结束", body: "休息时间到，请解锁开启新一轮工作。")
                    }
                }
            }
    }
    
    // 新增：循环播放逻辑
    func playSystemSoundRepeating(times: Int) {
        guard times > 0 else { return }
        
        // 停止之前的播放
        audioPlayer?.stop()
        audioPlayer = NSSound(named: NSSound.Name(selectedSound))
        
        // 播放当前声音
        audioPlayer?.play()
        soundRepeatCount += 1
        
        // 如果还没播满次数，延迟一定时间（如 1.5 秒）后递归调用
        if soundRepeatCount < times {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                // 只有在依然处于等待解锁状态时才继续播报，防止解锁后还在响
                if self?.currentPhase == "等待解锁" {
                    self?.playSystemSoundRepeating(times: times)
                }
            }
        }
    }
    
    // 新增：播放系统音频
    func playSystemSound() {
        // 停止当前正在播放的声音
        audioPlayer?.stop()
        // 加载选中的系统声音
        audioPlayer = NSSound(named: NSSound.Name(selectedSound))
        audioPlayer?.play()
    }
    // 4. 系统底层操作

    // 4. 系统底层操作
    private func executeLockCommand() {
        // 优先使用 macOS 内部私有 API 直接锁屏
        // 优势：瞬间响应，无需配置辅助功能权限，不受 App Sandbox 限制
        let libHandle = dlopen("/System/Library/PrivateFrameworks/login.framework/Versions/Current/login", RTLD_LAZY)
        if let libHandle = libHandle {
            let sym = dlsym(libHandle, "SACLockScreenImmediate")
            if let sym = sym {
                typealias SACLockScreenImmediateType = @convention(c) () -> Void
                let lockScreen = unsafeBitCast(sym, to: SACLockScreenImmediateType.self)
                lockScreen()
                return // 锁屏成功，直接返回
            }
        }
        
        print("❌ 私有 API 锁屏调用失败，尝试备用方案...")
        
        // 兜底方案：使用 NSAppleScript 调用休眠 (比通过 Process 调用 osascript 更原生)
        // 注意：如果是上架 App Store 的应用，不能使用私有 API，只能用此方案
        let script = """
        tell application "System Events"
            keystroke "q" using {control down, command down}
        end tell
        """
        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            appleScript.executeAndReturnError(&error)
            if let error = error {
                print("❌ AppleScript 执行错误: \(error)")
            }
        }
    }

    @discardableResult
    private func runProcess(_ executable: String, arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus != 0 {
                print("❌ 命令执行失败: \(executable) \(arguments.joined(separator: " "))")
                return false
            }
            return true
        } catch {
            print("❌ 无法启动命令: \(executable), error: \(error.localizedDescription)")
            return false
        }
    }

    private func setupLockObservers() {
        let center = DistributedNotificationCenter.default()
        center.addObserver(forName: NSNotification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { _ in
            self.lockTimestamp = Date()
        }
        center.addObserver(forName: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { _ in
            self.handleUnlock()
        }
    }
    
    private func handleUnlock() {
        guard isRunning else { return }
        
        // 情况 A: 休息完后用户解锁
        if isBreakTimerFinished {
            startWorkPhase()
            return
        }
        
        // 情况 B: 工作中手动锁屏，且锁够了时间
        if let lockedAt = lockTimestamp {
            let duration = Date().timeIntervalSince(lockedAt)
            if duration >= Double(breakMinutes * 60) {
                startWorkPhase()
            }
        }
        lockTimestamp = nil
    }

    func sendNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            
            // 检查提交结果
            UNUserNotificationCenter.current().add(request) { error in
                if let error = error {
                    print("❌ 通知提交失败: \(error.localizedDescription)")
                } else {
                    print("✅ 通知已成功发送至系统队列 (时间: \(Date()))")
                }
            }
    }
    
    // 新增：唤醒屏幕
    private func wakeUpScreen() {
        print("💡 正在尝试唤醒屏幕...")
        // 使用 caffeinate 的 -u 参数模拟用户活动以点亮屏幕，-t 2 表示持续 2 秒
        runProcess("/usr/bin/caffeinate", arguments: ["-u", "-t", "2"])
    }

    func formatTime(_ seconds: Int) -> String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

struct ContentView: View {
    @EnvironmentObject var manager: AppManager
    let systemSounds = ["Glass", "Blow", "Ping", "Morse", "Pop", "Tink", "Funk"]
    
    var body: some View {
        VStack(spacing: 0) {
            // --- 顶部状态区 ---
            HStack(spacing: 15) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(manager.currentPhase)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(phaseColor)
                    
                    Text(manager.formatTime(manager.remainingSeconds))
                        .font(.system(size: 32, weight: .medium, design: .monospaced))
                }
                Spacer()
                Button(action: { manager.toggleService() }) {
                    Image(systemName: manager.isRunning ? "stop.fill" : "play.fill")
                        .font(.title3)
                        .foregroundColor(.white)
                        .frame(width: 40, height: 40)
                        .background(manager.isRunning ? Color.red : Color.blue)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .frame(height: 80)
            .background(Color.primary.opacity(0.05))
            
            Divider()

            // --- 关键修改：修复后的 Form 区 ---
            Form {
                Section {
                    // 传递 Binding 时确保没有被 .disabled 限制
                    customStepper(label: "工作时长", icon: "briefcase", value: $manager.workMinutes, range: 1...120, unit: "分")
                    customStepper(label: "预警提前", icon: "bell", value: $manager.warningMinutes, range: 1...10, unit: "分")
                    customStepper(label: "休息时长", icon: "bed.double", value: $manager.breakMinutes, range: 1...60, unit: "分")
//                    customStepper(label: "锁屏频率", icon: "timer", value: $manager.lockFrequencySeconds, range: 2...60, unit: "秒")
                } header: {
                    Text("时间设置").font(.caption2).padding(.top, 5)
                }
                Section {
                    HStack {
                        Label("结束音效", systemImage: "speaker.wave.2")
                        Spacer()
                        Picker("", selection: $manager.selectedSound) {
                            ForEach(systemSounds, id: \.self) { sound in
                                Text(sound).tag(sound)
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                        .onChange(of: manager.selectedSound) { oldValue, newValue in
                            manager.playSystemSound() // 试听新选中的声音
                        }
                    }
                    
                    customStepper(label: "锁屏频率", icon: "timer", value: $manager.lockFrequencySeconds, range: 2...60, unit: "秒")
                } header: {
                    Text("提醒设置").font(.caption2)
                }
            }
            .formStyle(.grouped) // 使用分组样式可以提供更好的点击反馈
             .disabled(manager.isRunning)
            
            // --- 底部提示条 ---
            if manager.currentPhase == "等待解锁" {
                HStack {
                    Image(systemName: "lock.open.fill")
                    Text("请解锁屏幕以继续计时")
                }
                .font(.caption2)
                .foregroundColor(.orange)
                .frame(maxWidth: .infinity)
                .frame(height: 30)
                .background(Color.orange.opacity(0.1))
            }
        }
        .frame(width: 280, height: 380) // 略微调高高度以适应 Form 的默认间距
    }
    
    // --- 核心修复：重新设计的 Stepper 行 ---
    func customStepper(label: String, icon: String, value: Binding<Int>, range: ClosedRange<Int>, unit: String) -> some View {
        Stepper(value: value, in: range) {
            // 在 Stepper 的文字区域显示图标和数值，这样整个区域都能感知点击
            HStack {
                Label(label, systemImage: icon)
                Spacer()
                Text("\(value.wrappedValue)\(unit)")
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundColor(.secondary)
            }
        }
    }
    
    var phaseColor: Color {
        if !manager.isRunning { return .secondary }
        switch manager.currentPhase {
        case "工作中": return .green
        case "预警中": return .orange
        case "休息中": return .red
        case "等待解锁": return .orange
        default: return .blue
        }
    }
}
