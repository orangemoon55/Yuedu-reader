#if os(iOS) || CODA_STREAMING_TESTS
//
//  Created by Dimitrios Chatzieleftheriou on 26/05/2020.
//  Copyright © 2020 Decimal. All rights reserved.
//

import Foundation

final class NetworkSessionDelegate: NSObject, URLSessionDataDelegate {
    weak var taskProvider: StreamTaskProvider?
    var httpDataSink: ((HTTPAudioDataChunk) -> Void)?
    private var cacheRanges: [Int: HTTPAudioDataRange] = [:]

    func stream(for task: URLSessionTask) -> NetworkDataStream? {
        // 切歌时 NetworkingClient 会先释放，而 finishTasksAndInvalidate 让在途任务继续回调；
        // 此时 taskProvider 已为 nil 属正常情况，直接忽略该回调，不能断言崩溃。
        taskProvider?.dataStream(for: task)
    }

    func urlSession(_: URLSession,
                    dataTask: URLSessionDataTask,
                    didReceive data: Data)
    {
        if var range = cacheRanges[dataTask.taskIdentifier] {
            if let chunk = range.consume(data) { httpDataSink?(chunk) }
            cacheRanges[dataTask.taskIdentifier] = range
        }
        guard let stream = stream(for: dataTask) else { return }
        stream.didReceive(data: data,
                          response: dataTask.response as? HTTPURLResponse)
    }

    func urlSession(_: URLSession,
                    task: URLSessionTask,
                    didCompleteWithError error: Error?)
    {
        cacheRanges[task.taskIdentifier] = nil
        guard let stream = stream(for: task) else {
            return
        }
        stream.didComplete(with: error, response: task.response as? HTTPURLResponse)
    }

    func urlSession(_: URLSession,
                    dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void)
    {
        if httpDataSink != nil, let http = response as? HTTPURLResponse {
            cacheRanges[dataTask.taskIdentifier] = HTTPAudioDataRange(response: http)
        }
        guard let stream = stream(for: dataTask) else {
            completionHandler(.allow)
            return
        }
        stream.didReceive(response: response as? HTTPURLResponse)
        completionHandler(.allow)
    }
}
#endif
