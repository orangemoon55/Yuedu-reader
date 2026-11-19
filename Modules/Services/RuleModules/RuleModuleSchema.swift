import Foundation

/// Codable deliberately ignores extra keys. A rule module cannot: ignoring a new request,
/// mapping or capability may silently run a different module. Check structural keys before
/// decoding; maps such as headers/localizations keep their documented dynamic keys.
enum RuleModuleSchema {
    private enum Shape {
        case module, entry, request, list, detail, parameter, option, belongTo, placeholder
        case reading, toc, content, attribution, localization, entryText, paramText
        case comments, chapters, chapterList, commentPage, counts, countList, hot, hotList, authorSay
        case reviews, reviewList, rating, related, storeSection, storeShelf
    }

    static func validate(_ data: Data) throws(RuleModuleRejection) {
        let value: Any
        do { value = try JSONSerialization.jsonObject(with: data) }
        catch { throw .notJSON }
        try check(value, shape: .module, path: "")
    }

    private static func keys(_ shape: Shape) -> Set<String> {
        let words: String
        switch shape {
        case .module: words = "id title description author site version requiredVersion hosts rateLimit modules search lookup reading reviews icon globalParams detail related genre javascript comments attribution localizations"
        case .entry: words = "id title description cacheDuration params request list contentKind excludeTags isbnPrefixes detail minKeywordLength searchesAuthors store"
        case .request: words = "url method body headers charset bodyEncoding script"
        case .list: words = "items title author cover intro url kind language aliases tags publisher isbn series seriesCovers contentKind id volumes"
        case .detail: words = "request intro tags cacheDuration"
        case .parameter: words = "name title type description value enumOptions followsLanguage belongTo placeholders"
        case .option: words = "title value language"
        case .belongTo: words = "paramName value"
        case .placeholder: words = "title value"
        case .reading: words = "headers charset toc content"
        case .toc: words = "items title url nextPage singleChapter"
        case .content: words = "text title nextPage"
        case .attribution: words = "text url"
        case .localization: words = "title description entries"
        case .entryText: words = "title description params"
        case .paramText: words = "title description options"
        case .comments: words = "cacheDuration chapters chapter counts paragraph hot authorSay"
        case .chapters: words = "request cacheDuration list"
        case .chapterList: words = "items id title"
        case .commentPage: words = "request cacheDuration sorts list total"
        case .counts: words = "request cacheDuration list paragraphCount"
        case .countList: words = "items count quote index id"
        case .hot: words = "request cacheDuration list paragraphCount"
        case .hotList: words = "items text author likes date quote index id"
        case .authorSay: words = "request cacheDuration text author"
        case .reviews: words = "request cacheDuration list ratingScale rating"
        case .reviewList: words = "items text title author date rating likes"
        case .rating: words = "score count distribution"
        case .related: words = "request cacheDuration list"
        case .storeSection: words = "layout params shelves"
        case .storeShelf: words = "list params belongTo"
        }
        return Set(words.split(separator: " ").map(String.init))
    }

    private static func check(_ value: Any, shape: Shape, path: String) throws(RuleModuleRejection) {
        guard let object = value as? [String: Any] else { return } // Codable reports wrong types/missing fields.
        func field(_ key: String) -> String { path.isEmpty ? key : "\(path).\(key)" }
        for key in object.keys.sorted() where !keys(shape).contains(key) {
            throw .unsupportedField(field(key))
        }
        func child(_ key: String, _ nested: Shape) throws(RuleModuleRejection) {
            if let value = object[key] { try check(value, shape: nested, path: field(key)) }
        }
        func array(_ key: String, _ nested: Shape) throws(RuleModuleRejection) {
            guard let values = object[key] as? [Any] else { return }
            for (index, value) in values.enumerated() { try check(value, shape: nested, path: "\(field(key))[\(index)]") }
        }
        func map(_ key: String, _ nested: Shape) throws(RuleModuleRejection) {
            guard let values = object[key] as? [String: Any] else { return }
            for name in values.keys.sorted() { try check(values[name]!, shape: nested, path: "\(field(key)).\(name)") }
        }
        switch shape {
        case .module:
            try array("modules", .entry)
            for key in ["search", "lookup", "genre"] { try child(key, .entry) }
            try child("reading", .reading); try child("reviews", .reviews)
            try array("globalParams", .parameter); try child("detail", .detail)
            try child("related", .related); try child("comments", .comments)
            try child("attribution", .attribution); try map("localizations", .localization)
        case .entry:
            try array("params", .parameter); try child("request", .request); try child("list", .list)
            try child("detail", .detail); try array("store", .storeSection)
        case .parameter:
            try array("enumOptions", .option); try child("belongTo", .belongTo); try array("placeholders", .placeholder)
        case .storeSection: try array("shelves", .storeShelf)
        case .storeShelf: try child("belongTo", .belongTo)
        case .reading: try child("toc", .toc); try child("content", .content)
        case .localization: try map("entries", .entryText)
        case .entryText: try map("params", .paramText)
        case .comments:
            try child("chapters", .chapters); try child("chapter", .commentPage); try child("paragraph", .commentPage)
            try child("counts", .counts); try child("hot", .hot); try child("authorSay", .authorSay)
        case .chapters: try child("request", .request); try child("list", .chapterList)
        case .commentPage:
            try child("request", .request); try child("list", .reviewList); try array("sorts", .option)
        case .counts: try child("request", .request); try child("list", .countList)
        case .hot: try child("request", .request); try child("list", .hotList)
        case .reviews:
            try child("request", .request); try child("list", .reviewList); try child("rating", .rating)
        case .related: try child("request", .request); try child("list", .list)
        case .detail, .authorSay: try child("request", .request)
        default: break
        }
    }
}
