import AppKit

extension ThresholdLevel {
    var shortLabel: String {
        switch self {
        case .healthy: return "정상"
        case .caution: return "주의"
        case .warning: return "경고"
        case .critical: return "위험"
        }
    }
}

extension NSColor {
    /// "#RRGGBB" 형식 변환. sRGB 변환 후 hex.
    var hexString: String {
        let c = self.usingColorSpace(.sRGB) ?? self
        let r = Int(round(c.redComponent * 255))
        let g = Int(round(c.greenComponent * 255))
        let b = Int(round(c.blueComponent * 255))
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
