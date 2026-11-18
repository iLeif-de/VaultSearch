import SwiftUI

/// Sheet that builds a `created:` / `modified:` filter for the search field.
struct DateFilterView: View {
    enum Field: String, CaseIterable, Identifiable {
        case created, modified
        var id: Self { self }
        var title: LocalizedStringKey { self == .created ? "Created" : "Modified" }
    }

    enum Mode: CaseIterable, Identifiable {
        case on, between, onOrAfter, onOrBefore
        var id: Self { self }
        var title: LocalizedStringKey {
            switch self {
            case .on: "On"
            case .between: "Between"
            case .onOrAfter: "On or After"
            case .onOrBefore: "On or Before"
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
    @State private var field: Field = .created
    @State private var mode: Mode = .between
    @State private var start = Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .now
    @State private var end = Date.now
    let onApply: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Picker("Date", selection: $field) {
                    ForEach(Field.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)

                Picker("Match", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.title).tag($0) }
                }

                if mode == .between {
                    DatePicker("From", selection: $start, in: ...end, displayedComponents: .date)
                    DatePicker("To", selection: $end, in: start..., displayedComponents: .date)
                } else {
                    DatePicker("Date", selection: $start, displayedComponents: .date)
                }

                LabeledContent("Filter") {
                    Text(token)
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add Filter") {
                    onApply(token)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding([.horizontal, .bottom], 20)
        }
        .frame(width: 400)
    }

    private var token: String {
        let key = SearchSuggestion.dateKey(field == .created ? .created : .modified)
        switch mode {
        case .on: return "\(key)\(Self.format(start))"
        case .between: return "\(key)>=\(Self.format(start)) \(key)<=\(Self.format(end))"
        case .onOrAfter: return "\(key)>=\(Self.format(start))"
        case .onOrBefore: return "\(key)<=\(Self.format(start))"
        }
    }

    private static func format(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

#Preview {
    DateFilterView { _ in }
}
