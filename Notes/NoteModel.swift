//
//  NoteModel.swift
//  Notes
//

import SwiftUI

// MARK: - 便笺模型

/// 单个便笺窗口的可观察模型：持有富文本内容与选区，负责防抖自动保存。
/// 每个窗口一个实例，按 `id` 读写各自的存档文件。
@MainActor
@Observable
final class NoteModel {
    /// 便笺存档标识（每个窗口一个，经 WindowGroup 状态恢复保持不变）。
    let id: UUID

    /// 富文本内容。
    var note: AttributedString
    var selection = AttributedTextSelection()

    /// 待办清单标记：SwiftUI `TextEditor` 的 `AttributedString` 不支持
    /// `NSTextList` 段落属性，这里用行首字形标记实现，随 RTFD 完整持久化。
    static let uncheckedMarker = "☐ "
    static let checkedMarker = "☑ "

    /// 待办标记的展示样式：未勾选灰色、已勾选绿色，中等字重更醒目。
    static func markerAttributes(
        inheriting base: AttributeContainer,
        checked: Bool
    ) -> AttributeContainer {
        var attributes = base
        attributes.foregroundColor = checked ? Color.green : Color.secondary
        attributes.font = (attributes.font ?? .default).weight(.medium)
        return attributes
    }

    /// 防抖自动保存任务。
    private var autosaveTask: Task<Void, Never>?

    init(id: UUID) {
        self.id = id
        self.note = NoteStore.load(id: id)
    }

    /// 当前插入点 / 选区将使用的属性（驱动菜单项的开关状态）。
    var typingAttributes: AttributeContainer {
        selection.typingAttributes(in: note)
    }

    /// 将属性变换应用到当前选区（或后续输入）。
    func transformAttributes(_ transform: (inout AttributeContainer) -> Void) {
        note.transformAttributes(in: &selection, body: transform)
    }

    // MARK: 自动保存

    func scheduleAutosave() {
        autosaveTask?.cancel()
        autosaveTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            NoteStore.save(note, id: id)
        }
    }

    /// 立即落盘，冲掉防抖窗口内的最后几次修改（关窗 / 退出时调用）。
    func flushPendingSave() {
        autosaveTask?.cancel()
        NoteStore.save(note, id: id)
    }

    // MARK: 输入转换

    /// 将行首输入的 Markdown 风格待办 "[] " / "【】 " 转换为 ☐ 标记。
    /// 每次内容变化后调用；无匹配时不动内容，因此不会形成循环。
    func convertTypedTodoMarkers() {
        var note = self.note
        let oldNote = note
        let characters = note.characters

        // 收集所有行首的 "[] " / "【】 "（2 个标记字符 + 1 个空格）
        var markerRanges: [Range<AttributedString.Index>] = []
        var cursor = characters.startIndex
        var atLineStart = true
        while cursor < characters.endIndex {
            let character = characters[cursor]
            if atLineStart, let inputRange = Self.todoInputRange(at: cursor, characters: characters) {
                markerRanges.append(inputRange)
                cursor = inputRange.upperBound
                atLineStart = false
                continue
            }
            atLineStart = (character == "\n")
            cursor = characters.index(after: cursor)
        }
        guard !markerRanges.isEmpty else { return }

        // 替换前先解析选区（索引基于旧内容）
        let oldIndices = selection.indices(in: oldNote)
        let replacements = markerRanges.map { (range: $0, oldLength: 3, newLength: 2) }

        for range in markerRanges.reversed() {
            let attributes = note[range].runs.first?.attributes ?? AttributeContainer()
            note.replaceSubrange(
                range,
                with: AttributedString(
                    Self.uncheckedMarker,
                    attributes: Self.markerAttributes(inheriting: attributes, checked: false)
                )
            )
        }
        self.note = note
        self.selection = Self.adjustedSelection(
            oldIndices, replacements: replacements, oldNote: oldNote, newNote: note
        )
    }

    /// 匹配行首的 "[] " / "【】 "，返回其范围。
    private static func todoInputRange(
        at index: AttributedString.Index,
        characters: AttributedString.CharacterView
    ) -> Range<AttributedString.Index>? {
        var chars: [Character] = []
        var cursor = index
        for _ in 0..<3 {
            guard cursor < characters.endIndex else { break }
            chars.append(characters[cursor])
            cursor = characters.index(after: cursor)
        }
        let prefix = String(chars)
        guard prefix == "[] " || prefix == "【】 " else { return nil }
        return index..<cursor
    }

    /// 按替换信息把旧选区映射到新内容（"[] " 3 字符 → "☐ " 2 字符）。
    ///
    /// 索引一律先转成整数位置再平移：`AttributedString.Index` 是内部存储的
    /// 不透明索引，跨替换前后的内容直接做索引运算会越界崩溃（此前的
    /// EXC_BREAKPOINT 即由此引起）。
    private static func adjustedSelection(
        _ oldIndices: AttributedTextSelection.Indices,
        replacements: [(range: Range<AttributedString.Index>, oldLength: Int, newLength: Int)],
        oldNote: AttributedString,
        newNote: AttributedString
    ) -> AttributedTextSelection {
        let oldCharacters = oldNote.characters
        let newCharacters = newNote.characters

        // 旧索引 → 整数位置
        func position(of index: AttributedString.Index) -> Int {
            oldCharacters.distance(from: oldCharacters.startIndex, to: index)
        }
        // 整数位置 → 新索引（带钳制）
        func index(at positionValue: Int) -> AttributedString.Index {
            let length = newCharacters.distance(
                from: newCharacters.startIndex, to: newCharacters.endIndex
            )
            let clamped = max(0, min(positionValue, length))
            return newCharacters.index(newCharacters.startIndex, offsetBy: clamped)
        }
        func adjust(_ oldPosition: Int) -> Int {
            var result = oldPosition
            for replacement in replacements {
                let lower = position(of: replacement.range.lowerBound)
                let upper = lower + replacement.oldLength
                if result >= upper {
                    result += replacement.newLength - replacement.oldLength
                } else if result > lower {
                    // 光标落在被替换的标记内：移到新标记之后
                    result = lower + replacement.newLength
                }
            }
            return result
        }

        switch oldIndices {
        case .insertionPoint(let point):
            return AttributedTextSelection(insertionPoint: index(at: adjust(position(of: point))))
        case .ranges(let set):
            var lowerPosition = Int.max
            var upperPosition = 0
            for range in set.ranges {
                lowerPosition = min(lowerPosition, position(of: range.lowerBound))
                upperPosition = max(upperPosition, position(of: range.upperBound))
            }
            guard lowerPosition != Int.max else { return AttributedTextSelection() }
            let adjustedLower = adjust(lowerPosition)
            let adjustedUpper = adjust(upperPosition)
            if adjustedLower == adjustedUpper {
                return AttributedTextSelection(insertionPoint: index(at: adjustedLower))
            }
            return AttributedTextSelection(range: index(at: adjustedLower)..<index(at: adjustedUpper))
        }
    }
}

