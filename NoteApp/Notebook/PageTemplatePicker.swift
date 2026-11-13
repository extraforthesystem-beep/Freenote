import InkKit
import NoteCore
import SwiftUI

struct PageTemplatePicker: View {
    let current: PageTemplate?
    let isApplying: Bool
    let onApplySize: ((PaperSize, PageOrientation, Bool) -> Void)?
    let onApply: (PageTemplateItem, Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var applyToAllPages = false
    @State private var paperSize: PaperSize
    @State private var orientation: PageOrientation

    private let columns = [GridItem(.adaptive(minimum: 128, maximum: 190), spacing: 16)]

    init(
        current: PageTemplate?,
        isApplying: Bool,
        currentWidth: Double? = nil,
        currentHeight: Double? = nil,
        onApplySize: ((PaperSize, PageOrientation, Bool) -> Void)? = nil,
        onApply: @escaping (PageTemplateItem, Bool) -> Void
    ) {
        self.current = current
        self.isApplying = isApplying
        self.onApplySize = onApplySize
        self.onApply = onApply

        let matched = currentWidth.flatMap { width in
            currentHeight.flatMap { height in
                PaperSize.match(width: width, height: height)
            }
        }
        _paperSize = State(initialValue: matched?.0 ?? .a4)
        _orientation = State(initialValue: matched?.1 ?? .portrait)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    if let onApplySize {
                        sizeSection(onApplySize)
                        Divider()
                            .padding(.horizontal, 20)
                    }

                    ForEach(PageTemplateItem.Category.allCases) { category in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(category.rawValue)
                                .font(.headline)
                                .padding(.horizontal, 20)

                            LazyVGrid(columns: columns, spacing: 16) {
                                ForEach(PageTemplateCatalog.items(in: category)) { item in
                                    templateButton(item)
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                    }
                }
                .padding(.vertical, 20)
            }
            .navigationTitle("Page Template")
            .navigationBarTitleDisplayModeInline()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Toggle("Apply to every page in this notebook", isOn: $applyToAllPages)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(.bar)
            }
            .overlay {
                if isApplying {
                    ProgressView("Applying…")
                        .padding(20)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                }
            }
        }
    }

    /// Paper size and orientation for the page. Changing them moves the
    /// content with the page edges instead of redrawing it.
    private func sizeSection(
        _ onApplySize: @escaping (PaperSize, PageOrientation, Bool) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Size")
                .font(.headline)
                .padding(.horizontal, 20)

            VStack(alignment: .leading, spacing: 12) {
                Picker("Paper Size", selection: $paperSize) {
                    ForEach(PaperSize.allCases) { size in
                        Text(size.displayName).tag(size)
                    }
                }
                .pickerStyle(.menu)

                Picker("Orientation", selection: $orientation) {
                    ForEach(PageOrientation.allCases) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityLabel("Orientation")

                HStack(spacing: 12) {
                    Text(dimensionText)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button("Apply Size") {
                        onApplySize(paperSize, orientation, applyToAllPages)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isApplying)
                }

                Text("Content keeps its position; it is not scaled.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .background(
                Color.secondary.opacity(0.08),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .padding(.horizontal, 20)
        }
    }

    private var dimensionText: String {
        let size = paperSize.size(orientation)
        return "\(Int(size.width.rounded())) × \(Int(size.height.rounded())) pt"
    }

    private func templateButton(_ item: PageTemplateItem) -> some View {
        Button {
            onApply(item, applyToAllPages)
        } label: {
            VStack(spacing: 8) {
                ZStack(alignment: .topTrailing) {
                    if let image = TemplateImageCache.preview(for: item.template) {
                        Image(inkImage: image)
                            .resizable()
                            .scaledToFit()
                    } else {
                        Rectangle().fill(.white)
                    }

                    if isSelected(item) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.white, Color.accentColor)
                            .padding(7)
                    }
                }
                .aspectRatio(PageTemplateCatalog.pageWidth / PageTemplateCatalog.pageHeight, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(
                            isSelected(item) ? Color.accentColor : Color.secondary.opacity(0.25),
                            lineWidth: isSelected(item) ? 2.5 : 1
                        )
                }
                .shadow(color: .black.opacity(0.08), radius: 4, y: 2)

                Text(item.name)
                    .font(.caption)
                    .foregroundStyle(isSelected(item) ? Color.accentColor : .primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
        }
        .buttonStyle(.plain)
    }

    private func isSelected(_ item: PageTemplateItem) -> Bool {
        guard let current else { return false }
        return PageTemplateCatalog.sameLayout(item.template, current)
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
}

#Preview("Page Template") {
    PageTemplatePicker(
        current: nil,
        isApplying: false,
        currentWidth: 595,
        currentHeight: 842,
        onApplySize: { _, _, _ in }
    ) { _, _ in }
}
