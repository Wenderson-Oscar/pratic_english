import Foundation

enum Log {
    /// Quando true, mensagens marcadas como sensíveis incluem o texto. Default: false.
    ///
    /// Lida da variável de ambiente `PRATICENGLISH_VERBOSE` uma única vez na inicialização
    /// e congelada para o resto da sessão. Lançar verbose:
    ///   PRATICENGLISH_VERBOSE=1 PraticEnglish.app/Contents/MacOS/PraticEnglish
    ///
    /// Não usa UserDefaults de propósito: `defaults write` é silencioso e qualquer processo
    /// na sessão do usuário poderia ligar verbose por trás. ENV var no launch obriga a ser
    /// uma ação deliberada por sessão.
    static let verbose: Bool = {
        guard let v = ProcessInfo.processInfo.environment["PRATICENGLISH_VERBOSE"] else { return false }
        let normalized = v.lowercased()
        return normalized == "1" || normalized == "true" || normalized == "yes"
    }()

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
                    // Cria com 0600 para que só o dono leia (mesmo em backups/iCloud
                    // o arquivo herda a perm). Outros processos do mesmo usuário ainda
                    // podem ler — proteção é contra contas distintas/serviços.
                    FileManager.default.createFile(
                        atPath: url.path,
                        contents: data,
                        attributes: [.posixPermissions: 0o600]
                    )
                }
                // Reforça 0600 mesmo se o arquivo já existia com perms mais frouxas.
                try? FileManager.default.setAttributes(
                    [.posixPermissions: 0o600],
                    ofItemAtPath: url.path
                )
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
