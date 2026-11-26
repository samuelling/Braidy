import SwiftUI

/// Step 1: which console or device.
struct PlatformPickerView: View {
    @ObservedObject var reader: Reader
    @Environment(\.dismiss) private var dismiss
    @State private var startingGame = ""

    var body: some View {
        List {
            if !reader.game.isEmpty {
                Section("Playing now") {
                    HStack {
                        Label(reader.game, systemImage: "checkmark.seal.fill")
                            .labelStyle(TrailingIconLabelStyle())
                        Spacer()
                    }
                }
            }
            Section("What is it played on?") {
                ForEach(Reader.platforms, id: \.name) { p in
                    NavigationLink {
                        GameSearchView(reader: reader, platform: p.name, short: p.short)
                    } label: {
                        Label(p.name, systemImage: p.icon)
                    }
                }
            }
            let recent = reader.recentGames.filter { $0 != reader.game }
            if !recent.isEmpty {
                Section("Recent") {
                    ForEach(recent, id: \.self) { g in
                        Button(g) { reader.choose(game: g) }
                    }
                }
            }
        }
        .arcadeForm()
        .navigationTitle("Choose a game")
        .onAppear { startingGame = reader.game }
        // Once a game is picked (here or in a search below), pop back to Settings.
        .onChange(of: reader.game) { _, newValue in
            if newValue != startingGame { dismiss() }
        }
    }
}

/// Step 2: search games on that platform; Claude matches what's typed and shows what's popular.
struct GameSearchView: View {
    @ObservedObject var reader: Reader
    let platform: String
    let short: String

    @State private var query = ""
    @State private var results: [ClaudeClient.GameMatch] = []
    @State private var popular: [ClaudeClient.GameMatch] = []
    @State private var searching = false
    @State private var loadingPopular = false
    @State private var note: String?

    private var trimmed: String { query.trimmingCharacters(in: .whitespaces) }
    private var platformLabel: String { short.isEmpty ? "" : platform }

    var body: some View {
        List {
            if !trimmed.isEmpty {
                Section {
                    if reader.hasKey {
                        Button { search() } label: {
                            HStack {
                                Label("Find \u{201C}\(trimmed)\u{201D} with Claude", systemImage: "sparkles")
                                if searching { Spacer(); ProgressView() }
                            }
                        }
                        .disabled(searching)
                    }
                    Button { choose(title: trimmed, detail: platformLabel) } label: {
                        Label("Use \u{201C}\(trimmed)\u{201D} as typed", systemImage: "checkmark.circle")
                    }
                }
            }
            if let best = results.first {
                Section {
                    Button { choose(best) } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 34))
                                .foregroundStyle(.green)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(best.title).font(.headline).foregroundStyle(.primary)
                                if !best.detail.isEmpty {
                                    Text(best.detail).font(.subheadline).foregroundStyle(.secondary)
                                }
                                Text("Tap to use this game").font(.caption.weight(.semibold)).foregroundStyle(.green)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                } header: {
                    Text("Best match")
                }
                if results.count > 1 {
                    Section("Or did you mean") {
                        ForEach(results.dropFirst(), id: \.self) { m in gameRow(m) }
                    }
                }
            }
            if let note {
                Section { Text(note).foregroundStyle(.secondary) }
            }
            if trimmed.isEmpty {
                Section {
                    if loadingPopular {
                        HStack { ProgressView(); Text("Asking Claude what's popular…").foregroundStyle(.secondary) }
                    }
                    ForEach(popular, id: \.self) { m in gameRow(m) }
                    if popular.isEmpty && !loadingPopular {
                        ForEach(Reader.suggestedGames, id: \.self) { g in
                            Button(g) { choose(title: g, detail: platformLabel) }
                        }
                    }
                } header: {
                    Text(short.isEmpty ? "Popular" : "Popular on \(short)")
                } footer: {
                    Text(reader.hasKey ? "Type any game above and press return to search."
                                       : "Type any game above. Add a Claude key in Settings to search and see what's new.")
                }
            }
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: short.isEmpty ? "Type any game" : "Search \(short) games")
        .onSubmit(of: .search) { if reader.hasKey { search() } }
        .onChange(of: query) { _, _ in results = []; note = nil }
        .arcadeForm()
        .navigationTitle(platform)
        .task { await loadPopular() }
    }

    private func gameRow(_ m: ClaudeClient.GameMatch) -> some View {
        Button { choose(m) } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(m.title).foregroundStyle(.primary)
                if !m.detail.isEmpty { Text(m.detail).font(.caption).foregroundStyle(.secondary) }
            }
        }
    }

    private func choose(_ m: ClaudeClient.GameMatch) {
        choose(title: m.title, detail: m.detail.isEmpty ? platformLabel : m.detail)
    }

    /// Keep same-named versions apart, e.g. "The Legend of Zelda: Ocarina of Time (Switch 2)".
    private func choose(title: String, detail: String) {
        let name = short.isEmpty || title.localizedCaseInsensitiveContains(short) ? title : "\(title) (\(short))"
        reader.choose(game: name, detail: detail)
    }

    private func search() {
        let q = trimmed
        guard !q.isEmpty, !searching else { return }
        searching = true
        note = nil
        Task { @MainActor in
            do {
                results = try await reader.searchGames(q, platform: short.isEmpty ? "" : platform)
                if results.isEmpty { note = "Claude didn't find a matching game. You can still use what you typed." }
            } catch {
                note = error.localizedDescription
            }
            searching = false
        }
    }

    @MainActor
    private func loadPopular() async {
        guard reader.hasKey, !short.isEmpty, popular.isEmpty else { return }
        loadingPopular = true
        popular = (try? await reader.popularGames(platform: platform)) ?? []
        loadingPopular = false
    }
}
