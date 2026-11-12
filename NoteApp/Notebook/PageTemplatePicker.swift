import InkKit
import NoteCore
import SwiftUI

struct PageTemplatePicker: View {
    let current: PageTemplate?
    let isApplying: Bool
    let onApply: (PageTemplateItem, Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var applyToAllPages = false

    private let columns = [GridItem(.adaptive(minimum: 128, maximum: 190), spacing: 16)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
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
