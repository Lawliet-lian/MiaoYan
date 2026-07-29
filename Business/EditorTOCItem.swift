import Foundation

struct EditorTOCItem: Equatable {
    let level: Int
    let title: String
    let line: Int
    let characterRange: NSRange
}

