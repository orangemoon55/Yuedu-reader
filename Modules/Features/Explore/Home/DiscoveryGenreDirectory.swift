import Foundation
import SwiftUI

/// Local-only directory. The owner supplies already-resolved source categories and
/// owns the paginated book-list destination; this view never loads/scans sources.
struct DiscoveryGenreDirectory: View {
    let categories: [DiscoveryCategoryChoice]
    let open: (DiscoveryCategoryChoice) -> Void
    @State private var query = ""

    var body: some View {
        let index = DiscoveryGenreIndex(categories: categories)
        let genres = DiscoveryGenre.all.filter { $0.contains(query: query) }
        List {
            Section {
                ForEach(genres) { genre in
                    let matches = index.matches(for: genre)
                    NavigationLink {
                        DiscoveryGenreChoices(genre: genre, categories: matches, open: open)
                    } label: {
                        HStack(spacing: 16) {
                            Image(systemName: genre.systemImage)
                                .font(DSFont.title2)
                                .foregroundStyle(Color.blue)
                                .frame(width: 28)
                                .accessibilityHidden(true)
                            Text(DiscoveryGenreText.string(genre.title))
                                .font(DSFont.body)
                                .foregroundStyle(DSColor.textPrimary)
                            Spacer(minLength: 8)
                            Text(matches.isEmpty ? DiscoveryGenreText.string("暫無欄目") : "\(matches.count)")
                                .font(DSFont.caption)
                                .foregroundStyle(DSColor.textSecondary)
                        }
                        .padding(.vertical, 4)
                    }
                    .accessibilityIdentifier("discovery.genre.\(genre.id)")
                }
            }
            .interfaceSectionSurface()
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .themedAppSurface(for: .explore)
        .navigationTitle(DiscoveryGenreText.string("所有類型"))
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: DiscoveryGenreText.string("搜尋類型"))
        .overlay {
            if genres.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
        .accessibilityIdentifier("discovery.genreDirectory")
    }
}

private struct DiscoveryGenreChoices: View {
    let genre: DiscoveryGenre
    let categories: [DiscoveryCategoryChoice]
    let open: (DiscoveryCategoryChoice) -> Void
    @State private var query = ""

    private var visible: [DiscoveryCategoryChoice] {
        let needle = DiscoveryGenre.normalized(query)
        guard !needle.isEmpty else { return categories }
        return categories.filter {
            DiscoveryGenre.normalized($0.reference.title).contains(needle)
                || DiscoveryGenre.normalized($0.reference.sourceURL).contains(needle)
        }
    }

    var body: some View {
        List {
            if !categories.isEmpty {
                Section {
                    ForEach(visible, id: \.self) { choice in
                        Button {
                            // Pass the original value, including all source filter values.
                            open(choice)
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    // Never rename a real source category as the directory genre.
                                    Text(choice.reference.title)
                                        .font(DSFont.body)
                                        .foregroundStyle(DSColor.textPrimary)
                                    Text(sourceLabel(for: choice))
                                        .font(DSFont.caption)
                                        .foregroundStyle(DSColor.textSecondary)
                                        .lineLimit(2)
                                    if !choice.filters.isEmpty {
                                        Text(choice.filters.keys.sorted().map {
                                            "\($0): \(choice.filters[$0] ?? "")"
                                        }.joined(separator: " · "))
                                        .font(DSFont.caption)
                                        .foregroundStyle(DSColor.textSecondary)
                                        .lineLimit(2)
                                    }
                                }
                                Spacer(minLength: 8)
                                Image(systemName: "chevron.right")
                                    .font(DSFont.caption.weight(.semibold))
                                    .foregroundStyle(DSColor.textSecondary)
                                    .accessibilityHidden(true)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("discovery.genreChoice.\(choice.id)")
                    }
                } header: {
                    Text(DiscoveryGenreText.string("匹配的來源欄目"))
                } footer: {
                    Text(DiscoveryGenreText.string("保留來源原始分類；點選後開啟該來源書單。"))
                }
                .interfaceSectionSurface()
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .themedAppSurface(for: .explore)
        .navigationTitle(DiscoveryGenreText.string(genre.title))
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: DiscoveryGenreText.string("搜尋來源欄目"))
        .overlay {
            if categories.isEmpty {
                ContentUnavailableView {
                    Label(DiscoveryGenreText.string("暫無匹配欄目"), systemImage: genre.systemImage)
                } description: {
                    Text(DiscoveryGenreText.string("目前提供的來源分類沒有此類型。目錄僅比對已載入的欄目，不會以其他類型代替，也不會自動掃描來源。"))
                }
            } else if visible.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
    }

    private func sourceLabel(for choice: DiscoveryCategoryChoice) -> String {
        URL(string: choice.reference.sourceURL)?.host ?? choice.reference.sourceURL
    }
}

/// Pure matching model, internal so the app's test target can exercise the rules.
/// Aliases describe a genre, not fabricated source categories or request URLs.
struct DiscoveryGenre: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let systemImage: String
    let aliases: [String]
    let exactAliases: [String]
    let exclusions: [String]

    private init(_ id: String, _ title: String, _ systemImage: String,
                 _ aliases: [String], exact: [String] = [], excluding: [String] = []) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.aliases = ([title] + aliases).map(Self.normalized)
        self.exactAliases = exact.map(Self.normalized)
        self.exclusions = excluding.map(Self.normalized)
    }

