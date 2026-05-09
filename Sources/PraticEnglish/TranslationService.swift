import Foundation

/// Tradução pt-BR → en-US via API pública MyMemory (sem chave).
/// Para uso em produção, troque por DeepL/Google/OpenAI.
actor TranslationService {
    static let shared = TranslationService()

    private var cache: [String: String] = [:]
    private let endpoint = "https://api.mymemory.translated.net/get"

    func translate(_ text: String) async -> String? {
        let key = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let cached = cache[key] { return cached }

        var components = URLComponents(string: endpoint)!
        components.queryItems = [
            URLQueryItem(name: "q", value: text),
            URLQueryItem(name: "langpair", value: "pt-BR|en-US")
        ]
        guard let url = components.url else { return nil }

        var req = URLRequest(url: url)
        req.timeoutInterval = 6
        req.setValue("PraticEnglish/0.1", forHTTPHeaderField: "User-Agent")

        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }
            // Detecta cota excedida explicitamente.
            if let status = json["responseStatus"] {
                let statusStr = "\(status)".uppercased()
                if statusStr.contains("QUOTA") || statusStr.contains("EXCEEDED") {
                    Log.write("MyMemory: cota excedida (status=\(statusStr)).")
                    return nil
                }
            }
            guard let resp = json["responseData"] as? [String: Any],
                  let translated = resp["translatedText"] as? String else { return nil }
            let cleaned = translated.trimmingCharacters(in: .whitespacesAndNewlines)
            cache[key] = cleaned
            return cleaned
        } catch {
            return nil
        }
    }
}
