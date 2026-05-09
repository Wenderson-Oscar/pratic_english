import NaturalLanguage

enum LanguageDetector {
    static func isPortuguese(_ text: String) -> Bool {
        guard text.count >= 4 else { return false }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        let hypotheses = recognizer.languageHypotheses(withMaximum: 3)
        let pt = hypotheses[.portuguese] ?? 0
        return pt >= 0.65
    }
}
