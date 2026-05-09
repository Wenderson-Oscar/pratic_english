import Cocoa
import ApplicationServices

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let enabledDefaultsKey = "PraticEnglish.enabled"
    private static let autoClearLogKey = "PraticEnglish.autoClearLog"

    private var statusItem: NSStatusItem?
    private var monitor: KeyboardMonitor?
    private let popup = SuggestionPopup()
    private var lastTranslated: String?
    private var enabledMenuItem: NSMenuItem?
    private var autoClearLogMenuItem: NSMenuItem?

    private var isEnabled: Bool {
        get {
            UserDefaults.standard.object(forKey: Self.enabledDefaultsKey) as? Bool ?? true
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.enabledDefaultsKey)
            applyEnabledState()
        }
    }

    private var autoClearLog: Bool {
        get { UserDefaults.standard.bool(forKey: Self.autoClearLogKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.autoClearLogKey)
            autoClearLogMenuItem?.state = newValue ? .on : .off
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Limpa o log antes da primeira escrita, se a opção estiver ativa.
        if autoClearLog {
            Log.clear()
        }
        Log.write("App iniciado. Bundle: \(Bundle.main.bundlePath)")
        setupStatusBar()

        let ax = Permissions.accessibilityGranted(prompt: true)
        let im = Permissions.inputMonitoringGranted(prompt: true)
        Log.write("Permissões → Acessibilidade: \(ax) | Input Monitoring: \(im)")
        updateStatusTitle(ax: ax, im: im)

        if !im {
            showPermissionsAlert(ax: ax, im: im)
        }

        monitor = KeyboardMonitor { [weak self] text, source in
            self?.handle(text: text, source: source)
        }
        // start/stop é controlado por applyEnabledState — não chame .start() aqui.
        applyEnabledState()
    }

    private func setupStatusBar() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "EN"
        item.button?.toolTip = "PraticEnglish — pt-BR → en"

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "PraticEnglish", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())

        let enableItem = NSMenuItem(title: "Ativado",
                                    action: #selector(toggleEnabled),
                                    keyEquivalent: "e")
        enableItem.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(enableItem)
        enabledMenuItem = enableItem

        menu.addItem(.separator())
        let test = NSMenuItem(title: "Testar agora (campo focado)",
                              action: #selector(testNow), keyEquivalent: "t")
        menu.addItem(test)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Abrir Acessibilidade…",
                                action: #selector(openAX), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Abrir Monitoramento de Entrada…",
                                action: #selector(openIM), keyEquivalent: ""))

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Abrir log",
                                action: #selector(openLog), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Limpar log agora…",
                                action: #selector(clearLogConfirm), keyEquivalent: ""))
        let autoClearItem = NSMenuItem(title: "Limpar log ao iniciar",
                                       action: #selector(toggleAutoClearLog),
                                       keyEquivalent: "")
        autoClearItem.state = autoClearLog ? .on : .off
        menu.addItem(autoClearItem)
        autoClearLogMenuItem = autoClearItem

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Sair", action: #selector(quit), keyEquivalent: "q"))
        for mi in menu.items where mi.action != nil { mi.target = self }
        item.menu = menu
        statusItem = item
    }

    private func updateStatusTitle(ax: Bool, im: Bool) {
        let permSuffix: String
        switch (ax, im) {
        case (true, true): permSuffix = ""
        case (true, false): permSuffix = "⚠︎IM"
        case (false, true): permSuffix = "⚠︎AX"
        case (false, false): permSuffix = "⚠︎"
        }
        let base = isEnabled ? "EN" : "EN·off"
        statusItem?.button?.title = base + permSuffix
        statusItem?.button?.appearsDisabled = !isEnabled
    }

    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func toggleEnabled() {
        isEnabled.toggle()
    }

    @objc private func toggleAutoClearLog() {
        autoClearLog.toggle()
        Log.write("Auto-limpar log ao iniciar: \(autoClearLog ? "ON" : "OFF")")
    }

    @objc private func clearLogConfirm() {
        let alert = NSAlert()
        alert.messageText = "Limpar log agora?"
        alert.informativeText = "Apaga ~/Library/Logs/PraticEnglish.log. Não pode ser desfeito."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Limpar")
        alert.addButton(withTitle: "Cancelar")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Log.clear()
        Log.write("Log limpo manualmente.")
    }

    private func applyEnabledState() {
        let enabled = isEnabled
        enabledMenuItem?.state = enabled ? .on : .off

        if enabled {
            monitor?.start()
        } else {
            // Importante: paramos o monitor global de teclado para não captar
            // nada (nem buffer interno, nem AX). O buffer também é zerado.
            monitor?.stop()
            monitor?.clearBuffer()
            popup.close()
            lastTranslated = nil
        }

        let ax = Permissions.accessibilityGranted(prompt: false)
        let im = Permissions.inputMonitoringGranted(prompt: false)
        updateStatusTitle(ax: ax, im: im)
        Log.write("Estado: \(enabled ? "ATIVADO" : "DESATIVADO") (monitor \(enabled ? "ATIVO" : "PARADO"))")
    }

    @objc private func openAX() { Permissions.openAccessibilitySettings() }
    @objc private func openIM() { Permissions.openInputMonitoringSettings() }
    @objc private func openLog() { NSWorkspace.shared.open(Log.url) }

    @objc private func testNow() {
        Log.write("Testar agora acionado.")
        guard isEnabled else {
            popup.showInfo(message: "PraticEnglish está desativado.\nAtive em \"Ativado\" no menu.")
            return
        }
        guard let (text, rect) = AccessibilityHelper.focusedTextAndRect() else {
            Log.write("Nenhum elemento focado com texto encontrado.")
            popup.showInfo(message: "Nenhum campo de texto focado detectado.\nClique num campo de outro app antes de testar.")
            return
        }
        Log.write("Texto focado: \(Log.redact(text)) rect=\(rect)")
        handle(text: text, source: .accessibility(rect: rect))
    }

    private func showPermissionsAlert(ax: Bool, im: Bool) {
        let alert = NSAlert()
        alert.messageText = "Permissões necessárias"
        var lines = ["O app precisa das duas permissões abaixo para funcionar:"]
        lines.append(ax ? "✓ Acessibilidade" : "• Acessibilidade — leitura/substituição de texto")
        lines.append(im ? "✓ Monitoramento de Entrada" : "• Monitoramento de Entrada — captura de teclas")
        lines.append("")
        lines.append("Após marcar o app nas duas listas, encerre e abra novamente.")
        alert.informativeText = lines.joined(separator: "\n")
        alert.addButton(withTitle: "Abrir Monitoramento de Entrada")
        alert.addButton(withTitle: "Abrir Acessibilidade")
        alert.addButton(withTitle: "Fechar")
        let r = alert.runModal()
        if r == .alertFirstButtonReturn { Permissions.openInputMonitoringSettings() }
        else if r == .alertSecondButtonReturn { Permissions.openAccessibilitySettings() }
    }

    private func handle(text: String, source: KeyboardMonitor.Source) {
        guard isEnabled else { return }
        guard text.count >= 4 else {
            Log.write("Skip: texto curto (\(text.count) chars).")
            return
        }
        guard text != lastTranslated else {
            Log.write("Skip: mesmo texto já traduzido.")
            return
        }
        let isPT = LanguageDetector.isPortuguese(text)
        Log.write("Detect pt-BR=\(isPT) para: \(Log.redact(text))")
        guard isPT else { return }

        let anchor: CGRect
        switch source {
        case .accessibility(let rect): anchor = rect
        case .typedBuffer(_, let a): anchor = a
        }

        Task { [weak self] in
            guard let self else { return }
            Log.write("Solicitando tradução…")
            guard let translated = await TranslationService.shared.translate(text) else {
                Log.write("Tradução falhou ou retornou vazia.")
                return
            }
            let trimmed = translated.trimmingCharacters(in: .whitespacesAndNewlines)
            Log.write("Tradução: \(Log.redact(trimmed))")
            guard !trimmed.isEmpty,
                  trimmed.lowercased() != text.lowercased() else {
                Log.write("Skip: tradução vazia ou igual ao original.")
                return
            }

            await MainActor.run {
                self.lastTranslated = text
                self.popup.show(original: text, suggestion: trimmed, anchor: anchor) { accepted in
                    Log.write("Usuário \(accepted ? "ACEITOU" : "ignorou") a sugestão.")
                    guard accepted else {
                        self.lastTranslated = nil
                        return
                    }
                    self.applyReplacement(trimmed: trimmed, source: source)
                }
            }
        }
    }

    private func applyReplacement(trimmed: String, source: KeyboardMonitor.Source) {
        switch source {
        case .accessibility:
            AccessibilityHelper.replaceFocusedText(with: trimmed)
        case .typedBuffer(let length, _):
            AccessibilityHelper.replaceTypedBuffer(originalLength: length, with: trimmed)
            monitor?.clearBuffer()
        }
    }
}
