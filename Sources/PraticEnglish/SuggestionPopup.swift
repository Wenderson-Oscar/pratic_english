import Cocoa

@MainActor
final class SuggestionPopup {
    private var panel: NSPanel?
    private var hotkeyMonitor: Any?
    private var dismissTimer: Timer?
    private var onChoice: ((Bool) -> Void)?

    private let horizontalPadding: CGFloat = 12
    private let verticalPadding: CGFloat = 10
    private let interSpacing: CGFloat = 8
    private let textWidth: CGFloat = 460
    private let minPopupWidth: CGFloat = 320

    func show(original: String,
              suggestion: String,
              anchor: CGRect,
              completion: @escaping (Bool) -> Void) {
        close()
        onChoice = completion

        let screen = screenFor(point: anchor.origin) ?? NSScreen.main
        let screenFrame = screen?.frame ?? .zero

        // Limita altura a 60% da tela; se o conteúdo passar disso, ativa scroll.
        let maxContentHeight = max(120, screenFrame.height * 0.6 - 80)
        let (contentView, fittedSize) = makeContent(suggestion: suggestion,
                                                    maxTextHeight: maxContentHeight)

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: fittedSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.hasShadow = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.contentView = contentView

        // Posicionar acima do campo focado, convertendo AX (top-left) → AppKit (bottom-left).
        let anchorTopY = screenFrame.height - anchor.origin.y
        var x = anchor.origin.x
        var y = anchorTopY + 6

        if x + fittedSize.width > screenFrame.maxX { x = screenFrame.maxX - fittedSize.width - 8 }
        if x < screenFrame.minX { x = screenFrame.minX + 8 }
        if y + fittedSize.height > screenFrame.maxY {
            y = anchorTopY - anchor.height - fittedSize.height - 6
        }
        if y < screenFrame.minY { y = screenFrame.minY + 8 }

        panel.setFrameOrigin(NSPoint(x: x, y: y))
        panel.orderFrontRegardless()

        installHotkey()
        installDismissTimer()
        self.panel = panel
    }

