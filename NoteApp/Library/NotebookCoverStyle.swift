import SwiftUI

/// A decorative notebook cover chosen by name and stored in `notebook.json`.
enum NotebookCoverStyle: String, CaseIterable, Identifiable {
    case midnight
    case ocean
    case sunset
    case forest
    case sand
    case rose
    case graphite
    case linen

    var id: String { rawValue }

    var name: String {
        switch self {
        case .midnight: "Midnight"
        case .ocean: "Ocean"
        case .sunset: "Sunset"
        case .forest: "Forest"
        case .sand: "Sand"
        case .rose: "Rose"
        case .graphite: "Graphite"
        case .linen: "Linen"
        }
    }

    var colors: [Color] {
        switch self {
        case .midnight: [Color(red: 0.10, green: 0.12, blue: 0.24), Color(red: 0.25, green: 0.28, blue: 0.52)]
        case .ocean: [Color(red: 0.05, green: 0.32, blue: 0.46), Color(red: 0.10, green: 0.58, blue: 0.66)]
        case .sunset: [Color(red: 0.86, green: 0.38, blue: 0.28), Color(red: 0.95, green: 0.66, blue: 0.38)]
        case .forest: [Color(red: 0.11, green: 0.29, blue: 0.20), Color(red: 0.32, green: 0.52, blue: 0.33)]
        case .sand: [Color(red: 0.72, green: 0.61, blue: 0.45), Color(red: 0.90, green: 0.83, blue: 0.68)]
        case .rose: [Color(red: 0.62, green: 0.24, blue: 0.36), Color(red: 0.86, green: 0.50, blue: 0.57)]
        case .graphite: [Color(red: 0.18, green: 0.19, blue: 0.21), Color(red: 0.40, green: 0.42, blue: 0.45)]
        case .linen: [Color(red: 0.83, green: 0.79, blue: 0.71), Color(red: 0.95, green: 0.93, blue: 0.88)]
        }
    }

    var symbol: String {
        switch self {
        case .midnight: "moon.stars"
        case .ocean: "water.waves"
        case .sunset: "sun.horizon"
        case .forest: "leaf"
        case .sand: "beach.umbrella"
        case .rose: "sparkles"
        case .graphite: "square.grid.2x2"
        case .linen: "book.closed"
        }
    }

    /// Dark covers need white titles; the pale ones read better with ink.
    var prefersLightText: Bool {
        switch self {
        case .sand, .linen: false
        default: true
        }
    }
}

struct NotebookCoverPicker: View {
    let current: String?
    let onSelect: (String?) -> Void
    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.adaptive(minimum: 120, maximum: 180), spacing: AppSpacing.l)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: AppSpacing.xl) {
                    option(title: "First Page", name: nil, isPage: true)
                    ForEach(NotebookCoverStyle.allCases) { style in
                        option(title: style.name, name: style.rawValue, style: style)
                    }
                }
                .padding(AppSpacing.xl)
            }
            // The nine covers need the whole sheet: a shorter one cut the last
            // row's label off below the fold.
            .safeAreaPadding(.bottom, AppSpacing.l)
            .navigationTitle("Notebook Cover")
            .navigationBarTitleDisplayModeInline()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .coverPickerSheetSize()
    }

    private func option(
        title: String,
        name: String?,
        style: NotebookCoverStyle? = nil,
        isPage: Bool = false
    ) -> some View {
        let selected = current == name
        return Button {
            onSelect(name)
        } label: {
            VStack(spacing: AppSpacing.s) {
                ZStack {
                    if let style {
                        // The same cloth the library card draws, so the swatch
                        // is a small picture of the notebook it chooses.
                        NotebookCoverCloth(style: style, symbolSize: 22, symbolPadding: AppSpacing.m)
                    } else {
                        RoundedRectangle(cornerRadius: AppRadius.m, style: .continuous)
                            .fill(.white)
                        Image(systemName: "doc.text.image")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }

                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.white, Color.accentColor)
                            .padding(AppSpacing.s)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    }
                }
                .aspectRatio(3 / 4, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.m, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: AppRadius.m, style: .continuous)
                        .strokeBorder(
                            selected ? Color.accentColor : Color.secondary.opacity(0.25),
                            lineWidth: selected ? 2.5 : 1
                        )
                }

                Text(title)
                    .font(.caption)
                    .foregroundStyle(selected ? Color.accentColor : .primary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
    }
}

/// A chosen cover's cloth, as the library draws it: one solid colour with a
/// whisper of light across it and the cover's symbol in the corner. Shared by
/// the library cards and the cover picker, so a swatch and the card it makes
/// are the same picture.
struct NotebookCoverCloth: View {
    let style: NotebookCoverStyle
    /// The symbol's point size, so a card and a picker swatch can differ.
    var symbolSize: CGFloat = 22
    var symbolPadding: CGFloat = AppSpacing.s

    private var symbolTint: Color {
        (style.prefersLightText ? Color.white : Color.black.opacity(0.65)).opacity(0.35)
    }

    var body: some View {
        ZStack {
            style.colors[0]
            LinearGradient(
                colors: [.white.opacity(0.10), .clear, .black.opacity(0.10)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: style.symbol)
                .font(.system(size: symbolSize, weight: .light))
                .foregroundStyle(symbolTint)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(symbolPadding)
        }
        .accessibilityHidden(true)
    }
}

private extension View {
    @ViewBuilder
    func navigationBarTitleDisplayModeInline() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }

    /// The cover picker is a sheet of nine cards: give it the room to show
    /// every name.
    @ViewBuilder
    func coverPickerSheetSize() -> some View {
        #if os(iOS)
        presentationDetents([.large])
            .presentationDragIndicator(.visible)
        #else
        self
        #endif
    }
}