// MARK: - 格式化器

/// 选区格式化操作：需要在视图层创建（依赖字体解析环境），
/// 经 `FocusedValue` 暴露给「格式」菜单命令。
@MainActor
final class NoteFormatter {
    private let model: NoteModel
    private let fontResolutionContext: Font.Context

    init(model: NoteModel, fontResolutionContext: Font.Context) {
        self.model = model
        self.fontResolutionContext = fontResolutionContext
    }

    var isBoldActive: Bool { resolvedFont.isBold }
    var isItalicActive: Bool { resolvedFont.isItalic }
    var isUnderlineActive: Bool { model.typingAttributes.underlineStyle != nil }
    var isStrikethroughActive: Bool { model.typingAttributes.strikethroughStyle != nil }

    func toggleBold() {
        transformFont { font, resolved in font.bold(!resolved.isBold) }
    }

    func toggleItalic() {
        transformFont { font, resolved in font.italic(!resolved.isItalic) }
    }

    func toggleUnderline() {
        model.transformAttributes { container in
            container.underlineStyle = container.underlineStyle == nil ? .single : nil
        }
    }

    func toggleStrikethrough() {
        model.transformAttributes { container in
            container.strikethroughStyle = container.strikethroughStyle == nil ? .single : nil
        }
    }

    // MARK: 待办清单

    /// 添加 / 移除选区所覆盖行的清单标记（空行跳过）。
    func toggleChecklist() {
        editSelectionLines { line in
            if line.hasPrefix(NoteModel.checkedMarker) || line.hasPrefix(NoteModel.uncheckedMarker) {
                return .removeMarker
            }
            return .insertMarker(NoteModel.uncheckedMarker, checked: false)
        }
    }

    /// 勾选 / 取消勾选选区内已带清单标记的行。
    func toggleCheckState() {
        editSelectionLines { line in
            if line.hasPrefix(NoteModel.uncheckedMarker) {
                return .replaceMarker(NoteModel.checkedMarker, checked: true)
            }
            if line.hasPrefix(NoteModel.checkedMarker) {
                return .replaceMarker(NoteModel.uncheckedMarker, checked: false)
            }
            return .none
        }
    }

    /// 行级编辑动作：只触碰行首标记字符，保留行内其余格式。
    private enum LineAction {
        case none
        case insertMarker(String, checked: Bool)
        case replaceMarker(String, checked: Bool)
        case removeMarker
    }