    func showInfo(message: String) {
        let alert = NSAlert()
        alert.messageText = "PraticEnglish"
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    func close() {
        if let m = hotkeyMonitor { NSEvent.removeMonitor(m); hotkeyMonitor = nil }
        dismissTimer?.invalidate()
        dismissTimer = nil
        panel?.orderOut(nil)
        panel = nil
        onChoice = nil
    }

    // MARK: - UI

    /// Monta o conteúdo dimensionado dinamicamente. Se o texto passar de `maxTextHeight`,
    /// envolve em NSScrollView para que tudo permaneça acessível sem cortar.
    private func makeContent(suggestion: String, maxTextHeight: CGFloat) -> (NSView, NSSize) {
        let bg = NSVisualEffectView()
        bg.material = .hudWindow
        bg.state = .active
        bg.blendingMode = .behindWindow
        bg.wantsLayer = true
        bg.layer?.cornerRadius = 12
        bg.layer?.masksToBounds = true
        bg.layer?.borderWidth = 1
        bg.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.6).cgColor

        let title = NSTextField(labelWithString: "Sugestão em inglês")
        title.font = .systemFont(ofSize: 10, weight: .semibold)
        title.textColor = .secondaryLabelColor

        let textFont = NSFont.systemFont(ofSize: 13)
        let measuredHeight = measureWrappedHeight(text: suggestion,
                                                  font: textFont,
                                                  maxWidth: textWidth)
        let needsScroll = measuredHeight > maxTextHeight
        let textBlockHeight = needsScroll ? maxTextHeight : measuredHeight

        let textContainer: NSView
        if needsScroll {
            textContainer = makeScrollableText(suggestion, font: textFont,
                                               width: textWidth, height: textBlockHeight)
        } else {
            let label = NSTextField(wrappingLabelWithString: suggestion)
            label.font = textFont
            label.textColor = .labelColor
            label.maximumNumberOfLines = 0
            label.lineBreakMode = .byWordWrapping
            label.preferredMaxLayoutWidth = textWidth
            textContainer = label
        }

        let acceptBtn = NSButton(title: "Substituir", target: self, action: #selector(acceptClicked))
        acceptBtn.bezelStyle = .rounded
        acceptBtn.keyEquivalent = "\r"

        let dismissBtn = NSButton(title: "Ignorar", target: self, action: #selector(dismissClicked))
        dismissBtn.bezelStyle = .rounded

        let hint = NSTextField(labelWithString: "⌥⇧⏎ substituir   ⎋ ignorar")
        hint.font = .systemFont(ofSize: 10)
        hint.textColor = .tertiaryLabelColor

        for v in [title, textContainer, acceptBtn, dismissBtn, hint] {
            v.translatesAutoresizingMaskIntoConstraints = false
            bg.addSubview(v)
        }

        let buttonHeight: CGFloat = 24
        let titleHeight: CGFloat = 14
        let totalHeight = verticalPadding
            + titleHeight + 2
            + textBlockHeight + interSpacing
            + buttonHeight + verticalPadding

        let contentWidth = max(minPopupWidth, textWidth + horizontalPadding * 2)

        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: bg.topAnchor, constant: verticalPadding - 2),
            title.leadingAnchor.constraint(equalTo: bg.leadingAnchor, constant: horizontalPadding),

            textContainer.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 2),
            textContainer.leadingAnchor.constraint(equalTo: bg.leadingAnchor, constant: horizontalPadding),
            textContainer.trailingAnchor.constraint(equalTo: bg.trailingAnchor, constant: -horizontalPadding),
            textContainer.heightAnchor.constraint(equalToConstant: textBlockHeight),

            acceptBtn.topAnchor.constraint(equalTo: textContainer.bottomAnchor, constant: interSpacing),
            acceptBtn.leadingAnchor.constraint(equalTo: bg.leadingAnchor, constant: horizontalPadding),

            dismissBtn.centerYAnchor.constraint(equalTo: acceptBtn.centerYAnchor),
            dismissBtn.leadingAnchor.constraint(equalTo: acceptBtn.trailingAnchor, constant: 6),

            hint.centerYAnchor.constraint(equalTo: acceptBtn.centerYAnchor),
            hint.trailingAnchor.constraint(equalTo: bg.trailingAnchor, constant: -horizontalPadding)
        ])

        bg.frame = NSRect(x: 0, y: 0, width: contentWidth, height: totalHeight)
        return (bg, NSSize(width: contentWidth, height: totalHeight))
    }

    private func makeScrollableText(_ text: String, font: NSFont,
                                    width: CGFloat, height: CGFloat) -> NSView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        scroll.autohidesScrollers = true

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.font = font
        textView.textColor = .labelColor
        textView.textContainerInset = NSSize(width: 0, height: 2)
        textView.string = text
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true

        scroll.documentView = textView
        scroll.frame = NSRect(x: 0, y: 0, width: width, height: height)
        return scroll
    }

    /// Mede a altura necessária para renderizar `text` com quebras automáticas em `maxWidth`.
    private func measureWrappedHeight(text: String, font: NSFont, maxWidth: CGFloat) -> CGFloat {
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let attributed = NSAttributedString(string: text, attributes: attrs)
        let size = NSSize(width: maxWidth, height: CGFloat.greatestFiniteMagnitude)
        let rect = attributed.boundingRect(
            with: size,
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        return ceil(rect.height) + 4
    }

    @objc private func acceptClicked() { choose(true) }
    @objc private func dismissClicked() { choose(false) }

    private func choose(_ accepted: Bool) {
        let cb = onChoice
        close()
        cb?(accepted)
    }

    // MARK: - Hotkey global

    private func installHotkey() {
        hotkeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self else { return }
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            // Aceitar: ⌥⇧⏎
            if event.keyCode == 36 && mods.contains(.option) && mods.contains(.shift) {
                Task { @MainActor in self.choose(true) }
                return
            }
            // Qualquer outra tecla (digitar, apagar, setas, Esc, Tab, Enter…) → fecha o popup.
            // Modificadores sozinhos (Shift/Cmd/Option/Ctrl) disparam .flagsChanged, não .keyDown.
            Task { @MainActor in self.choose(false) }
        }
    }

    private func installDismissTimer() {
        dismissTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.choose(false) }
        }
    }

    private func screenFor(point: CGPoint) -> NSScreen? {
        for screen in NSScreen.screens {
            if NSPointInRect(NSPoint(x: point.x, y: point.y), screen.frame) {
                return screen
            }
        }
        return NSScreen.main
    }
}
