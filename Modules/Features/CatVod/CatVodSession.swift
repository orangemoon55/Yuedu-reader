// CatVodSession.swift
// Per-site browsing model: loads home, categories, searches, detail, and playback.
import Foundation
import Combine
import SwiftUI

@MainActor
final class CatVodSession: ObservableObject {
    let sourceID: String
    let site: CatVodSite

    @Published private(set) var categories: [CatVodCategory] = []
    @Published private(set) var filters: [CatVodFilter] = []
    @Published private(set) var selectedCategoryID: String = ""
    @Published private(set) var selectedFilters: [String: String] = [:]
    @Published private(set) var videos: [CatVodVideo] = []
    @Published private(set) var page = 1
    @Published private(set) var hasMore = false
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    // Search state
    @Published var searchQuery = ""
    @Published private(set) var searchResults: [CatVodVideo] = []
    @Published private(set) var searchPage = 1
    @Published private(set) var searchHasMore = false

    // Detail state
    @Published private(set) var detail: CatVodVideo?
    @Published private(set) var isLoadingDetail = false

    // Playback
    @Published private(set) var playback: CatVodPlayback?

    private var task: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?
    private var detailTask: Task<Void, Never>?

    init(sourceID: String, site: CatVodSite) {
        self.sourceID = sourceID
        self.site = site
    }

    deinit {
        task?.cancel()
        searchTask?.cancel()
        detailTask?.cancel()
    }

    // MARK: - Home / Category

    func loadHome() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let data = try await CatVodRuntime.shared.invoke(site, action: "home", arguments: ["filter": true])
            let home = try CatVodContentParser.home(data)
            categories = home.categories
            filters = home.filters
            videos = home.videos
            page = 1
            hasMore = !home.videos.isEmpty
            if categories.isEmpty {
                selectedCategoryID = ""
            } else if selectedCategoryID.isEmpty {
                selectedCategoryID = categories[0].id
            }
        } catch {
            errorMessage = error.localizedDescription
            videos = []
            hasMore = false
        }
    }

    func loadCategory(_ categoryID: String, reset: Bool = true) async {
        guard !isLoading else { return }
        if reset { page = 1 }
        selectedCategoryID = categoryID
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            var args: [String: Any] = ["tid": categoryID, "pg": page]
            if !selectedFilters.isEmpty {
                args["filter"] = true
                args["ext"] = selectedFilters
            }
            let data = try await CatVodRuntime.shared.invoke(site, action: "category", arguments: args)
            let pg = try CatVodContentParser.page(data, requestedPage: page)
            if page == 1 {
                videos = pg.videos
            } else {
                videos.append(contentsOf: pg.videos)
            }
            page = pg.page
            hasMore = pg.hasMore
        } catch {
            errorMessage = error.localizedDescription
            if page == 1 { videos = [] }
            hasMore = false
        }
    }

    func loadMore() async {
        guard hasMore, !isLoading else { return }
        page += 1
        await loadCategory(selectedCategoryID, reset: false)
    }

    // MARK: - Search

    func search(_ query: String, reset: Bool = true) async {
        searchQuery = query
        guard !searchQuery.isEmpty else {
            searchResults = []
            searchHasMore = false
            return
        }
        guard searchTask == nil else { return }
        if reset { searchPage = 1 }
        searchTask = Task { @MainActor in
            errorMessage = nil
            do {
                var args: [String: Any] = ["wd": query, "pg": searchPage]
                if site.filterable {
                    args["filter"] = true
                }
                let data = try await CatVodRuntime.shared.invoke(site, action: "search", arguments: args)
                let pg = try CatVodContentParser.page(data, requestedPage: searchPage)
                if searchPage == 1 {
                    searchResults = pg.videos
                } else {
                    searchResults.append(contentsOf: pg.videos)
                }
                searchPage = pg.page
                searchHasMore = pg.hasMore
            } catch {
                errorMessage = error.localizedDescription
                if searchPage == 1 { searchResults = [] }
                searchHasMore = false
            }
            searchTask = nil
        }
    }

    func searchMore() async {
        guard searchHasMore, searchTask == nil else { return }
        searchPage += 1
        await search(searchQuery, reset: false)
    }

    // MARK: - Detail

    func loadDetail(videoID: String) async {
        detailTask?.cancel()
        isLoadingDetail = true
        errorMessage = nil
        detailTask = Task { @MainActor in
            do {
                let data = try await CatVodRuntime.shared.invoke(site, action: "detail", arguments: ["ids": videoID])
                let video = try CatVodContentParser.detail(data)
                detail = video
            } catch {
                errorMessage = error.localizedDescription
                detail = nil
            }
            isLoadingDetail = false
            detailTask = nil
        }
    }

    // MARK: - Playback

    func loadPlayback(routeID: String, episodeID: String) async {
        do {
            let data = try await CatVodRuntime.shared.invoke(site, action: "play",
                arguments: ["flag": routeID, "id": episodeID])
            let pb = try CatVodContentParser.playback(data)
            playback = pb
        } catch {
            errorMessage = error.localizedDescription
            playback = nil
        }
    }
}