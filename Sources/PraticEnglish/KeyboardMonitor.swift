import Cocoa

final class KeyboardMonitor {
    enum Source {
        /// AX expôs o texto e o frame; substituição usa AXValue ou Cmd+A.
        case accessibility(rect: CGRect)
        /// Sem AX; texto reconstruído do buffer de teclas. Substituição = N backspaces + retype.
        case typedBuffer(length: Int, anchor: CGRect)
    }

    typealias Handler = (String, Source) -> Void

    private let handler: Handler
    private var monitor: Any?
    private var debounce: DispatchWorkItem?
    private let pause: TimeInterval = 0.9

    /// Buffer reconstruído a partir das teclas digitadas. Usado quando AX não dá texto.
    private var buffer = ""
    private var lastFrontApp: pid_t = 0

    init(handler: @escaping Handler) {
        self.handler = handler

        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(appActivated(_:)),
            name: NSWorkspace.didActivateApplicationNotification, object: nil
        )
    }

    @objc private func appActivated(_ note: Notification) {
        // Mudar de app reseta o buffer (evita misturar texto entre apps).
        if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
           app.processIdentifier != lastFrontApp {
            buffer = ""
            lastFrontApp = app.processIdentifier
        }
    }

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            self?.onKey(event)
        }
        if monitor == nil {
            Log.write("⚠ Falha ao criar monitor global de teclado (Input Monitoring negado?).")
        } else {
            Log.write("Monitor global de teclado instalado.")
        }
    }

    func stop() {
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
        debounce?.cancel()
    }

    /// Limpa o buffer (chamar após substituição efetiva).
    func clearBuffer() { buffer = "" }

    private func onKey(_ event: NSEvent) {
        // Limpa o buffer se o foco está num campo seguro (senha) — evita captar credenciais.
        if AccessibilityHelper.focusedIsSecure() {
            buffer = ""
            return
        }

        updateBuffer(with: event)

        let endOfSentence: Set<String> = [".", "!", "?"]
        let immediate = event.charactersIgnoringModifiers.map { endOfSentence.contains(String($0)) } ?? false

        debounce?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.checkFocused() }
        debounce = item
        let delay: TimeInterval = immediate ? 0.15 : pause
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func updateBuffer(with event: NSEvent) {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        // Modificadores não-shift (Cmd/Ctrl/Option) → ação especial → reset.
        if mods.contains(.command) || mods.contains(.control) || mods.contains(.option) {
            buffer = ""
            return
        }
        switch event.keyCode {
        case 51: // Delete (backspace)
            if !buffer.isEmpty { buffer.removeLast() }
        case 36, 76: // Return, Enter
            buffer = ""
        case 48: // Tab
            buffer = ""
        case 53: // Esc
            buffer = ""
        case 123, 124, 125, 126, 115, 116, 117, 119, 121: // setas, home, page up/down, end
            buffer = ""
        default:
            if let chars = event.characters, !chars.isEmpty,
               chars.allSatisfy({ !$0.isNewline }) {
                buffer.append(chars)
                // Limita o buffer pra não crescer indefinidamente.
                if buffer.count > 500 { buffer.removeFirst(buffer.count - 500) }
            }
        }
    }

    private func checkFocused() {
        // 1. Tenta AX (mais confiável quando disponível).
        if let (text, rect) = AccessibilityHelper.focusedTextAndRect() {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let words = trimmed.split(whereSeparator: { $0.isWhitespace }).count
            if words >= 2 {
                handler(trimmed, .accessibility(rect: rect))
                return
            }
            Log.write("checkFocused (AX): poucas palavras (\(words)).")
        }

        // 2. Fallback: usa buffer interno (VS Code, terminal, Electron sem AX).
        let trimmed = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = trimmed.split(whereSeparator: { $0.isWhitespace }).count
        guard words >= 2 else {
            Log.write("checkFocused (buffer): \(words) palavras (buffer=\(Log.redact(buffer))).")
            return
        }
        let anchor = anchorFromMouse()
        Log.write("checkFocused (buffer): usando \(buffer.count) chars do buffer interno.")
        handler(trimmed, .typedBuffer(length: buffer.count, anchor: anchor))
    }

    private func anchorFromMouse() -> CGRect {
        // NSEvent.mouseLocation: coords AppKit (origem inferior-esquerda).
        // SuggestionPopup espera coords AX (origem superior-esquerda).
        let p = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSPointInRect(p, $0.frame) }) ?? NSScreen.main
        let h = screen?.frame.height ?? 0
        let topY = h - p.y
        return CGRect(x: p.x, y: topY, width: 0, height: 20)
    }

}
