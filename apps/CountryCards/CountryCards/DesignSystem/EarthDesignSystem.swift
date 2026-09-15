import SwiftUI

enum EarthColors {
    static let ink = Color(hex: 0x040811)
    static let navy = Color(hex: 0x071426)
    static let mist = Color(hex: 0xA8BDCC)
    static let abyss = Color(hex: 0x040811)
    static let night = Color(hex: 0x071426)
    static let ocean = Color(hex: 0x0A2638)
    static let panel = Color(hex: 0x0D1B2A)
    static let raised = Color(hex: 0x12283A)
    static let line = Color(hex: 0x274256)
    static let text = Color(hex: 0xF4FAFF)
    static let secondary = Color(hex: 0xA8BDCC)
    static let disabled = Color(hex: 0x667C8B)
    static let cyan = Color(hex: 0x58D8E8)
    static let blue = Color(hex: 0x3A83FF)
    static let gold = Color(hex: 0xF2C85B)
    static let green = Color(hex: 0x55D39A)
    static let amber = Color(hex: 0xF3A63C)
    static let coral = Color(hex: 0xFF6D67)
    static let violet = Color(hex: 0xA96CFF)
    static let hurCyan = Color(hex: 0x7DF3FF)
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xff) / 255,
                  green: Double((hex >> 8) & 0xff) / 255,
                  blue: Double(hex & 0xff) / 255,
                  opacity: 1)
    }
}

enum EarthBackdropVariant { case archive, home, gacha(Rarity), battle, profile }

struct EarthBackdrop: View {
    var variant: EarthBackdropVariant = .archive
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var accent: Color {
        switch variant {
        case .battle: EarthColors.blue
        case .profile: EarthColors.gold
        case .gacha(let rarity): RarityVisualStyle(rarity: rarity).primary
        case .archive, .home: EarthColors.cyan
        }
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                LinearGradient(colors: [EarthColors.night, EarthColors.ocean, EarthColors.abyss], startPoint: .top, endPoint: .bottom)
                Circle()
                    .fill(RadialGradient(colors: [accent.opacity(0.24), EarthColors.ocean.opacity(0.75), .black], center: .top, startRadius: 0, endRadius: geo.size.width * 0.62))
                    .overlay(Circle().stroke(accent.opacity(0.25), lineWidth: 2))
                    .frame(width: geo.size.width * 1.25)
                    .offset(y: geo.size.height * 0.48)
                Canvas { context, size in
                    for i in 0..<12 {
                        let x = CGFloat((i * 83) % 127) / 127 * size.width
                        let y = CGFloat((i * 61) % 109) / 109 * size.height
                        context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 2, height: 2)), with: .color(accent.opacity(0.18)))
                    }
                    for inset in stride(from: 32.0, through: 180.0, by: 38.0) {
                        let rect = CGRect(x: size.width / 2 - inset, y: size.height * 0.32 - inset * 0.35, width: inset * 2, height: inset * 0.7)
                        context.stroke(Path(ellipseIn: rect), with: .color(.white.opacity(0.04)), lineWidth: 1)
                    }
                }
                .opacity(reduceMotion ? 0.7 : 1)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

enum ArchivePanelVariant { case standard, raised, hero, warning }

struct ArchivePanel<Content: View>: View {
    var variant: ArchivePanelVariant = .standard
    @ViewBuilder var content: Content
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var border: Color { variant == .warning ? EarthColors.amber : variant == .hero ? EarthColors.cyan.opacity(0.55) : EarthColors.line }
    var body: some View {
        content.padding(16)
            .background((variant == .raised ? EarthColors.raised : EarthColors.panel).opacity(reduceTransparency ? 1 : 0.97))
            .clipShape(RoundedRectangle(cornerRadius: variant == .hero ? 24 : 18))
            .overlay(RoundedRectangle(cornerRadius: variant == .hero ? 24 : 18).stroke(border.opacity(0.75), lineWidth: 1))
            .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
    }
}

enum EarthActionVariant { case primary, reward, secondary, quiet, danger }

