import Foundation

enum EditorTOCParser {
    private struct PendingLine {
        let lineNumber: Int
        let text: String
        let range: NSRange
    }

    static func parse(_ text: String) -> [EditorTOCItem] {
        let nsText = text as NSString
        var items: [EditorTOCItem] = []

        var lineNumber = 0
        var pendingLine: PendingLine?

        var isInFrontmatter = false
        var frontmatterCandidate = true

        var isInFencedCodeBlock = false
        var fencedMarker: Character?
        var fencedMarkerLength = 0

        nsText.enumerateSubstrings(in: NSRange(location: 0, length: nsText.length), options: [.byLines]) { _, lineRange, _, _ in
            lineNumber += 1

            let rawLine = nsText.substring(with: lineRange)
            let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)

            if frontmatterCandidate, lineNumber == 1, trimmed == "---" {
                isInFrontmatter = true
                pendingLine = nil
                return
            }

            if isInFrontmatter {
                if trimmed == "---" || trimmed == "..." {
                    isInFrontmatter = false
                    frontmatterCandidate = false
                }
                pendingLine = nil
                return
            }

            if frontmatterCandidate, !trimmed.isEmpty {
                frontmatterCandidate = false
            }

            if isInFencedCodeBlock {
                if let marker = fencedMarker, isClosingFence(trimmed, marker: marker, minLength: fencedMarkerLength) {
                    isInFencedCodeBlock = false
                    fencedMarker = nil
                    fencedMarkerLength = 0
                }
                pendingLine = nil
                return
            }

            if let (marker, length) = openingFenceInfo(trimmed) {
                isInFencedCodeBlock = true
                fencedMarker = marker
                fencedMarkerLength = length
                pendingLine = nil
                return
            }

            if let setextLevel = setextUnderlineLevel(trimmed),
                let candidate = pendingLine,
                isEligibleSetextHeadingCandidate(candidate.text)
            {
                let title = cleanTitle(candidate.text)
                if !title.isEmpty {
                    items.append(
                        EditorTOCItem(
                            level: setextLevel,
                            title: title,
                            line: candidate.lineNumber,
                            characterRange: NSRange(location: candidate.range.location, length: 0)
                        )
                    )
                }
                pendingLine = nil
                return
            }

            if let atx = parseATXHeading(trimmed) {
                if !atx.title.isEmpty {
                    items.append(
                        EditorTOCItem(
                            level: atx.level,
                            title: atx.title,
                            line: lineNumber,
                            characterRange: NSRange(location: lineRange.location, length: 0)
                        )
                    )
                }
            }

            if trimmed.isEmpty {
                pendingLine = nil
            } else {
                pendingLine = PendingLine(lineNumber: lineNumber, text: rawLine, range: lineRange)
            }
        }

        return items
    }

    private static func openingFenceInfo(_ trimmedLine: String) -> (Character, Int)? {
        guard let first = trimmedLine.first, first == "`" || first == "~" else { return nil }
        let length = trimmedLine.prefix { $0 == first }.count
        guard length >= 3 else { return nil }
        return (first, length)
    }

    private static func isClosingFence(_ trimmedLine: String, marker: Character, minLength: Int) -> Bool {
        let length = trimmedLine.prefix { $0 == marker }.count
        return length >= minLength
    }

    private static func setextUnderlineLevel(_ trimmedLine: String) -> Int? {
        guard !trimmedLine.isEmpty else { return nil }
        if trimmedLine.allSatisfy({ $0 == "=" }) && trimmedLine.count >= 2 { return 1 }
        if trimmedLine.allSatisfy({ $0 == "-" }) && trimmedLine.count >= 2 { return 2 }
        return nil
    }

    private static func isEligibleSetextHeadingCandidate(_ rawLine: String) -> Bool {
        let trimmedLine = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedLine.isEmpty else { return false }

        // Setext 标题的上一行本质上必须是“段落行”，不能已经是其他块级语法。
        // 这里先做 MVP 所需的保守过滤，避免把目录列表、引用、ATX 标题、代码围栏、
        // 任务列表、表格行等内容误收进 TOC。
        if trimmedLine.hasPrefix("#") || trimmedLine.hasPrefix(">") || trimmedLine.hasPrefix("|") {
            return false
        }

        if trimmedLine.hasPrefix("- ") || trimmedLine.hasPrefix("* ") || trimmedLine.hasPrefix("+ ") {
            return false
        }

        if trimmedLine.hasPrefix("- [") || trimmedLine.hasPrefix("* [") || trimmedLine.hasPrefix("+ [") {
            return false
        }

        if trimmedLine.hasPrefix("```") || trimmedLine.hasPrefix("~~~") {
            return false
        }

        if let first = trimmedLine.first, first.isNumber {
            let suffix = trimmedLine.drop { $0.isNumber }
            if suffix.hasPrefix(". ") || suffix.hasPrefix(") ") {
                return false
            }
        }

        return true
    }

    private static func parseATXHeading(_ trimmedLine: String) -> (level: Int, title: String)? {
        guard trimmedLine.first == "#" else { return nil }
        let level = trimmedLine.prefix { $0 == "#" }.count
        guard (1...6).contains(level) else { return nil }

        let indexAfterHashes = trimmedLine.index(trimmedLine.startIndex, offsetBy: level)
        guard indexAfterHashes < trimmedLine.endIndex else { return nil }
        guard trimmedLine[indexAfterHashes] == " " || trimmedLine[indexAfterHashes] == "\t" else { return nil }

        let remainder = trimmedLine[trimmedLine.index(after: indexAfterHashes)...]
        let title = cleanTitle(String(remainder))
        return (level, title)
    }

    private static func cleanTitle(_ raw: String) -> String {
        var title = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while let last = title.last, last == "#" {
            title.removeLast()
        }
        title = title.trimmingCharacters(in: .whitespacesAndNewlines)

        // TOC 优先保留标题文本本身，只做保守清洗，避免把整条加粗标题误洗成空。
        title = title.replacingOccurrences(
            of: "!\\[([^\\]]*)\\]\\([^\\)]*\\)",
            with: "$1",
            options: .regularExpression
        )
        title = title.replacingOccurrences(
            of: "\\[([^\\]]+)\\]\\([^\\)]*\\)",
            with: "$1",
            options: .regularExpression
        )
        title = title.replacingOccurrences(
            of: "[`~*_]+",
            with: "",
            options: .regularExpression
        )

        return title.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
