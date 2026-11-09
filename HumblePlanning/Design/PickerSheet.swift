import SwiftUI

/// One choice of a picker.
struct PickerItem: Identifiable, Hashable {
    let id: String
    let label: String
    var color: String?
    var group: String?
}

/// A list to choose one or several items from, with a search field above 8 items.
struct PickerSheet: View {
    let title: String
    let items: [PickerItem]
    let multiple: Bool
    var allowNone = false
    let onDone: (Set<String>) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selection: Set<String>
    @State private var query = ""

    init(title: String, items: [PickerItem], selected: Set<String>, multiple: Bool, allowNone: Bool = false, onDone: @escaping (Set<String>) -> Void) {
        self.title = title
        self.items = items
        self.multiple = multiple
        self.allowNone = allowNone
        self.onDone = onDone
        _selection = State(initialValue: selected)
    }

    private var shown: [PickerItem] {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return items }
        return items.filter { $0.label.localizedCaseInsensitiveContains(text) || ($0.group?.localizedCaseInsensitiveContains(text) ?? false) }
    }

    var body: some View {
        NavigationStack {
            List {
                if allowNone && !multiple && query.isEmpty {
                    row(PickerItem(id: "", label: String(localized: .none)), selected: selection.isEmpty) { finish([]) }
                }
                ForEach(shown) { item in
                    row(item, selected: selection.contains(item.id)) {
                        if multiple {
                            if selection.contains(item.id) { selection.remove(item.id) } else { selection.insert(item.id) }
                        } else {
                            finish([item.id])
                        }
                    }
                }
            }
            .accessibilityIdentifier("picker.list")
            .overlay {
                if shown.isEmpty { ContentUnavailableView.search(text: query) }
            }
            .searchable(if: items.count > 8, text: $query, prompt: String(localized: .search))
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(role: .cancel) { dismiss() } }
                if multiple {
                    ToolbarItem(placement: .topBarTrailing) {
                        let everything = selection.count == items.count
                        Button(everything ? String(localized: .none) : String(localized: .all)) {
                            selection = everything ? [] : Set(items.map(\.id))
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) { Button(role: .confirm) { finish(selection) }.accessibilityIdentifier("picker.done") }
                }
            }
        }
    }


    private func row(_ item: PickerItem, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                if item.color != nil { ColorDot(hex: item.color, size: 12) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.label).lineLimit(2)
                    if let group = item.group, !group.isEmpty {
                        Text(group).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if selected { Image(systemName: "checkmark").foregroundStyle(.tint).fontWeight(.semibold) }
            }
            .contentShape(.rect)
        }
        .foregroundStyle(.primary)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func finish(_ value: Set<String>) {
        onDone(value)
        dismiss()
    }
}

private extension View {
    /// The search field only for long lists: a field that filters nothing would still be shown and read by VoiceOver.
    @ViewBuilder
    func searchable(if enabled: Bool, text: Binding<String>, prompt: String) -> some View {
        if enabled {
            searchable(text: text, placement: .navigationBarDrawer(displayMode: .always), prompt: prompt)
        } else {
            self
        }
    }
}
