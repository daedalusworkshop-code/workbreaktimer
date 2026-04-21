import SwiftUI
import UserNotifications

@main
struct WorkRestTimerApp: App {
    // 绑定 AppDelegate 来处理通知显示
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var manager = AppManager()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(manager)
                // 在这里设置窗口显示的标题
                .navigationTitle("一张一弛，文武之道")
        }
        .windowResizability(.contentSize)
        // 如果你想彻底隐藏标题栏文字，可以使用以下样式（可选）
        // .windowStyle(.hiddenTitleBar)
    }
}

// 必须实现此代理，否则应用在前台时通知不会弹出横幅
class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
    }
    
    // 允许前台显示通知
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
