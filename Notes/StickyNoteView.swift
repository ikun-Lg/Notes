//
//  StickyNoteView.swift
//  Notes
//

import SwiftUI
#if os(macOS)
import AppKit
#endif

/// 窗口根视图：`WindowGroup(for:)` 启动时值为 nil，首次出现时生成
/// UUID 写回绑定，使该窗口此后可被系统状态恢复还原到同一张便笺。
struct StickyNoteRootView: View {
    @Binding var noteID: UUID?

    var body: some View {
        if let id = noteID {
            StickyNoteView(noteID: id)
        } else {
            Color.clear
                .task {
                    if noteID == nil {
                        noteID = UUID()
                    }
                }
        }
    }
}

/// 液态玻璃悬浮便笺主视图：富文本编辑 + 自动保存。
struct StickyNoteView: View {
    /// 每个窗口持有自己的模型实例，内容互不影响。
    @State private var model: NoteModel

    @Environment(\.fontResolutionContext) private var fontResolutionContext

    @AppStorage(NoteTint.storageKey) private var tint: NoteTint = .yellow
    @AppStorage(NoteTint.opacityStorageKey) private var tintOpacity = NoteTint.defaultOpacity

    init(noteID: UUID) {
        _model = State(initialValue: NoteModel(id: noteID))
    }

    var body: some View {
        @Bindable var model = model

        TextEditor(text: $model.note, selection: $model.selection)
            .textEditorStyle(.plain)
            .scrollContentBackground(.hidden)
            .font(.body)
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        // 液态玻璃铺在内容之下的背景层：铺满整个窗口，圆角由窗口原生
        // 裁切统一决定。底色用独立颜色层叠在玻璃之上而非烘进玻璃 tint：
        // 玻璃在窗口失焦时会切换为非激活渲染（变透明、颜色被冲淡），
        // 固定颜色层则不受按键状态影响，失焦后底色保持不变。
        .background {
            ZStack {
                Color.clear
                    .glassEffect(.regular, in: Rectangle())
                tint.color.opacity(tintOpacity)
            }
            .ignoresSafeArea()
        }
        .focusedSceneValue(
            \.noteFormatter,
            NoteFormatter(model: model, fontResolutionContext: fontResolutionContext)
        )
        .onChange(of: model.note) {
            model.convertTypedTodoMarkers()
            model.scheduleAutosave()
        }
        .onDisappear {
            model.flushPendingSave()
        }
        #if os(macOS)
        .onReceive(
            NotificationCenter.default.publisher(
                for: NSApplication.willTerminateNotification
            )
        ) { _ in
            model.flushPendingSave()
        }
        #endif
    }
}

// MARK: - 预览

#Preview("便笺") {
    if #available(macOS 26.0, *) {
        StickyNoteView(noteID: UUID())
            .frame(width: 360, height: 380)
    }
}
