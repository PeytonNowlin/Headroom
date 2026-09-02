import Foundation

/// RFC 4180-ish reader: quoted fields with embedded commas, newlines, and `""` escapes. The first
/// row is the header; records are delivered keyed by it. Rows whose width differs from the header
/// are counted and skipped; a structural failure (stray quote) aborts.
enum CSV {
    struct Summary: Equatable {
        var isWellFormed: Bool
        var rejectedRecords: Int
    }

    @discardableResult
    static func forEachRecord(in text: String, header onHeader: (([String]) -> Void)? = nil,
                              _ body: ([String: String]) -> Void) -> Summary {
        var header: [String]?
        var rejected = 0
        let wellFormed = forEachRow(in: text) { row in
            guard let keys = header else {
                let normalized = row.map { $0.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{FEFF}"))) }
                header = normalized
                onHeader?(normalized)
                return
            }
            guard row.count == keys.count else { rejected += 1; return }
            body(Dictionary(zip(keys, row)) { first, _ in first })
        }
        return Summary(isWellFormed: wellFormed, rejectedRecords: rejected)
    }

    private static func forEachRow(in text: String, _ body: ([String]) -> Void) -> Bool {
        enum State { case start, unquoted, quoted, quoteClosed }
        var field = ""
        var row: [String] = []
        var state = State.start

        func endField() { row.append(field); field = "" }
        func endRow() {
            endField()
            if !row.allSatisfy(\.isEmpty) { body(row) }
            row = []
        }

        var i = text.startIndex
        while i < text.endIndex {
            let c = text[i]
            if state == .quoted {
                if c == "\"" {
                    let next = text.index(after: i)
                    if next < text.endIndex, text[next] == "\"" {
                        field.append("\"")
                        i = text.index(after: next)
                        continue
                    }
                    state = .quoteClosed
                } else {
                    field.append(c)
                }
                i = text.index(after: i)
                continue
            }
            switch (state, c) {
            case (.start, "\""): state = .quoted
            case (_, ","): endField(); state = .start
            case (_, "\r"), (_, "\n"), (_, "\r\n"): endRow(); state = .start
            case (.unquoted, "\""), (.quoteClosed, _): return false
            case (.start, _): field.append(c); state = .unquoted
            case (.unquoted, _): field.append(c)
            case (.quoted, _): break
            }
            i = text.index(after: i)
        }
        guard state != .quoted else { return false }
        if !field.isEmpty || !row.isEmpty || state == .quoteClosed { endRow() }
        return true
    }
}
