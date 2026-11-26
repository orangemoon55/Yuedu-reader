// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 jo32 and Yingxia contributors.
// Adapted from Yingxia, Sources/TVCore/PlaybackResolution.swift:3-33,
// commit a6bcc00bbbdbd7c6af7b7223ca2fa6018d6d685c.
// Upstream license/copyright: README.md:114-120 and LICENSE at that commit.
// Changes: renamed the value type, added Hashable, and replaced JSONValue accessors
// with Foundation JSONSerialization values. Ordering and pair parsing are upstream's.
// URL safety, headers and business errors belong to CatVodContentParser, not this adapter.

import Foundation
import CoreFoundation

struct YingxiaPlaybackChoice: Identifiable, Sendable, Hashable {
    let id: Int
    let name: String
    let address: String

    static func parse(_ value: Any?, prefix: String = "", fallbackName: String) -> [YingxiaPlaybackChoice] {
        if let text = scalarString(value), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return [YingxiaPlaybackChoice(id: 0, name: fallbackName, address: prefix + text)]
        }
        if let object = value as? [String: Any], let values = object["values"] as? [Any] {
            // FongMi's Url: {"values": [{"n": name, "v": address}], "position": the one it plays}; the others are
            // the same episode in other qualities. FongMi's new-SDK spiders answer this (#500).
            let position = scalarString(object["position"]).flatMap(Int.init) ?? 0
            let order = values.indices.contains(position) ? [position] + values.indices.filter { $0 != position } : Array(values.indices)
            var choices: [YingxiaPlaybackChoice] = []
            for index in order {
                guard let entry = values[index] as? [String: Any], let address = scalarString(entry["v"]),
                      !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                let name = scalarString(entry["n"]) ?? ""
                choices.append(YingxiaPlaybackChoice(id: choices.count, name: name.isEmpty ? fallbackName : name, address: prefix + address))
            }
            return choices
        }
        guard let values = value as? [Any] else { return [] }
        var choices: [YingxiaPlaybackChoice] = []
        for index in stride(from: 0, to: values.count - values.count % 2, by: 2) {
            guard let name = scalarString(values[index]), let address = scalarString(values[index + 1]),
                  !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            choices.append(YingxiaPlaybackChoice(id: index / 2, name: name.isEmpty ? fallbackName : name, address: prefix + address))
        }
        return choices
    }

    // Mirrors JSONValue.string / .int (Models.swift:106-113): strings and numbers,
    // but not booleans, containers or null. CFBoolean is also an NSNumber in Foundation.
    private static func scalarString(_ value: Any?) -> String? {
        if let text = value as? String { return text }
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let value = number.doubleValue
        return value.rounded() == value ? String(format: "%.0f", value) : String(value)
    }
}