    static func normalized(_ value: String) -> String {
        let simplified = value.applyingTransform(StringTransform("Traditional-Simplified"), reverse: false) ?? value
        let folded = simplified.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                                         locale: Locale(identifier: "en_US_POSIX"))
        return folded.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }.joined(separator: " ")
    }

    private static func contains(_ text: String, alias: String) -> Bool {
        // English aliases must be whole words/phrases: art != martial, history != historical.
        if alias.unicodeScalars.allSatisfy({ $0.isASCII }) {
            return (" " + text + " ").contains(" " + alias + " ")
        }
        return text.contains(alias)
    }

    func matchScore(for title: String) -> Int? {
        matchScore(normalizedTitle: Self.normalized(title))
    }

    fileprivate func matchScore(normalizedTitle: String) -> Int? {
        guard !normalizedTitle.isEmpty,
              !exclusions.contains(where: { Self.contains(normalizedTitle, alias: $0) }) else { return nil }
        if exactAliases.contains(normalizedTitle) { return 1_000 + normalizedTitle.count }
        return aliases.compactMap { alias -> Int? in
            guard Self.contains(normalizedTitle, alias: alias) else { return nil }
            return (normalizedTitle == alias ? 1_000 : 100) + alias.count
        }.max()
    }

    func contains(query: String) -> Bool {
        let needle = Self.normalized(query)
        return needle.isEmpty || Self.normalized(title).contains(needle)
            || (aliases + exactAliases).contains { $0.contains(needle) }
    }

    // Keep this order: the first fourteen entries mirror the supplied screenshot.
    static let all: [DiscoveryGenre] = [
        .init("fiction", "小說與文學", "text.book.closed.fill",
              ["文学", "名著", "散文", "短篇小说", "literature", "classics"],
              exact: ["小说", "fiction"], excluding: ["非小说", "非虚构", "nonfiction", "non fiction"]),
        .init("romance", "愛情", "heart.fill", ["言情", "恋爱", "浪漫", "耽美", "百合", "romance"]),
        .init("mystery", "推理懸疑", "magnifyingglass", ["推理", "悬疑", "侦探", "探案", "刑侦", "mystery", "detective"]),
        .init("science-fiction", "科幻", "atom", ["科学幻想", "星际", "末世", "sci fi", "scifi", "science fiction"]),
        .init("fantasy", "奇幻", "wand.and.stars", ["玄幻", "魔幻", "魔法", "异世界", "fantasy"]),
        .init("martial-arts", "武俠", "figure.martial.arts", ["仙侠", "修真", "修仙", "武道", "wuxia", "xianxia", "martial arts"]),
        .init("horror", "恐怖驚悚", "moon.stars.fill", ["恐怖", "惊悚", "灵异", "怪谈", "horror", "thriller"]),
        .init("historical-fiction", "歷史小說", "building.columns.fill",
              ["架空历史", "历史架空", "历史军事", "军事历史", "穿越历史", "历史穿越", "historical fiction", "historical novel"]),
        .init("young-adult", "校園青春", "graduationcap.fill", ["校园", "青春", "轻小说", "young adult", "teen fiction"]),
        .init("comics", "漫畫與圖畫小說", "bubble.left.and.bubble.right.fill", ["漫画", "图画小说", "绘本", "comics", "manga", "graphic novel"]),
        .init("children", "兒童", "teddybear.fill", ["少儿", "童话", "童书", "children", "kids", "juvenile"]),
        .init("nonfiction", "非小說", "book.closed.fill", ["非虚构", "纪实", "报告文学", "nonfiction", "non fiction"]),
        .init("biography", "傳記與回憶錄", "person.text.rectangle.fill", ["传记", "自传", "回忆录", "biography", "biographies", "memoir", "memoirs"]),
        .init("history", "歷史", "building.columns.fill", ["世界史", "中国史", "史学", "history"],
              excluding: ["小说", "架空", "穿越", "历史军事", "军事历史", "fiction", "novel", "novels"]),
        .init("business", "商業與個人理財", "chart.xyaxis.line", ["商业", "理财", "经济", "金融", "投资", "管理", "business", "finance", "economics"]),
        .init("computing", "電腦與網際網路", "desktopcomputer", ["计算机", "互联网", "电脑", "编程", "程序设计", "computer", "computers", "programming", "internet"]),
        .init("health", "健康與健身", "heart.text.square.fill", ["健康", "健身", "养生", "医学", "health", "fitness", "medicine"]),
        .init("home", "生活與家居", "house.fill", ["家居", "家庭生活", "园艺", "手工", "home", "gardening", "crafts"]),
        .init("cooking", "烹飪與美食", "fork.knife", ["烹饪", "美食", "食谱", "菜谱", "cooking", "cookbooks", "food"]),
        .init("arts", "藝術與娛樂", "paintpalette.fill", ["艺术", "娱乐", "音乐", "摄影", "绘画", "art", "arts", "music", "photography"], excluding: ["martial arts"]),
        .init("travel", "旅行與探險", "airplane", ["旅行", "旅游", "游记", "探险", "travel"]),
        .init("politics", "政治與時事", "globe", ["政治", "时事", "社会学", "politics", "political", "current affairs", "sociology"]),
        .init("science", "科學與自然", "leaf.fill", ["科学", "自然", "科普", "物理", "化学", "生物", "science", "nature"],
              excluding: ["科幻", "科学幻想", "science fiction", "sci fi", "scifi"]),
        .init("sports", "運動與戶外", "sportscourt.fill", ["运动", "户外", "体育", "竞技", "sports", "outdoors"]),
        .init("religion", "宗教與心靈", "sparkles", ["宗教", "心灵", "佛学", "信仰", "religion", "spirituality"]),
        .init("philosophy", "哲學", "lightbulb.fill", ["哲学", "伦理", "philosophy", "ethics"]),
        .init("self-development", "自我成長", "sun.max.fill", ["自我成长", "励志", "成功学", "心理学", "self help", "personal development", "psychology"]),
        .init("education", "教育與學習", "pencil.and.outline", ["教育", "学习", "教材", "考试", "education", "study", "textbooks"]),
        .init("reference", "參考工具", "books.vertical.fill", ["参考", "工具书", "词典", "字典", "百科", "reference", "dictionary", "dictionaries"]),
        .init("poetry", "詩歌", "quote.opening", ["诗歌", "诗词", "诗集", "poetry", "poems"]),
    ]
}

