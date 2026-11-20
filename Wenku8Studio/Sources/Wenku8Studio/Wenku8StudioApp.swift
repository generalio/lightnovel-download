import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let appIcon = NSImage(named: "AppIcon") ?? Bundle.main.image(forResource: "AppIcon") {
            NSApp.applicationIconImage = appIcon
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
struct Wenku8StudioApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var viewModel = StudioViewModel()

    var body: some Scene {
        WindowGroup("Wenku8 Studio · 轻小说文库 EPUB 下载器") {
            ContentView()
                .environmentObject(viewModel)
                .frame(minWidth: 1020, minHeight: 680)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1220, height: 780)
    }
}
