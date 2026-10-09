//
//  NoteStore.swift
//  Notes
//

import Foundation
import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

/// 便笺的读取与保存。
///
/// macOS 上以扁平化 RTFD（富文本数据）持久化到 Application Support，
/// 每个窗口一张便笺，各自存为 `StickyNotes/<uuid>.rtfd`；其他平台仅内存驻留。
enum NoteStore {
#if canImport(AppKit)
    private static var notesDirectory: URL {
        let directory = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Notes", isDirectory: true)
            .appendingPathComponent("StickyNotes", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
        return directory
    }

    private static func fileURL(for id: UUID) -> URL {
        notesDirectory.appendingPathComponent("\(id.uuidString).rtfd")
    }

    /// 旧版单文件便笺（多开窗口功能之前）。
    private static var legacyFileURL: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Notes", isDirectory: true)
            .appendingPathComponent("StickyNote.rtfd")
    }

    private static func decode(_ data: Data) -> AttributedString? {
        guard
            let richText = try? NSAttributedString(
                data: data,
                options: [
                    NSAttributedString.DocumentReadingOptionKey.documentType:
                        NSAttributedString.DocumentType.rtfd
                ],
                documentAttributes: nil
            )
        else { return nil }
        return try? AttributedString(richText, including: \AttributeScopes.swiftUI)
    }

    /// 读取指定便笺的存档；找不到时收养旧版单文件（一次性迁移），否则返回示例便笺。
    static func load(id: UUID) -> AttributedString {
        if let data = try? Data(contentsOf: fileURL(for: id)), let note = decode(data) {
            return note
        }
        let legacyURL = legacyFileURL
        if let data = try? Data(contentsOf: legacyURL), let note = decode(data) {
            // 已被收养过就移除，避免多个窗口重复迁移出相同内容
            try? FileManager.default.removeItem(at: legacyURL)
            return note
        }
        return .welcomeNote
    }

    static func save(_ note: AttributedString, id: UUID) {
        // Xcode 预览进程不落盘，避免副作用
        guard ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1"
        else { return }
        guard let richText = try? NSAttributedString(note, including: \AttributeScopes.swiftUI)
        else { return }
        let fullRange = NSRange(location: 0, length: richText.length)
        guard
            let data = try? richText.data(
                from: fullRange,
                documentAttributes: [
                    NSAttributedString.DocumentAttributeKey.documentType:
                        NSAttributedString.DocumentType.rtfd
                ]
            )
        else { return }
        try? data.write(to: fileURL(for: id), options: .atomic)
    }
#else
    static func load(id: UUID) -> AttributedString {
        .welcomeNote
    }

    static func save(_ note: AttributedString, id: UUID) {}
#endif
}

// MARK: - 示例内容

extension AttributedString {
    /// 首次启动展示的示例便笺，顺带演示富文本样式。
    static let welcomeNote: AttributedString = {
        var title = AttributedString("欢迎使用便笺 📝\n")
        title.font = .title3.weight(.semibold)

        var intro = AttributedString("这是一张液态玻璃质感的悬浮便笺，会一直停在其他窗口前面。\n\n")
        intro.foregroundColor = .secondary

        var lead = AttributedString("选中文字后，用菜单栏「格式」菜单切换")
        var bold = AttributedString("加粗")
        bold.font = .body.bold()
        var italic = AttributedString("、斜体")
        italic.font = .body.italic()
        var underline = AttributedString("、下划线")
        underline.underlineStyle = .single
        var strikethrough = AttributedString("、删除线")
        strikethrough.strikethroughStyle = .single
        var tail = AttributedString("；⌘B / ⌘I / ⌘U 快捷键同样有效。\n\n")

        var settings = AttributedString("点击菜单栏中的便笺图标，可以更换底色、调整透明度。\n\n")
        settings.foregroundColor = .secondary

        var checklistIntro = AttributedString("「格式」菜单还能添加待办清单；行首输入 [] 加空格也可以，例如：\n")
        var todo1 = AttributedString("☐ 按 ⌘⇧C 勾选这一项\n")
        var todo2 = AttributedString("☐ 按 ⌘⇧L 移除清单标记\n")

        var multi = AttributedString("⌘N 可以新建多张便笺，各自独立保存。\n\n")
        multi.foregroundColor = .secondary

        var drag = AttributedString("按住窗口顶部边缘，即可拖动移动便笺位置。")

        return title + intro + lead + bold + italic + underline
            + strikethrough + tail + settings + checklistIntro + todo1 + todo2 + multi + drag
    }()
}
