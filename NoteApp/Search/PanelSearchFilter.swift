import SearchKit
import SwiftUI

/// The pages panel's search filters: what to search, which pages, and how
/// recent an edit must be. A popover rather than the library's menu, because
/// the panel's field row has room for one button and no submenu.
struct PanelSearchFilterButton: View {
    @Binding var sources: Set<PageTextSource>
    @Binding var dateRange: SearchDateRange
    @Binding var pageRange: ClosedRange<Int>?
    let pageCount: Int

    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            Image(systemName: isFiltered
                ? "line.3.horizontal.decrease.circle.fill"
                : "line.3.horizontal.decrease.circle")
                .foregroundStyle(isFiltered ? Color.accentColor : Color.secondary)
                .hitTarget()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Search Filters")
        .popover(isPresented: $isPresented) {
            form
                .frame(width: 300)
                .presentationCompactAdaptation(.popover)
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            Text("Search In")
                .font(.subheadline.weight(.semibold))
            VStack(alignment: .leading, spacing: AppSpacing.s) {
                ForEach(PageTextSource.allCases, id: \.self) { source in
                    Toggle(source.sectionTitle, isOn: sourceBinding(for: source))
                        .toggleStyle(.switch)
                }
            }

            Divider()

            Text("Pages")
                .font(.subheadline.weight(.semibold))
            Picker("Pages", selection: usesRange) {
                Text("All Pages").tag(false)
                Text("Range").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityLabel("Page Range")
            if pageRange != nil {
                Stepper("From \(fromPage.wrappedValue)", value: fromPage, in: pageBounds)
                Stepper("To \(toPage.wrappedValue)", value: toPage, in: pageBounds)
            }

            Divider()

            HStack {
                Text("Last Edited")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Picker("Last Edited", selection: $dateRange) {
                    ForEach(SearchDateRange.allCases, id: \.self) { range in
                        Text(range.title).tag(range)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }

            Divider()

            Text("Type a page number (e.g. 12 or p12) to jump to it.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button("Reset") {
                sources = Set(PageTextSource.allCases)
                pageRange = nil
                dateRange = .anyTime
            }
            .disabled(!isFiltered)
        }
        .padding(AppSpacing.l)
    }

    private var isFiltered: Bool {
        sources.count < PageTextSource.allCases.count
            || dateRange != .anyTime
            || pageRange != nil
    }

    /// Turning every source off is not allowed, so a filter always has something
    /// to search.
    private func sourceBinding(for source: PageTextSource) -> Binding<Bool> {
        Binding(
            get: { sources.contains(source) },
            set: { isOn in
                if isOn {
                    sources.insert(source)
                } else if sources.count > 1 {
                    sources.remove(source)
                }
            }
        )
    }

    /// On for a page range, off for the whole notebook.
    private var usesRange: Binding<Bool> {
        Binding(
            get: { pageRange != nil },
            set: { isOn in
                pageRange = isOn ? 1...lastPage : nil
            }
        )
    }

    /// The first and last page a self-made range may name.
    private var pageBounds: ClosedRange<Int> {
        1...lastPage
    }

    private var lastPage: Int {
        max(pageCount, 1)
    }

    private var fromPage: Binding<Int> {
        Binding(
            get: { min(max(pageRange?.lowerBound ?? 1, 1), lastPage) },
            set: { value in
                let upper = min(max(pageRange?.upperBound ?? lastPage, 1), lastPage)
                pageRange = min(max(value, 1), upper)...upper
            }
        )
    }

    private var toPage: Binding<Int> {
        Binding(
            get: { min(max(pageRange?.upperBound ?? lastPage, 1), lastPage) },
            set: { value in
                let lower = min(max(pageRange?.lowerBound ?? 1, 1), lastPage)
                pageRange = lower...max(min(value, lastPage), lower)
            }
        )
    }
}
