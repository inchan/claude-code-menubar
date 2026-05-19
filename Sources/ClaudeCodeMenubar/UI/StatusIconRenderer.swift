import AppKit

enum StatusIconRenderer {
    /// 메뉴바용 이니셜 + 색상 원형 아이콘 (단독 사용).
    static func render(initial: String, hex: String, size: CGFloat = 18,
                       warning: Bool = false) -> NSImage {
        let pxSize = NSSize(width: size, height: size)
        let image = NSImage(size: pxSize)
        image.lockFocusFlipped(false)
        defer { image.unlockFocus() }
        let rect = NSRect(origin: .zero, size: pxSize)
        drawCircle(initial: initial, hex: hex, in: rect)
        if warning { drawWarningBadge(in: rect) }
        image.isTemplate = false
        return image
    }

    /// 메뉴바 풀 라벨: [원형 이니셜] (S/W) — style 에 따라 % 또는 progress 그래픽.
    static func renderStatusBar(initial: String,
                                hex: String,
                                fiveHour: Int?,
                                fiveLevel: ThresholdLevel?,
                                sevenDay: Int?,
                                sevenLevel: ThresholdLevel?,
                                style: MenuBarStyle = .percent,
                                colorOverrides: [String: String] = [:],
                                warning: Bool = false) -> NSImage {
        // 메뉴바 슬롯 높이는 22pt. 이미지 height 를 동일하게 맞춰야 시스템이
        // 자동 위쪽 정렬을 하지 않는다. 원형 아이콘은 18pt 유지하고 22pt 안에서 가운데.
        let height: CGFloat = 22
        let circleSize: CGFloat = 18
        let gap: CGFloat = 8
        let labelFont = AppFonts.ns(size: AppFonts.menuBarSize)
        let secondary = NSColor.secondaryLabelColor

        // 표시할 항목 + 색상 결정 (override 적용).
        var items: [(label: String, percent: Int, color: NSColor)] = []
        if let fh = fiveHour, let lv = fiveLevel {
            items.append((label: "S", percent: fh, color: lv.nsColor(overrides: colorOverrides)))
        }
        if let sd = sevenDay, let lv = sevenLevel {
            items.append((label: "W", percent: sd, color: lv.nsColor(overrides: colorOverrides)))
        }

        if style == .progress {
            return renderProgressStyle(initial: initial, hex: hex, items: items,
                                       height: height, circleSize: circleSize, gap: gap,
                                       labelFont: labelFont, secondary: secondary,
                                       warning: warning)
        }

        // percent 텍스트 스타일
        var pieces: [(String, NSColor)] = []
        for (i, it) in items.enumerated() {
            if i > 0 { pieces.append((" \u{2759} ", secondary)) }
            pieces.append(("\(it.label): \(it.percent)%", it.color))
        }
        if pieces.isEmpty { pieces.append((" --", secondary)) }

        let attrs: [(NSAttributedString, NSSize)] = pieces.map { piece in
            let a = NSAttributedString(string: piece.0, attributes: [
                .font: labelFont, .foregroundColor: piece.1, .kern: 0.8, .tracking: 0.8
            ])
            return (a, a.size())
        }
        let textWidth = attrs.reduce(CGFloat(0)) { $0 + $1.1.width }
        let totalWidth = circleSize + gap + textWidth + 2

        let image = NSImage(size: NSSize(width: totalWidth, height: height),
                            flipped: false) { _ in
            let circleY = (height - circleSize) / 2
            let circleRect = NSRect(x: 0, y: circleY, width: circleSize, height: circleSize)
            drawCircle(initial: initial, hex: hex, in: circleRect)
            if warning { drawWarningBadge(in: circleRect) }
            let textBoxHeight = attrs.first?.1.height
                ?? (labelFont.ascender - labelFont.descender)
            let textY = (height - textBoxHeight) / 2
            var x: CGFloat = circleSize + gap
            for (attr, size) in attrs {
                attr.draw(at: NSPoint(x: x, y: textY))
                x += size.width
            }
            return true
        }
        image.isTemplate = false
        return image
    }