/// Deduplicate only identical choices, never just a URL/title: different filter
/// combinations can point to different real lists. Exact matches sort first.
struct DiscoveryGenreIndex {
    private let entries: [(choice: DiscoveryCategoryChoice, title: String, order: Int)]

    init(categories: [DiscoveryCategoryChoice]) {
        var seen = Set<DiscoveryCategoryChoice>()
        entries = categories.enumerated().compactMap { order, choice in
            guard seen.insert(choice).inserted else { return nil }
            return (choice, DiscoveryGenre.normalized(choice.reference.title), order)
        }
    }

    func matches(for genre: DiscoveryGenre) -> [DiscoveryCategoryChoice] {
        entries.compactMap { entry -> (choice: DiscoveryCategoryChoice, score: Int, order: Int)? in
            guard let score = genre.matchScore(normalizedTitle: entry.title) else { return nil }
            return (entry.choice, score, entry.order)
        }.sorted {
            $0.score == $1.score ? $0.order < $1.order : $0.score > $1.score
        }.map(\.choice)
    }
}

/// New directory strings stay self-contained: existing translations win; otherwise
/// honor the app bundle's selected Simplified Chinese without editing shared resources.
private enum DiscoveryGenreText {
    static func string(_ key: String) -> String {
        let translated = localized(key)
        guard translated == key,
              Bundle.main.preferredLocalizations.first?.hasPrefix("zh-Hans") == true else { return translated }
        return key.applyingTransform(StringTransform("Traditional-Simplified"), reverse: false) ?? key
    }
}