    /// 对选区（或插入点）覆盖的每一行执行动作。
    /// 从最后一行往前处理，避免插入 / 删除字符使行索引失效。
    private func editSelectionLines(_ action: (Substring) -> LineAction) {
        var note = model.note
        let characters = note.characters

        // 选区转索引：插入点为单行；范围选区取整体首尾
        let selectionStart: AttributedString.Index
        let selectionEnd: AttributedString.Index
        switch model.selection.indices(in: note) {
        case .insertionPoint(let point):
            selectionStart = point
            selectionEnd = point
        case .ranges(let set):
            var start = characters.endIndex
            var end = characters.startIndex
            for range in set.ranges {
                start = min(start, range.lowerBound)
                end = max(end, range.upperBound)
            }
            guard start != characters.endIndex else { return }
            selectionStart = start
            selectionEnd = end
        }

        // 扩展到选区起点所在行的行首
        var lineStart = selectionStart
        while lineStart > characters.startIndex,
              characters[characters.index(before: lineStart)] != "\n" {
            lineStart = characters.index(before: lineStart)
        }

        // 收集选区覆盖的所有行（含起点行，止于选区终点所在行）
        var lineRanges: [Range<AttributedString.Index>] = []
        var cursor = lineStart
        while cursor < characters.endIndex, cursor <= selectionEnd {
            var lineEnd = cursor
            while lineEnd < characters.endIndex, characters[lineEnd] != "\n" {
                lineEnd = characters.index(after: lineEnd)
            }
            lineRanges.append(cursor..<lineEnd)
            guard lineEnd < characters.endIndex else { break }
            cursor = characters.index(after: lineEnd) // 跳过换行符
        }

        for range in lineRanges.reversed() {
            let line = Substring(note.characters[range])
            guard !line.isEmpty else { continue }
            let baseAttributes = note[range].runs.first?.attributes ?? AttributeContainer()
            switch action(line) {
            case .none:
                break
            case .insertMarker(let marker, let checked):
                note.replaceSubrange(
                    range.lowerBound..<range.lowerBound,
                    with: AttributedString(
                        marker,
                        attributes: NoteModel.markerAttributes(
                            inheriting: baseAttributes, checked: checked
                        )
                    )
                )
            case .replaceMarker(let marker, let checked):
                let markerEnd = characters.index(range.lowerBound, offsetBy: 2)
                note.replaceSubrange(
                    range.lowerBound..<markerEnd,
                    with: AttributedString(
                        marker,
                        attributes: NoteModel.markerAttributes(
                            inheriting: baseAttributes, checked: checked
                        )
                    )
                )
            case .removeMarker:
                let markerEnd = characters.index(range.lowerBound, offsetBy: 2)
                note.replaceSubrange(range.lowerBound..<markerEnd, with: AttributedString(""))
            }
        }
        model.note = note
    }

    /// 相对字体属性（粗体 / 斜体）是声明式的，需先按当前环境 resolve 出
    /// 具体字重、倾斜等结果再取反；未显式设置过字体时回退到 `.default`。
    private func transformFont(_ transform: (Font, Font.Resolved) -> Font) {
        model.transformAttributes { container in
            let font = container.font ?? .default
            let resolved = font.resolve(in: fontResolutionContext)
            container.font = transform(font, resolved)
        }
    }

    private var resolvedFont: Font.Resolved {
        (model.typingAttributes.font ?? .default).resolve(in: fontResolutionContext)
    }
}

// MARK: - FocusedValue 桥接

private struct NoteFormatterKey: FocusedValueKey {
    typealias Value = NoteFormatter
}

extension FocusedValues {
    var noteFormatter: NoteFormatter? {
        get { self[NoteFormatterKey.self] }
        set { self[NoteFormatterKey.self] = newValue }
    }
}

// MARK: - 格式菜单

/// 「格式」菜单：替代原窗口内工具栏，快捷键保持 ⌘B / ⌘I / ⌘U。
struct NoteCommands: Commands {
    @FocusedValue(\.noteFormatter) private var formatter

    var body: some Commands {
        CommandMenu("格式") {
            Button("粗体") { formatter?.toggleBold() }
                .keyboardShortcut("b", modifiers: .command)
                .disabled(formatter == nil)
            Button("斜体") { formatter?.toggleItalic() }
                .keyboardShortcut("i", modifiers: .command)
                .disabled(formatter == nil)
            Button("下划线") { formatter?.toggleUnderline() }
                .keyboardShortcut("u", modifiers: .command)
                .disabled(formatter == nil)
            Button("删除线") { formatter?.toggleStrikethrough() }
                .disabled(formatter == nil)
            Divider()
            Button("待办清单") { formatter?.toggleChecklist() }
                .keyboardShortcut("l", modifiers: [.command, .shift])
                .disabled(formatter == nil)
            Button("勾选 / 取消勾选") { formatter?.toggleCheckState() }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(formatter == nil)
        }
    }
}
