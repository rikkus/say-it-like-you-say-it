import SwiftUI

/// The same identity as the web version: cool slate neutrals, deep rose for the
/// live microphone, teal for anything settled.
enum Palette {
    static let live = Color(red: 0.67, green: 0.13, blue: 0.29)
    static let liveSoft = Color(red: 0.96, green: 0.86, blue: 0.89)
    static let settled = Color(red: 0.05, green: 0.42, blue: 0.38)
    static let settledSoft = Color(red: 0.84, green: 0.92, blue: 0.91)
    static let warn = Color(red: 0.59, green: 0.35, blue: 0.04)

    static var live2: Color { Color(.sRGB, red: 1.0, green: 0.37, blue: 0.53, opacity: 1) }
}

extension Color {
    static var liveAccent: Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark
            ? UIColor(red: 1.0, green: 0.37, blue: 0.53, alpha: 1)
            : UIColor(red: 0.67, green: 0.13, blue: 0.29, alpha: 1) })
    }
    static var settledAccent: Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark
            ? UIColor(red: 0.26, green: 0.83, blue: 0.75, alpha: 1)
            : UIColor(red: 0.05, green: 0.42, blue: 0.38, alpha: 1) })
    }
    static var warnAccent: Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark
            ? UIColor(red: 0.89, green: 0.65, blue: 0.30, alpha: 1)
            : UIColor(red: 0.59, green: 0.35, blue: 0.04, alpha: 1) })
    }
}

extension Font {
    /// The lines you read aloud get a serif — they're prose, not interface.
    static func reading(_ size: CGFloat) -> Font {
        .system(size: size, weight: .regular, design: .serif)
    }
    static func label(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold, design: .default)
    }
    static func data(_ size: CGFloat) -> Font {
        .system(size: size, weight: .regular, design: .monospaced)
    }
}

struct Eyebrow: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .tracking(1.4)
            .foregroundStyle(.secondary)
    }
}

struct Panel<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
