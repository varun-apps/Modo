import SwiftUI

/// Window content showing the last N rewrites with copy and clear actions.
struct HistoryView: View {
    @ObservedObject private var store = HistoryStore.shared
    @State private var selectedEntry: HistoryEntry?
    @State private var searchText: String = ""

    private var filteredEntries: [HistoryEntry] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return store.entries }
        return store.entries.filter { entry in
            entry.modeTitle.lowercased().contains(query)
                || entry.originalText.lowercased().contains(query)
                || entry.resultText.lowercased().contains(query)
        }
    }

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        HSplitView {
            list
                .frame(minWidth: 240, idealWidth: 280)
            detail
                .frame(minWidth: 320)
        }
        .frame(minWidth: 640, minHeight: 420)
    }

    private var list: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(filteredEntries.count) of \(store.entries.count)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Clear All") { store.clear() }
                    .disabled(store.entries.isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Divider()

            if store.entries.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No history yet")
                        .font(.callout)
                    Text("Recent rewrites will appear here.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else if filteredEntries.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("No matches")
                        .font(.callout)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                List(selection: $selectedEntry) {
                    ForEach(filteredEntries) { entry in
                        row(entry).tag(entry)
                    }
                }
                .listStyle(.sidebar)
            }
        }
    }

    private func row(_ entry: HistoryEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: entry.modeSymbol)
                Text(entry.modeTitle).font(.callout.weight(.medium))
                Spacer()
                Text(dateFormatter.string(from: entry.date))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(entry.originalText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var detail: some View {
        if let entry = selectedEntry ?? filteredEntries.first {
            entryDetail(entry)
        } else {
            Text(store.entries.isEmpty ? "No history yet" : "Select an item to view it")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func entryDetail(_ entry: HistoryEntry) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: entry.modeSymbol)
                Text(entry.modeTitle).font(.headline)
                Spacer()
                Text(dateFormatter.string(from: entry.date))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(role: .destructive) {
                    let next = store.entries.first { $0.id != entry.id }
                    store.delete(entry)
                    selectedEntry = next
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }

            Text("Original")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ScrollView {
                Text(entry.originalText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 120)
            .padding(8)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(nsColor: .separatorColor))
            )

            Text("Result")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ScrollView {
                Text(entry.resultText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .padding(8)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(nsColor: .separatorColor))
            )

            HStack {
                Button {
                    copy(entry.resultText)
                } label: {
                    Label("Copy Result", systemImage: "doc.on.doc")
                }
                Button {
                    copy(entry.originalText)
                } label: {
                    Label("Copy Original", systemImage: "doc.on.doc")
                }
                Spacer()
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