struct EarthActionButtonStyle: ButtonStyle {
    var variant: EarthActionVariant = .primary
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .bold, design: .rounded))
            .foregroundStyle(enabled ? foreground : EarthColors.disabled)
            .frame(maxWidth: .infinity, minHeight: 52)
            .padding(.horizontal, 16)
            .background(background.opacity(enabled ? 1 : 0.48))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(border.opacity(enabled ? 0.8 : 0.35), lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .shadow(color: glow.opacity(configuration.isPressed ? 0.16 : 0.38), radius: configuration.isPressed ? 6 : 14)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
    private var background: AnyShapeStyle {
        switch variant {
        case .primary: AnyShapeStyle(LinearGradient(colors: [EarthColors.cyan, EarthColors.blue], startPoint: .leading, endPoint: .trailing))
        case .reward: AnyShapeStyle(LinearGradient(colors: [EarthColors.gold, EarthColors.amber], startPoint: .leading, endPoint: .trailing))
        case .secondary: AnyShapeStyle(EarthColors.raised)
        case .quiet: AnyShapeStyle(Color.clear)
        case .danger: AnyShapeStyle(EarthColors.coral.opacity(0.2))
        }
    }
    private var foreground: Color { variant == .primary || variant == .reward ? EarthColors.abyss : EarthColors.text }
    private var border: Color { variant == .danger ? EarthColors.coral : variant == .reward ? EarthColors.gold : EarthColors.line }
    private var glow: Color { variant == .reward ? EarthColors.gold : EarthColors.cyan }
}

struct EarthTopBar<Trailing: View>: View {
    let title: String
    var backAction: (() -> Void)? = nil
    @ViewBuilder var trailing: Trailing
    var body: some View {
        HStack(spacing: 12) {
            if let backAction {
                Button(action: backAction) { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                    .accessibilityLabel("戻る")
            } else { EarthEmblem().frame(width: 32, height: 32).accessibilityHidden(true) }
            Text(title).font(.system(size: 20, weight: .bold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.75)
            Spacer(); trailing
        }
        .foregroundStyle(EarthColors.text).frame(height: 52).padding(.horizontal, 16)
    }
}

extension EarthTopBar where Trailing == EmptyView {
    init(title: String, backAction: (() -> Void)? = nil) { self.init(title: title, backAction: backAction) { EmptyView() } }
}

struct EarthEmblem: View {
    var size: CGFloat = 32
    var body: some View {
        ZStack {
            Circle().stroke(EarthColors.cyan, lineWidth: 2)
            Path { p in p.move(to: CGPoint(x: 4, y: 16)); p.addCurve(to: CGPoint(x: 28, y: 16), control1: CGPoint(x: 10, y: 8), control2: CGPoint(x: 22, y: 24)) }
                .stroke(EarthColors.cyan.opacity(0.75), lineWidth: 1.5)
            Circle().fill(EarthColors.cyan).frame(width: 4)
        }
        .frame(width: size, height: size)
    }
}

struct ResourceChip: View {
    let label: String; let value: String; var tint: Color = EarthColors.cyan
    var body: some View {
        HStack(spacing: 7) { Circle().fill(tint).frame(width: 8); Text(label).foregroundStyle(EarthColors.secondary); Text(value).fontWeight(.bold).monospacedDigit() }
            .font(.caption).foregroundStyle(EarthColors.text).padding(.horizontal, 10).frame(height: 32)
            .background(EarthColors.panel, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(tint.opacity(0.45)))
    }
}

struct ArchiveSegmentSwitch<Item: Hashable>: View {
    let items: [(Item, String)]; @Binding var selection: Item
    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                Button { withAnimation(.easeInOut(duration: 0.22)) { selection = item.0 } } label: {
                    Text(item.1).font(.subheadline.weight(selection == item.0 ? .bold : .medium)).frame(maxWidth: .infinity, minHeight: 40)
                        .background(selection == item.0 ? EarthColors.raised : .clear, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(alignment: .bottom) { if selection == item.0 { Rectangle().fill(EarthColors.cyan).frame(height: 2).padding(.horizontal, 12) } }
                }.foregroundStyle(selection == item.0 ? EarthColors.text : EarthColors.secondary)
            }
        }.padding(2).background(EarthColors.panel, in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(EarthColors.line))
    }
}

