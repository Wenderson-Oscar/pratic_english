import Cocoa
import ApplicationServices

enum AccessibilityHelper {
    /// Lê o valor textual e o frame (em coordenadas AX, top-left) do elemento focado no sistema.
    /// Tenta uma cascata de estratégias para lidar com browsers, Electron e campos nativos.
    static func focusedTextAndRect() -> (String, CGRect)? {
        guard let element = focusedElement() else {
            Log.write("AX: nenhum elemento focado.")
            return nil
        }

        let role = (copyAttribute(element, kAXRoleAttribute) as? String) ?? "?"
        let subrole = (copyAttribute(element, kAXSubroleAttribute) as? String) ?? ""
        if isSecure(role: role, subrole: subrole) {
            Log.write("AX: campo seguro detectado (subrole=\(subrole)) — ignorando.")
            return nil
        }
        Log.write("AX focado → role=\(role) subrole=\(subrole)")

        let text = readText(from: element)
        guard !text.isEmpty else {
            Log.write("AX: elemento focado não expõe texto (role=\(role)).")
            return nil
        }

        let rect = readFrame(of: element)
        return (text, rect)
    }

    /// Verifica se o elemento focado é um campo de senha/seguro.
    /// Usado pelo monitor de teclado para impedir que credenciais entrem no buffer interno.
    static func focusedIsSecure() -> Bool {
        guard let element = focusedElement() else { return false }
        let role = (copyAttribute(element, kAXRoleAttribute) as? String) ?? ""
        let subrole = (copyAttribute(element, kAXSubroleAttribute) as? String) ?? ""
        return isSecure(role: role, subrole: subrole)
    }

    private static func isSecure(role: String, subrole: String) -> Bool {
        return subrole == "AXSecureTextField"
    }

    /// Substitui texto reconstruído por buffer (sem AX): N backspaces e digita o novo.
    /// Usado em VS Code, Terminal, e outros campos que não expõem AX.
    static func replaceTypedBuffer(originalLength: Int, with newValue: String) {
        // Aborta se o foco mudou para um campo seguro (senha) entre o popup mostrar
        // e o usuário aceitar — evita digitar texto traduzido em cima de credenciais.
        if focusedIsSecure() {
            Log.write("Substituição abortada: foco em campo seguro.")
            return
        }
        Log.write("Substituindo via buffer: backspace×\(originalLength), digitando \(newValue.count) chars.")
        let src = CGEventSource(stateID: .combinedSessionState)
        let tap: CGEventTapLocation = .cghidEventTap

        for _ in 0..<originalLength {
            if let down = CGEvent(keyboardEventSource: src, virtualKey: 0x33, keyDown: true) {
                down.post(tap: tap)
            }
            if let up = CGEvent(keyboardEventSource: src, virtualKey: 0x33, keyDown: false) {
                up.post(tap: tap)
            }
            usleep(2_500)
        }
        usleep(20_000)
        typeUnicode(newValue, source: src, tap: tap)
    }

