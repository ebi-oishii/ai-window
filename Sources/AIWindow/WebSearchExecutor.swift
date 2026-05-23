import Foundation

/// Lightweight DuckDuckGo HTML search. No API key, no provider account.
/// Best-effort parser — DDG can rearrange its markup at any time, so failures
/// degrade to "(no results)" rather than throwing.
struct WebSearchExecutor {
    private static let endpoint = "https://html.duckduckgo.com/html/"
    /// Brand DDG's bot guard kicks in for empty/curl-like UAs.
    private static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 13_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Safari/605.1.15"

    struct Result {
        let title: String
        let url: String
        let snippet: String
    }

    func search(query: String, limit: Int = 5) async -> [Result] {
        guard var components = URLComponents(string: Self.endpoint) else { return [] }
        components.queryItems = [URLQueryItem(name: "q", value: query)]
        guard let url = components.url else { return [] }

        var req = URLRequest(url: url)
        req.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("en-US,en;q=0.9,ja;q=0.8", forHTTPHeaderField: "Accept-Language")

        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            let html = String(data: data, encoding: .utf8) ?? ""
            return parse(html: html, limit: limit)
        } catch {
            return []
        }
    }

    func format(_ results: [Result], query: String) -> String {
        if results.isEmpty { return "「\(query)」の検索結果が取得できませんでした" }
        return results.enumerated().map { idx, r in
            "\(idx + 1). \(r.title)\n   \(r.url)\n   \(r.snippet)"
        }.joined(separator: "\n\n")
    }

    /// DDG HTML lite layout uses anchors with class "result__a" for titles
    /// and sibling anchors with class "result__snippet" for the description.
    /// Regex-based extraction tolerates attribute-order variation.
    private func parse(html: String, limit: Int) -> [Result] {
        // Capture: ($1) attrs of result__a anchor, ($2) inner HTML
        let anchorPattern = #"<a([^>]*class="result__a"[^>]*)>([\s\S]*?)</a>"#
        let snippetPattern = #"<a[^>]*class="result__snippet"[^>]*>([\s\S]*?)</a>"#
        let hrefPattern = #"href="([^"]+)""#

        guard let anchorRx = try? NSRegularExpression(pattern: anchorPattern),
              let snippetRx = try? NSRegularExpression(pattern: snippetPattern),
              let hrefRx = try? NSRegularExpression(pattern: hrefPattern) else { return [] }

        let ns = html as NSString
        let fullRange = NSRange(location: 0, length: ns.length)
        let anchorMatches = anchorRx.matches(in: html, range: fullRange)
        let snippetMatches = snippetRx.matches(in: html, range: fullRange)

        var results: [Result] = []
        for (i, m) in anchorMatches.prefix(limit).enumerated() {
            guard m.numberOfRanges >= 3 else { continue }
            let attrs = ns.substring(with: m.range(at: 1))
            let inner = ns.substring(with: m.range(at: 2))

            let attrsNS = attrs as NSString
            guard let hrefMatch = hrefRx.firstMatch(in: attrs, range: NSRange(location: 0, length: attrsNS.length)),
                  hrefMatch.numberOfRanges >= 2 else { continue }
            let href = attrsNS.substring(with: hrefMatch.range(at: 1))
            let cleanURL = decodeDDGRedirect(href)
            let title = stripTags(inner)
            guard !title.isEmpty, !cleanURL.isEmpty else { continue }

            let snippet: String
            if i < snippetMatches.count, snippetMatches[i].numberOfRanges >= 2 {
                snippet = stripTags(ns.substring(with: snippetMatches[i].range(at: 1)))
            } else {
                snippet = ""
            }

            results.append(Result(title: title, url: cleanURL, snippet: snippet))
        }
        return results
    }

    /// DDG wraps external URLs in /l/?uddg=<encoded>. Decode them back.
    private func decodeDDGRedirect(_ raw: String) -> String {
        let unescaped = raw.replacingOccurrences(of: "&amp;", with: "&")
        if unescaped.contains("uddg="),
           let comps = URLComponents(string: unescaped.hasPrefix("//") ? "https:" + unescaped : unescaped),
           let target = comps.queryItems?.first(where: { $0.name == "uddg" })?.value {
            return target
        }
        return unescaped
    }

    private func stripTags(_ s: String) -> String {
        var text = s
        while let open = text.range(of: "<"), let close = text.range(of: ">", range: open.upperBound..<text.endIndex) {
            text.removeSubrange(open.lowerBound..<close.upperBound)
        }
        return text
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;",  with: "<")
            .replacingOccurrences(of: "&gt;",  with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