struct ElementSigilButton: View {
    let element: CardElement; var detail: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ElementSigil(element: element).frame(width: 42, height: 42)
            Text(element.displayName).font(.headline).foregroundStyle(EarthColors.text)
            if let detail { Text(detail).font(.caption).foregroundStyle(EarthColors.secondary).monospacedDigit() }
        }.frame(maxWidth: .infinity, minHeight: 104, alignment: .leading).padding(14)
            .background(element.borderColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
            .overlay(alignment: .leading) { Rectangle().fill(element.borderColor).frame(width: 3).clipShape(Capsule()).padding(.vertical, 12) }
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(element.borderColor.opacity(0.55)))
    }
}

struct ElementSigil: View {
    let element: CardElement
    var body: some View {
        ZStack {
            Circle().stroke(element.borderColor.opacity(0.45), lineWidth: 1)
            ForEach(0..<3, id: \.self) { i in Circle().fill(element.borderColor).frame(width: 6).offset(x: CGFloat(i - 1) * 10, y: CGFloat((i % 2) * 8 - 4)) }
        }.accessibilityHidden(true)
    }
}

struct AdDock: View {
    var body: some View {
        Text("ADVERTISEMENT  •  広告SDK未接続")
            .font(.system(size: 9, weight: .medium, design: .monospaced)).tracking(1)
            .foregroundStyle(EarthColors.disabled).frame(width: 320, height: 50)
            .frame(maxWidth: .infinity)
            .background(EarthColors.abyss).overlay(alignment: .top) { Rectangle().fill(EarthColors.line.opacity(0.5)).frame(height: 1) }
            .accessibilityLabel("広告領域、広告SDK未接続")
    }
}

/// アプリ内モーダルでも固定バナー領域を失わない共通殻。OS共有/StoreKitは対象外。
struct SheetWithAdDock<Content: View>: View {
    @ViewBuilder let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View { VStack(spacing: 0) { content.frame(maxWidth: .infinity, maxHeight: .infinity); AdDock() }.background(EarthColors.abyss).preferredColorScheme(.dark) }
}

struct CollectionProgressOrb: View {
    let owned: Int; let total: Int
    private var progress: Double { total > 0 ? Double(owned) / Double(total) : 0 }
    var body: some View {
        ZStack {
            Circle().stroke(EarthColors.line, lineWidth: 8)
            Circle().trim(from: 0, to: progress).stroke(LinearGradient(colors: [EarthColors.cyan, EarthColors.gold], startPoint: .topLeading, endPoint: .bottomTrailing), style: StrokeStyle(lineWidth: 8, lineCap: .round)).rotationEffect(.degrees(-90))
            VStack(spacing: 2) { Text("\(String(owned))/\(String(total))").font(.headline.monospacedDigit()); Text("\(Int(progress * 100))%").font(.caption).foregroundStyle(EarthColors.secondary) }
        }.foregroundStyle(EarthColors.text).accessibilityElement(children: .ignore).accessibilityLabel("所持カード\(owned)枚、全\(total)枚、達成率\(Int(progress * 100))パーセント")
    }
}

struct RarityVisualStyle {
    let rarity: Rarity
    var primary: Color { switch rarity { case .n: Color(hex: 0xCDD7DC); case .sr: Color(hex: 0x48B875); case .ssr: Color(hex: 0x3F7FE5); case .ur: Color(hex: 0x9C56D8); case .hur: Color(hex: 0xE0B33E) } }
    var secondary: Color { switch rarity { case .n: Color(hex: 0x7F939E); case .sr: Color(hex: 0x173C2A); case .ssr: Color(hex: 0x191F5A); case .ur: Color(hex: 0xD7A83D); case .hur: Color(hex: 0x071018) } }
}
