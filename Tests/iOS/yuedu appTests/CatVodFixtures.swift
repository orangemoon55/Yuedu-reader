import Foundation

/// JSON inputs shared by Swift Testing and the standalone macOS swiftc runner.
enum CatVodFixtures {
    static let categories = #"{"class":[{"type_id":1,"type_name":"电影"}],"filters":{"1":[{"key":"year","name":"年份","init":"2024","value":[{"n":"全部","v":""},{"n":"2024","v":"2024"}]}]},"list":[]}"#
    static let stringified = #"{"list":[{"vod_id":"a","vod_name":"片名"}]}"#
    static let wrappedStringified = #"{"data":"{\"list\":[]}"}"#
    static let empty = #"{"code":0,"list":[],"pagecount":20}"#
    static let explicitError = #"{"error":"源不可用","list":[]}"#
    static let nonzeroCode = #"{"code":503,"msg":"失败","list":[]}"#
    static let invalidJSON = "<html>bad</html>"
    static let groupedEpisodes = #"{"list":[{"vod_id":"v","vod_name":"片","vod_play_from":"a$$$b","vod_play_url":"第一集$https://e.test/a$x,y#第二集$opaque$$$正片$https://e.test/b"}]}"#
    static let dictionaryHeaders = #"{"url":"https://e.test/a.m3u8","headers":{"Referer":"https://e.test/"}}"#
    static let stringHeaders = #"{"url":"https://e.test/a","header":"{\"User-Agent\":\"Readcc\"}"}"#
    static let parseOne = #"{"url":"https://e.test/watch?id=1","parse":"1"}"#
    static let booleanJX = #"{"url":"https://e.test/a","jx":true,"parse":0}"#
    static let qualityURLs = #"{"url":["坏","ftp://e.test/a","高清","https://e.test/hd","标清","https://e.test/sd"],"header":{"X-Test":"yes"}}"#
    static let missingURL = #"{"parse":0}"#
    static let relativeURL = #"{"url":"/proxy/video.m3u8"}"#
    static let pageTwo = #"{"page":"2","pagecount":"3","list":[{"vod_id":2,"vod_name":"第二页影片"}]}"#
    static let unknownPagination = #"{"list":[{"vod_id":1,"vod_name":"未知分页影片"}]}"#
    static let totalHasMore = #"{"total":25,"limit":10,"list":[{"vod_id":1,"vod_name":"总数分页影片"}]}"#
    static let nextNumber = #"{"next":3,"list":[{"vod_id":1,"vod_name":"下一页影片"}]}"#
    static let hiddenOuterError = #"{"code":500,"data":{"list":[]}}"#
}
