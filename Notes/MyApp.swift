//
//  MyApp.swift
//  Notes
//

import SwiftUI

@main
struct MyApp: App {
    var body: some Scene {
        #if os(macOS)
        // 悬浮便笺窗口（可多开）：
        // - `.windowLevel(.floating)`：置于其他应用普通窗口之上（画中画同级）
        // - `.windowStyle(.hiddenTitleBar)`：去掉标题栏但保留按键窗口能力；
        //   `.plain` 的纯 borderless 窗口 canBecomeKey=false，光标无法出现
        // - `WindowGroup(for:)`：每个窗口绑定一张便笺的 UUID，
        //   ⌘N 新建、系统状态恢复时窗口还原到对应便笺
        // - `.windowBackgroundDragBehavior(.enabled)`：配合标题栏拖动移动窗口
        WindowGroup(for: UUID.self) { $noteID in
            StickyNoteRootView(noteID: $noteID)
                .frame(minWidth: 320, minHeight: 120)
        }
        .windowStyle(.hiddenTitleBar)
        .windowLevel(.floating)
        .windowBackgroundDragBehavior(.enabled)
        .defaultSize(width: 360, height: 380)
        .windowResizability(.contentMinSize)
        .commands {
            NewNoteCommands()
            NoteCommands()
        }

        // 状态栏（菜单栏）配置面板：底色与不透明度
        MenuBarExtra("便笺设置", systemImage: "note.text") {
            NoteSettingsView()
        }
        .menuBarExtraStyle(.window)
        #else
        WindowGroup("便笺") {
            StickyNoteRootView(noteID: .constant(UUID()))
        }
        #endif
    }
}

// MARK: - 新建便笺

/// 「文件 → 新建便笺」⌘N：打开一张新便笺窗口。
struct NewNoteCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("新建便笺") {
                openWindow(value: UUID())
            }
            .keyboardShortcut("n")
        }
    }
}
