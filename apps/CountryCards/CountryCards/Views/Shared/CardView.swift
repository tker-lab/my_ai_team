import SwiftUI

enum CollectibleCardSize { case mini, battle, grid, hero, share
    var dimensions: CGSize { switch self { case .mini: .init(width: 72, height: 100); case .battle: .init(width: 104, height: 146); case .grid: .init(width: 156, height: 218); case .hero: .init(width: 226, height: 316); case .share: .init(width: 360, height: 504) } }
}
enum CollectibleCardRevealState { case hidden, valueHidden, revealed }
enum CollectibleCardEmphasis { case standard, selected, featured, winner, new }
enum CollectibleCardAnimationPolicy { case live, `static` }

struct CollectibleCardView: View {
    let card: Card; let country: Country?
    var size: CollectibleCardSize = .grid
    var revealState: CollectibleCardRevealState = .revealed
    var emphasis: CollectibleCardEmphasis = .standard
    var animationPolicy: CollectibleCardAnimationPolicy = .live
    /// 対戦中はレア度を推測できる文字・色・光をすべて中立化する。
    var hidesRarity = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shimmer = false
    private var d: CGSize { size.dimensions }
    private var scale: CGFloat { d.width / 160 }
    private var radius: CGFloat { max(11, 16 * scale) }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(revealState == .hidden ? AnyShapeStyle(EarthColors.navy) : hidesRarity ? AnyShapeStyle(LinearGradient(colors: [EarthColors.mist, Color(red: 0.48, green: 0.55, blue: 0.58)], startPoint: .topLeading, endPoint: .bottomTrailing)) : AnyShapeStyle(card.rarity.baseGradient))
                .overlay(alignment: .top) { LinearGradient(colors: [.white.opacity(0.3), .clear], startPoint: .top, endPoint: .bottom).frame(height: d.height * 0.38) }
            if revealState == .hidden { cardBack } else { cardInformation }
            if !hidesRarity, revealState != .hidden, card.rarity >= .ssr { rarityLight }
        }
        .frame(width: d.width, height: d.height)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(revealState == .hidden ? EarthColors.mist.opacity(0.42) : hidesRarity ? EarthColors.line : card.element.borderColor, lineWidth: max(2, 4 * scale)) }
        .shadow(color: emphasis == .selected || emphasis == .winner || emphasis == .new ? EarthColors.cyan.opacity(0.52) : .black.opacity(0.42), radius: emphasis == .featured ? 18 : 8, y: 5)
        .accessibilityElement(children: .combine).accessibilityLabel(accessibilityText)
        .onAppear { shimmer = !reduceMotion && animationPolicy == .live }
    }

    private var cardInformation: some View {
        VStack(spacing: max(3, 7 * scale)) {
            ZStack(alignment: .topTrailing) { flag; ElementSigil(element: card.element).frame(width: max(22, 31 * scale), height: max(22, 31 * scale)).padding(5 * scale) }
            Text(country?.nameJa ?? "???").font(.system(size: max(11, 17 * scale), weight: .black, design: .rounded)).lineLimit(1).minimumScaleFactor(0.55)
            Text(card.element.displayName).font(.system(size: max(9, 12 * scale), weight: .bold, design: .rounded)).foregroundStyle(.black.opacity(0.64)).lineLimit(1).minimumScaleFactor(0.65)
            Text(revealState == .valueHidden ? "？？？" : card.displayValue + card.element.unit).font(.system(size: max(11, 18 * scale), weight: .black, design: .rounded)).lineLimit(1).minimumScaleFactor(0.42)
            if size != .mini, let year = card.year, revealState == .revealed { Text("\(year)年のデータ").font(.system(size: max(7, 9 * scale), weight: .semibold)).foregroundStyle(.black.opacity(0.54)) }
            if !hidesRarity { RarityBadge(rarity: card.rarity, compact: size == .mini) }
        }.foregroundStyle(.black.opacity(0.86)).padding(max(7, 12 * scale))
    }

    @ViewBuilder private var flag: some View {
        if let url = country?.flagImageURL() {
            AsyncImage(url: url) { phase in
                if case .success(let image) = phase { image.resizable().aspectRatio(contentMode: .fill) } else { EarthColors.mist.opacity(0.38) }
            }.frame(height: d.height * 0.31).clipShape(RoundedRectangle(cornerRadius: max(6, 8 * scale)))
        } else { RoundedRectangle(cornerRadius: max(6, 8 * scale)).fill(EarthColors.mist.opacity(0.38)).frame(height: d.height * 0.31).overlay(Image(systemName: "globe.asia.australia.fill").foregroundStyle(.white.opacity(0.8))) }
    }

    private var cardBack: some View { ZStack {
        ForEach(0..<3, id: \.self) { index in RoundedRectangle(cornerRadius: radius - CGFloat(index * 2)).stroke(EarthColors.cyan.opacity(0.18 + Double(index) * 0.12), lineWidth: 1).padding(CGFloat(10 + index * 10) * scale) }
        EarthEmblem(size: d.width * 0.47)
        Text("ARCHIVE").font(.system(size: max(7, 10 * scale), weight: .black, design: .monospaced)).tracking(1).foregroundStyle(EarthColors.secondary).offset(y: d.height * 0.28)
    } }

    private var rarityLight: some View {
        LinearGradient(colors: [.clear, .white.opacity(card.rarity == .hur ? 0.44 : 0.25), .clear], startPoint: .topLeading, endPoint: .bottomTrailing)
            .offset(x: shimmer ? d.width : -d.width)
            .animation(reduceMotion || animationPolicy == .static ? nil : .linear(duration: card.rarity == .hur ? 7 : 9).repeatForever(autoreverses: false), value: shimmer).allowsHitTesting(false)
    }
    private var accessibilityText: String {
        guard revealState != .hidden else { return "未入手カード" }
        let value = revealState == .valueHidden ? "数値は非公開" : card.displayValue + card.element.unit
        let base = "\(country?.nameJa ?? "国名不明")、\(card.element.displayName)、\(value)"
        return hidesRarity ? base : "\(base)、\(card.rarity.displayName)"
    }
}

struct CardView: View {
    let card: Card; let country: Country?; var isRevealed = true; var hideValue = false
    var body: some View { CollectibleCardView(card: card, country: country, size: .grid, revealState: !isRevealed ? .hidden : (hideValue ? .valueHidden : .revealed)) }
}

struct RarityBadge: View {
    let rarity: Rarity; var compact = false
    var body: some View { Text(rarity.displayName).font(.system(size: compact ? 9 : 11, weight: .black, design: .rounded)).tracking(1.1).padding(.horizontal, compact ? 6 : 9).padding(.vertical, compact ? 2 : 3).foregroundStyle(rarity == .n ? .black.opacity(0.75) : .white).background(rarity.baseColor.gradient).clipShape(Capsule()).overlay(Capsule().strokeBorder(.white.opacity(0.44), lineWidth: 0.7)) }
}
