//
//  NoteSettingsView.swift
//  Notes
//

import SwiftUI

// MARK: - 便笺底色

/// 便笺底色预设（经 `@AppStorage` 持久化，便笺窗口与状态栏面板共享同一键）。
enum NoteTint: String, CaseIterable, Identifiable {
    case yellow, pink, blue, green, purple, gray

    static let storageKey = "note.tint"
    static let opacityStorageKey = "note.tintOpacity"
    static let defaultOpacity = 0.35
    /// 底色不透明度范围：0 为纯液态玻璃，0.6 为接近实色。
    static let opacityRange = 0.0...0.6

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .yellow: .yellow
        case .pink: .pink
        case .blue: .blue
        case .green: .green
        case .purple: .purple
        case .gray: .gray
        }
    }

    var label: String {
        switch self {
        case .yellow: "黄色"
        case .pink: "粉色"
        case .blue: "蓝色"
        case .green: "绿色"
        case .purple: "紫色"
        case .gray: "灰色"
        }
    }
}

// MARK: - 状态栏配置面板

/// 菜单栏（状态栏）中的便笺配置：底色与不透明度。
@available(macOS 26.0, *)
struct NoteSettingsView: View {
    @AppStorage(NoteTint.storageKey) private var tint: NoteTint = .yellow
    @AppStorage(NoteTint.opacityStorageKey) private var tintOpacity = NoteTint.defaultOpacity

    var body: some View {
        GlassEffectContainer(spacing: 24) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("底色")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 12) {
                        ForEach(NoteTint.allCases) { option in
                            swatchButton(option)
                        }
                    }
                }

                Divider().opacity(0.4)

                VStack(alignment: .leading, spacing: 8) {
                    Text("不透明度")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        Image(systemName: "circle.lefthalf.filled")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Slider(value: $tintOpacity, in: NoteTint.opacityRange)
                        Text("\(opacityPercent)%")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 34, alignment: .trailing)
                    }
                }
            }
            .padding(14)
        }
        .frame(width: 240)
        .padding(8)
        .hoverHelp("便笺配置")
    }

    private var opacityPercent: Int {
        Int((tintOpacity / NoteTint.opacityRange.upperBound * 100).rounded())
    }

    private func swatchButton(_ option: NoteTint) -> some View {
        Button {
            withAnimation(.smooth) { tint = option }
        } label: {
            Circle()
                .fill(option.color)
                .frame(width: 24, height: 24)
                .overlay {
                    Circle()
                        .strokeBorder(.white, lineWidth: 2)
                        .opacity(tint == option ? 1 : 0)
                        .animation(.smooth, value: tint)
                }
        }
        .buttonStyle(.glass)
        .hoverHelp(option.label)
        .accessibilityLabel(option.label)
        .accessibilityAddTraits(tint == option ? [.isSelected] : [])
    }
}

// MARK: - 平台差异辅助

extension View {
    /// `.help()` 仅 macOS 可用，其他平台静默忽略。
    @ViewBuilder
    func hoverHelp(_ text: String) -> some View {
        #if os(macOS)
        self.help(text)
        #else
        self
        #endif
    }
}

// MARK: - 预览

#Preview("状态栏配置") {
    if #available(macOS 26.0, *) {
        NoteSettingsView()
    } else {
        Text("需要 macOS 26+")
    }
}