    /// progress style: [이니셜] [S 미니 bar] [W 미니 bar]
    private static func renderProgressStyle(initial: String, hex: String,
                                            items: [(label: String, percent: Int, color: NSColor)],
                                            height: CGFloat, circleSize: CGFloat, gap: CGFloat,
                                            labelFont: NSFont, secondary: NSColor,
                                            warning: Bool = false) -> NSImage {
        let barWidth: CGFloat = 36
        let barHeight: CGFloat = 5
        let labelGap: CGFloat = 6
        let interItem: CGFloat = 8
        // 폭 측정용 (모든 라벨이 같은 폰트 → 폭 동일). 색상은 그릴 때 per-item 임계치 색.
        let measureAttrs: [NSAttributedString.Key: Any] = [
            .font: labelFont, .foregroundColor: secondary, .kern: 0.8, .tracking: 0.8
        ]
        let labelWidth: CGFloat = items.isEmpty ? 0
            : NSAttributedString(string: "S", attributes: measureAttrs).size().width
        let itemWidth = labelWidth + labelGap + barWidth
        let totalWidth = circleSize + gap
            + (items.isEmpty ? 30 : (CGFloat(items.count) * itemWidth + CGFloat(max(0, items.count - 1)) * interItem))
            + 2

        let image = NSImage(size: NSSize(width: totalWidth, height: height),
                            flipped: false) { _ in
            let circleY = (height - circleSize) / 2
            let circleRect = NSRect(x: 0, y: circleY, width: circleSize, height: circleSize)
            drawCircle(initial: initial, hex: hex, in: circleRect)
            if warning { drawWarningBadge(in: circleRect) }
            var x: CGFloat = circleSize + gap
            if items.isEmpty {
                let attr = NSAttributedString(string: "--", attributes: measureAttrs)
                attr.draw(at: NSPoint(x: x, y: (height - attr.size().height) / 2))
                return true
            }
            for (idx, it) in items.enumerated() {
                let labelAttrs: [NSAttributedString.Key: Any] = [
                    .font: labelFont, .foregroundColor: it.color, .kern: 0.8, .tracking: 0.8
                ]
                let label = NSAttributedString(string: it.label, attributes: labelAttrs)
                label.draw(at: NSPoint(x: x, y: (height - label.size().height) / 2))
                let barX = x + labelWidth + labelGap
                let barY = (height - barHeight) / 2
                // 배경
                NSColor.secondaryLabelColor.withAlphaComponent(0.18).setFill()
                NSBezierPath(roundedRect: NSRect(x: barX, y: barY, width: barWidth, height: barHeight),
                             xRadius: barHeight / 2, yRadius: barHeight / 2).fill()
                // 채움
                let fillW = barWidth * CGFloat(min(max(it.percent, 0), 100)) / 100
                if fillW > 0 {
                    it.color.setFill()
                    NSBezierPath(roundedRect: NSRect(x: barX, y: barY, width: fillW, height: barHeight),
                                 xRadius: barHeight / 2, yRadius: barHeight / 2).fill()
                }
                x += itemWidth + (idx < items.count - 1 ? interItem : 0)
            }
            return true
        }
        image.isTemplate = false
        return image
    }

    // MARK: - private

    /// 원형 아이콘 우상단에 주황색 경고 배지(작은 원 + "!"). Keychain 권한 거부 등
    /// 사용자 개입이 필요한 상태를 메뉴바에서 즉시 인지하도록.
    private static func drawWarningBadge(in circleRect: NSRect) {
        let badgeSize = circleRect.width * 0.55
        let badgeRect = NSRect(
            x: circleRect.maxX - badgeSize + 1,
            y: circleRect.maxY - badgeSize + 1,
            width: badgeSize,
            height: badgeSize
        )
        // 흰색 stroke ring 으로 본체 원과 분리감.
        NSColor.white.setFill()
        NSBezierPath(ovalIn: badgeRect.insetBy(dx: -1, dy: -1)).fill()
        NSColor.systemOrange.setFill()
        NSBezierPath(ovalIn: badgeRect).fill()
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: badgeSize * 0.75),
            .foregroundColor: NSColor.white
        ]
        let text = NSAttributedString(string: "!", attributes: attrs)
        let size = text.size()
        let textRect = NSRect(
            x: badgeRect.minX + (badgeRect.width - size.width) / 2,
            y: badgeRect.minY + (badgeRect.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
        text.draw(in: textRect)
    }

    private static func drawCircle(initial: String, hex: String, in rect: NSRect) {
        let fillColor = NSColor(hex: hex) ?? .systemBlue
        fillColor.setFill()
        NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()

        let attrs: [NSAttributedString.Key: Any] = [
            .font: AppFonts.ns(size: rect.height * 0.29),
            .foregroundColor: NSColor.white
        ]
        let text = NSAttributedString(string: initial, attributes: attrs)
        let size = text.size()
        let textRect = NSRect(
            x: rect.minX + (rect.width - size.width) / 2,
            y: rect.minY + (rect.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
        text.draw(in: textRect)
    }
}

extension NSColor {
    convenience init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        let r = CGFloat((v >> 16) & 0xFF) / 255
        let g = CGFloat((v >> 8) & 0xFF) / 255
        let b = CGFloat(v & 0xFF) / 255
        self.init(srgbRed: r, green: g, blue: b, alpha: 1)
    }
}