    /// Substitui o texto do campo focado. Tenta AXValue, com fallback para Cmd+A + digitação simulada.
    static func replaceFocusedText(with newValue: String) {
        if let element = focusedElement() {
            let result = AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, newValue as CFString)
            if result == .success,
               let after = copyAttribute(element, kAXValueAttribute) as? String,
               after == newValue {
                Log.write("AX: substituído via AXValue.")
                return
            }
            Log.write("AX: AXValue falhou (status=\(result.rawValue)). Caindo para teclado simulado.")
        }
        simulateSelectAllAndType(newValue)
    }

    // MARK: - Internals

    private static func focusedElement() -> AXUIElement? {
        // 1. system-wide
        let system = AXUIElementCreateSystemWide()
        if let el = readAXElement(system, kAXFocusedUIElementAttribute) {
            return el
        }

        // 2. fallback: app frontmost
        guard let app = NSWorkspace.shared.frontmostApplication else {
            Log.write("AX: nenhum app frontmost.")
            return nil
        }
        Log.write("AX fallback → app frontmost: \(app.localizedName ?? "?") (pid=\(app.processIdentifier))")
        let appElement = AXUIElementCreateApplication(app.processIdentifier)

        if let el = readAXElement(appElement, kAXFocusedUIElementAttribute) {
            return el
        }

        // 3. focused window → focused element
        if let win = readAXElement(appElement, kAXFocusedWindowAttribute),
           let el = readAXElement(win, kAXFocusedUIElementAttribute) {
            return el
        }

        // 4. main window → procura recursivamente por AXFocused=true
        if let win = readAXElement(appElement, kAXMainWindowAttribute) ?? readAXElement(appElement, kAXFocusedWindowAttribute) {
            if let found = findFocusedDescendant(win, depth: 0) {
                return found
            }
        }

        return nil
    }

    private static func readAXElement(_ source: AXUIElement, _ attribute: String) -> AXUIElement? {
        var ref: CFTypeRef?
        let r = AXUIElementCopyAttributeValue(source, attribute as CFString, &ref)
        guard r == .success, let v = ref, CFGetTypeID(v) == AXUIElementGetTypeID() else {
            return nil
        }
        return (v as! AXUIElement)
    }

    private static func findFocusedDescendant(_ element: AXUIElement, depth: Int) -> AXUIElement? {
        if depth > 10 { return nil }
        if let focused = copyAttribute(element, kAXFocusedAttribute) as? Bool, focused {
            return element
        }
        if let children = copyAttribute(element, kAXChildrenAttribute) as? [AXUIElement] {
            for child in children {
                if let f = findFocusedDescendant(child, depth: depth + 1) { return f }
            }
        }
        return nil
    }

    /// Cascata: AXValue → AXSelectedText → AXTitle → procura recursivamente pelo descendente com texto.
    private static func readText(from element: AXUIElement) -> String {
        if let v = copyAttribute(element, kAXValueAttribute) as? String, !v.isEmpty { return v }
        if let v = copyAttribute(element, kAXSelectedTextAttribute) as? String, !v.isEmpty { return v }
        if let v = copyAttribute(element, kAXTitleAttribute) as? String, !v.isEmpty { return v }
        if let v = copyAttribute(element, kAXDescriptionAttribute) as? String, !v.isEmpty { return v }
        // Alguns Web Views guardam o conteúdo num filho.
        if let children = copyAttribute(element, kAXChildrenAttribute) as? [AXUIElement] {
            for child in children.prefix(8) {
                if let v = copyAttribute(child, kAXValueAttribute) as? String, !v.isEmpty { return v }
            }
        }
        return ""
    }

    private static func readFrame(of element: AXUIElement) -> CGRect {
        var origin = CGPoint.zero
        var size = CGSize.zero
        if let posRef = copyAttribute(element, kAXPositionAttribute) {
            AXValueGetValue(posRef as! AXValue, .cgPoint, &origin)
        }
        if let sizeRef = copyAttribute(element, kAXSizeAttribute) {
            AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
        }
        return CGRect(origin: origin, size: size)
    }

    private static func copyAttribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var ref: CFTypeRef?
        let r = AXUIElementCopyAttributeValue(element, name as CFString, &ref)
        return r == .success ? ref : nil
    }

    private static func listAttributes(_ element: AXUIElement) -> [String] {
        var names: CFArray?
        let r = AXUIElementCopyAttributeNames(element, &names)
        guard r == .success, let arr = names as? [String] else { return [] }
        return arr
    }

    private static func simulateSelectAllAndType(_ text: String) {
        let src = CGEventSource(stateID: .combinedSessionState)
        let tap: CGEventTapLocation = .cghidEventTap

        if let down = CGEvent(keyboardEventSource: src, virtualKey: 0x00, keyDown: true) {
            down.flags = .maskCommand
            down.post(tap: tap)
        }
        if let up = CGEvent(keyboardEventSource: src, virtualKey: 0x00, keyDown: false) {
            up.flags = .maskCommand
            up.post(tap: tap)
        }
        usleep(40_000)
        typeUnicode(text, source: src, tap: tap)
    }

    private static func typeUnicode(_ text: String, source: CGEventSource?, tap: CGEventTapLocation) {
        let utf16 = Array(text.utf16)
        let chunk = 16
        var i = 0
        while i < utf16.count {
            let end = min(i + chunk, utf16.count)
            var slice = Array(utf16[i..<end])
            if let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true) {
                down.keyboardSetUnicodeString(stringLength: slice.count, unicodeString: &slice)
                down.post(tap: tap)
            }
            if let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) {
                up.keyboardSetUnicodeString(stringLength: slice.count, unicodeString: &slice)
                up.post(tap: tap)
            }
            i = end
            usleep(2_000)
        }
    }
}
