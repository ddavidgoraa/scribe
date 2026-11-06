import Foundation
import MdCore
import Observation

/// Full-text library search (⌘⇧F). The Rust index lives off the main thread.
@MainActor
@Observable
final class SearchModel {
    var query = "" {
        didSet { if query != oldValue { scheduleSearch() } }
    }
    private(set) var results: [SearchHit] = []
    private(set) var isSearching = false

    private var index: SearchIndex?
    private var searchTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?

    var isActive: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    func open(root: URL) {
        index = SearchIndex(root: root.path)
        results = []
        refresh()
    }

    /// Reindexes changed notes (library opened, files changed), then repeats the search.
    func refresh() {
        guard let index else { return }
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300)) // coalesce bursts of file events
            guard !Task.isCancelled else { return }
            await Task.detached(priority: .utility) { try? index.refresh() }.value
            guard !Task.isCancelled else { return }
            self?.scheduleSearch(delay: .zero)
        }
    }

    private func scheduleSearch(delay: Duration = .milliseconds(150)) {
        searchTask?.cancel()
        let query = query
        guard let index, isActive else {
            results = []
            isSearching = false
            return
        }
        isSearching = true
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            let hits = await Task.detached(priority: .userInitiated) { index.search(query: query, limit: 100) }.value
            guard !Task.isCancelled else { return }
            self?.results = hits
            self?.isSearching = false
        }
    }
}
