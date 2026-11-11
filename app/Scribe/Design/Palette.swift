import AppKit
import SwiftUI

/// "Paper" design tokens: neutral white, ink greys and one accent (iA blue).
/// Every color adapts to light and dark appearance.
enum Palette {
    static let paper = dynamic(light: 0xFFFFFF, dark: 0x161617)
    /// Panels, palettes, code backgrounds.
    static let paper2 = dynamic(light: 0xF5F5F7, dark: 0x1F1F21)
    static let ink = dynamic(light: 0x1D1D1F, dark: 0xEDEDED)
    static let ink2 = dynamic(light: 0x6E6E73, dark: 0x98989D)
    /// Markdown markers, hints, dates.
    static let ink3 = dynamic(light: 0xAEAEB2, dark: 0x636366)
    static let line = dynamic(light: 0xE5E5EA, dark: 0x2C2C2E)
    static let accent = dynamic(light: 0x1A9FFF, dark: 0x3BAFFF)
    static let accentSoft = dynamic(light: 0x1A9FFF, dark: 0x3BAFFF, alpha: 0.12)
    /// Text of the selected row (stronger than `accent` for contrast on `accentSoft`).
    static let accentText = dynamic(light: 0x0A6BB3, dark: 0x6CC4FF)
    static let selection = dynamic(light: 0x1A9FFF, dark: 0x3BAFFF, alpha: 0.2)
    static let code = dynamic(light: 0xF5F5F7, dark: 0x232325)
    /// Search hit highlight, like a marker pen.
    static let mark = dynamic(light: 0xFFCC00, dark: 0xFFD60A, alpha: 0.35)
    static let toast = dynamic(light: 0x1D1D1F, dark: 0x2C2C2E)

    static func dynamic(light: UInt32, dark: UInt32, alpha: CGFloat = 1) -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light, alpha: alpha)
        }
    }
}

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
}

extension Color {
    static let paper = Color(nsColor: Palette.paper)
    static let paper2 = Color(nsColor: Palette.paper2)
    static let ink = Color(nsColor: Palette.ink)
    static let ink2 = Color(nsColor: Palette.ink2)
    static let ink3 = Color(nsColor: Palette.ink3)
    static let line = Color(nsColor: Palette.line)
    static let accentBlue = Color(nsColor: Palette.accent)
    static let accentSoft = Color(nsColor: Palette.accentSoft)
    static let accentText = Color(nsColor: Palette.accentText)
    static let markHighlight = Color(nsColor: Palette.mark)
    static let toast = Color(nsColor: Palette.toast)
}

/// Spacing (4 pt grid), radii and motion.
enum Metrics {
    static let rowRadius: CGFloat = 7
    static let panelRadius: CGFloat = 12
    static let paletteRadius: CGFloat = 16
    static let panelInset: CGFloat = 10
    static let sidebarWidth: CGFloat = 270
    static let panelAnimation = Animation.easeOut(duration: 0.18)
}

extension View {
    /// A floating panel: Liquid Glass on macOS 26+, a solid panel with a soft shadow before.
    @ViewBuilder
    func floatingPanel(cornerRadius: CGFloat = Metrics.panelRadius, fill: Color = .paper2) -> some View {
        if #available(macOS 26.0, *), !UserDefaults.standard.bool(forKey: "disableGlass") {
            self.glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            self
                .background(fill, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).strokeBorder(Color.line))
                .shadow(color: .black.opacity(0.06), radius: 15, y: 10)
        }
    }

    /// Small UI caption style used for section headers.
    func sectionHeader() -> some View {
        self.font(.system(size: 11, weight: .semibold)).tracking(0.9).textCase(.uppercase).foregroundStyle(Color.ink3)
    }
}

/// Short, calm dates for lists: time today, "Yesterday", weekday this week, then day and month.
enum ShortDate {
    static func string(for date: Date, now: Date = Date(), calendar: Calendar = .current, locale: Locale = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        if calendar.isDate(date, inSameDayAs: now) {
            formatter.timeStyle = .short
            return formatter.string(from: date)
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            formatter.dateStyle = .medium
            formatter.doesRelativeDateFormatting = true
            return formatter.string(from: date)
        }
        if let days = calendar.dateComponents([.day], from: date, to: now).day, (0..<7).contains(days) {
            formatter.setLocalizedDateFormatFromTemplate("EEE")
            return formatter.string(from: date)
        }
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        formatter.setLocalizedDateFormatFromTemplate(sameYear ? "MMMd" : "MMMdyyyy")
        return formatter.string(from: date)
    }
}
