import Foundation

struct ByteRangePlanner {
    struct ScheduledRange: Equatable {
        let id: UUID
        let range: Range<Int64>
    }

    private var cachedRanges: [Range<Int64>] = []
    private var inFlightRanges: [UUID: Range<Int64>] = [:]

    mutating func scheduleMissingRanges(in requestedRange: Range<Int64>) -> [ScheduledRange] {
        let coveredRanges = mergedRanges(cachedRanges + Array(inFlightRanges.values))
        let missingRanges = subtract(coveredRanges, from: requestedRange)
        let scheduledRanges = missingRanges.map { ScheduledRange(id: UUID(), range: $0) }
        for scheduledRange in scheduledRanges {
            inFlightRanges[scheduledRange.id] = scheduledRange.range
        }
        return scheduledRanges
    }

    mutating func recordCached(_ range: Range<Int64>) {
        cachedRanges = mergedRanges(cachedRanges + [range])
    }

    mutating func finish(_ scheduledRangeID: UUID) {
        inFlightRanges.removeValue(forKey: scheduledRangeID)
    }

    func cachedRange(containing offset: Int64) -> Range<Int64>? {
        cachedRanges.first { $0.lowerBound <= offset && offset < $0.upperBound }
    }

    func isComplete(contentLength: Int64) -> Bool {
        cachedRanges.count == 1
            && cachedRanges[0].lowerBound == 0
            && cachedRanges[0].upperBound == contentLength
    }

    private func subtract(_ coveredRanges: [Range<Int64>], from requestedRange: Range<Int64>) -> [Range<Int64>] {
        var missingRanges: [Range<Int64>] = []
        var nextOffset = requestedRange.lowerBound

        for coveredRange in coveredRanges where nextOffset < requestedRange.upperBound {
            guard coveredRange.upperBound > nextOffset else { continue }
            if coveredRange.lowerBound > nextOffset {
                missingRanges.append(nextOffset..<min(coveredRange.lowerBound, requestedRange.upperBound))
            }
            nextOffset = max(nextOffset, coveredRange.upperBound)
        }

        if nextOffset < requestedRange.upperBound {
            missingRanges.append(nextOffset..<requestedRange.upperBound)
        }
        return missingRanges
    }

    private func mergedRanges(_ ranges: [Range<Int64>]) -> [Range<Int64>] {
        var mergedRanges: [Range<Int64>] = []
        for range in ranges.sorted(by: { $0.lowerBound < $1.lowerBound }) where !range.isEmpty {
            guard let lastRange = mergedRanges.last else {
                mergedRanges.append(range)
                continue
            }
            if range.lowerBound <= lastRange.upperBound {
                mergedRanges[mergedRanges.count - 1] = lastRange.lowerBound..<max(lastRange.upperBound, range.upperBound)
            } else {
                mergedRanges.append(range)
            }
        }
        return mergedRanges
    }
}

