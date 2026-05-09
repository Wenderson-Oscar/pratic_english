import Foundation

enum Log {
    /// Quando true, mensagens marcadas como sensíveis incluem o texto. Default: false.
    /// Pode ser ligado em desenvolvimento via UserDefaults: `defaults write <bundle-id> PraticEnglish.verboseLogging -bool YES`
    static var verbose: Bool {
        UserDefaults.standard.bool(forKey: "PraticEnglish.verboseLogging")
    }

    static let url: URL = {
        let dir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("PraticEnglish.log")
    }()

    private static let queue = DispatchQueue(label: "praticenglish.log")
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    /// Apaga o arquivo de log. Próximas chamadas a `write` recriam o arquivo.
    static func clear() {
        queue.sync {
            try? FileManager.default.removeItem(at: url)
        }
    }

    static func write(_ message: String) {
        let line = "[\(formatter.string(from: Date()))] \(message)\n"
        queue.async {
            if let data = line.data(using: .utf8) {
                if FileManager.default.fileExists(atPath: url.path),
                   let handle = try? FileHandle(forWritingTo: url) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    try? handle.close()
                } else {
                    try? data.write(to: url)
                }
            }
        }
        FileHandle.standardError.write(line.data(using: .utf8) ?? Data())
    }

    /// Substitui texto sensível por sua contagem de caracteres/palavras quando verbose=false.
    /// Use para qualquer conteúdo que o usuário digitou.
    static func redact(_ text: String) -> String {
        if verbose { return text }
        let chars = text.count
        let words = text.split(whereSeparator: \.isWhitespace).count
        return "<\(words)w/\(chars)c>"
    }
}
