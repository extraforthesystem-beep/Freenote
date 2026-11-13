import SwiftUI

/// The floating "3 / 12" pill over the bottom of the page.
struct PageCounterPill: View {
    let session: NotebookSession
    let onSelect: (Int) -> Void

    var body: some View {
        HStack(spacing: 0) {
            if session.pageCount == 0 {
                Text("No pages")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 44)
            } else {
                pillButton("Previous Page", systemImage: "chevron.backward") {
                    Task { await session.goToPreviousPage() }
                }
                .disabled(session.pageIndex == 0)

                Menu {
                    ForEach(0..<session.pageCount, id: \.self) { index in
                        Button {
                            onSelect(index)
                        } label: {
                            if index == session.pageIndex {
                                Label("Page \(index + 1)", systemImage: "checkmark")
                            } else {
                                Text("Page \(index + 1)")
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text("\(session.currentPageNumber) / \(session.pageCount)")
                            .font(.subheadline.monospacedDigit().weight(.medium))
                        if session.isSaving {
                            ProgressView()
                                .controlSize(.mini)
                                .accessibilityLabel("Saving")
                        }
                    }
                    .padding(.horizontal, 6)
                    .frame(minWidth: 60, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .accessibilityLabel("Page \(session.currentPageNumber) of \(session.pageCount)")

                pillButton("Next Page", systemImage: "chevron.forward") {
                    Task { await session.goToNextPage() }
                }
                .disabled(session.pageIndex + 1 >= session.pageCount)

                Divider()
                    .frame(height: 20)

                pillButton("Add Page", systemImage: "plus") {
                    Task { await session.addPage() }
                }
            }
        }
        .padding(.horizontal, 4)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.separator, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
    }

    private func pillButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 40, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(title)
    }
}

/// A small non-blocking message over the top of the page.
struct EditorBanner: View {
    let systemImage: String
    let message: String
    var tint: Color = .orange
    var actionTitle: String?
    var action: (() -> Void)?
    var onDismiss: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
            Text(message)
                .font(.subheadline)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.borderless)
                    .frame(minHeight: 44)
            }
            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, onDismiss == nil ? 14 : 4)
        .frame(minHeight: 44)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.separator, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.1), radius: 6, y: 2)
        .padding(.horizontal, 16)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}
