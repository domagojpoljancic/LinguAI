//
//  Validation.swift
//  LinguAI
//
//  Pure validation helpers for box and word forms. Extracted for testability.
//

import Foundation

enum Validation {

    /// Returns true if the trimmed name is a duplicate of an existing box (case-insensitive),
    /// excluding the box currently being edited.
    static func isDuplicateBoxName(
        _ trimmedName: String,
        existingBoxes: [VocabularyBox],
        editingBox: VocabularyBox?
    ) -> Bool {
        existingBoxes.contains { existing in
            existing.name.caseInsensitiveCompare(trimmedName) == .orderedSame &&
            existing !== editingBox
        }
    }

    /// Returns true if the (primary, target) pair already exists in the list (case-insensitive).
    static func isDuplicateWordPair(primary: String, target: String, words: [BoxWord]) -> Bool {
        words.contains {
            $0.primaryText.caseInsensitiveCompare(primary) == .orderedSame &&
            $0.targetText.caseInsensitiveCompare(target) == .orderedSame
        }
    }
}
