import SwiftUI

enum DemoTier: String, CaseIterable, Identifiable {
    case normal = "N / SR"
    case ssr = "SSR"
    case ur = "UR"
    case hur = "HUR"

    var id: Self { self }
    var rank: Int { Self.allCases.firstIndex(of: self) ?? 0 }
    var title: String {
        switch self {
        case .normal: "QUIET HORIZON"
        case .ssr: "STORM AWAKENS"
        case .ur: "WORLD RESONANCE"
        case .hur: "BEYOND THE EARTH"
        }
    }
    var subtitle: String {
        switch self {
        case .normal: "雨雲の向こう、新しい国へ"
        case .ssr: "雷鳴が、まだ見ぬ大地を選ぶ"
        case .ur: "星と海が共鳴する"
        case .hur: "世界にひとつの記録が目覚める"
        }
    }
    var accent: Color {
        switch self {
        case .normal: Color(red: 0.40, green: 0.78, blue: 0.82)
        case .ssr: Color(red: 0.20, green: 0.62, blue: 1.00)
        case .ur: Color(red: 0.82, green: 0.42, blue: 1.00)
        case .hur: Color(red: 1.00, green: 0.83, blue: 0.36)
        }
    }
    var colors: [Color] {
        switch self {
        case .normal: [.black, Color(red: 0.05, green: 0.15, blue: 0.19), Color(red: 0.10, green: 0.28, blue: 0.31)]
        case .ssr: [.black, Color(red: 0.02, green: 0.10, blue: 0.30), Color(red: 0.02, green: 0.36, blue: 0.52)]
        case .ur: [.black, Color(red: 0.15, green: 0.03, blue: 0.31), Color(red: 0.44, green: 0.08, blue: 0.44)]
        case .hur: [.black, Color(red: 0.15, green: 0.08, blue: 0.02), Color(red: 0.45, green: 0.24, blue: 0.03)]
        }
    }
}

private enum DemoPhase { case menu, gathering, impact, pack, cards, finale }

struct GachaDemoView: View {
    @State private var tier: DemoTier = .ssr
    @State private var phase: DemoPhase = .menu
    @State private var phaseStarted = Date()
    @State private var revealed = 0
    @State private var isFlipping = false
    @State private var runID = UUID()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if phase == .menu { menu.transition(.opacity) }
            else { cinematic.transition(.opacity) }
        }
        .background(.black)
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.45), value: phase == .menu)
    }

    private var menu: some View {
        ZStack {
            EarthStormScene(tier: tier, intensity: 0.38)
            LinearGradient(colors: [.black.opacity(0.1), .black.opacity(0.68)], startPoint: .top, endPoint: .bottom)
            VStack(spacing: 0) {
                Spacer()
                Text("COUNTRY CARDS")
                    .font(.system(size: 13, weight: .semibold, design: .rounded)).tracking(5)
                    .foregroundStyle(.white.opacity(0.75))
                Text("EARTHBOUND")
                    .font(.system(size: 42, weight: .black, design: .rounded)).tracking(-2)
                    .foregroundStyle(.white)
                Text("GACHA CINEMATIC STUDY")
                    .font(.system(size: 10, weight: .medium, design: .monospaced)).tracking(2)
                    .foregroundStyle(tier.accent)
                    .padding(.top, 5)
                Spacer()
                VStack(spacing: 18) {
                    Text("最高レア度を選択")
                        .font(.caption.weight(.medium)).foregroundStyle(.white.opacity(0.65))
                    HStack(spacing: 8) {
                        ForEach(DemoTier.allCases) { item in
                            Button { withAnimation(.spring(response: 0.35)) { tier = item } } label: {
                                Text(item.rawValue)
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                                    .background(item == tier ? item.accent : .white.opacity(0.08), in: Capsule())
                                    .foregroundStyle(item == tier ? .black : .white.opacity(0.7))
                                    .overlay(Capsule().stroke(.white.opacity(item == tier ? 0 : 0.14)))
                            }
                            .accessibilityIdentifier("tier_\(item.rawValue)")
                        }
                    }
                    Button(action: start) {
                        HStack { Text("この演出を再生"); Image(systemName: "play.fill") }
                            .font(.headline).foregroundStyle(.black)
                            .frame(maxWidth: .infinity).padding(.vertical, 17)
                            .background(.white, in: Capsule())
                    }
                    .accessibilityIdentifier("playButton")
                    Text("導入 → パック開封 → 3枚のカード公開")
                        .font(.caption2).foregroundStyle(.white.opacity(0.45))
                }
                .padding(.horizontal, 24).padding(.bottom, 42)
            }
        }
    }

    private var cinematic: some View {
        ZStack {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { timeline in
                let elapsed = timeline.date.timeIntervalSince(phaseStarted)
                EarthStormScene(tier: tier, intensity: intensity(elapsed))
                    .overlay { phaseContent(elapsed: elapsed) }
            }
            VStack {
                HStack {
                    Button { runID = UUID(); phase = .menu } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "chevron.left")
                            VStack(alignment: .leading, spacing: 2) {
                                Text(tier.rawValue).font(.caption.bold()).foregroundStyle(tier.accent)
                                Text(tier.title).font(.caption2.monospaced()).tracking(1).foregroundStyle(.white.opacity(0.55))
                            }
                        }
                    }
                    Spacer()
                    Button(phase == .finale ? "REVEAL" : "SKIP") { skip() }
                        .font(.caption.bold()).tracking(1).foregroundStyle(.white.opacity(0.75))
                        .padding(.horizontal, 15).padding(.vertical, 9)
                        .background(.black.opacity(0.28), in: Capsule()).overlay(Capsule().stroke(.white.opacity(0.18)))
                }
                .padding(.horizontal, 20).padding(.top, 10)
                Spacer()
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { if phase == .cards { revealNext() } }
        .accessibilityIdentifier("cinematicArea")
    }

    @ViewBuilder private func phaseContent(elapsed: TimeInterval) -> some View {
        switch phase {
        case .gathering, .impact:
            IntroTitles(tier: tier, elapsed: elapsed, impact: phase == .impact)
        case .pack:
            PackOpening(tier: tier, progress: min(1, elapsed / 2.6))
        case .cards:
            CardRevealStage(tier: tier, revealed: revealed, isFlipping: isFlipping)
        case .finale:
            FinaleView(tier: tier)
        case .menu: EmptyView()
        }
    }

    private func intensity(_ elapsed: TimeInterval) -> Double {
        switch phase {
        case .gathering: min(0.85, 0.25 + elapsed * 0.16)
        case .impact: 1
        case .pack: 0.72
        case .cards, .finale: 0.48
        case .menu: 0.3
        }
    }

    private func start() {
        runID = UUID(); revealed = 0; phase = .gathering; phaseStarted = Date()
        let id = runID
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(reduceMotion ? 0.6 : tier == .hur ? 2.9 : 2.2))
            guard id == runID else { return }; phase = .impact; phaseStarted = Date()
            try? await Task.sleep(for: .seconds(reduceMotion ? 0.4 : tier == .hur ? 1.6 : 1.05))
            guard id == runID else { return }; phase = .pack; phaseStarted = Date()
            try? await Task.sleep(for: .seconds(reduceMotion ? 0.7 : 2.65))
            guard id == runID else { return }; phase = .cards; phaseStarted = Date()
        }
    }

    private func skip() { runID = UUID(); phase = .cards; revealed = 0; phaseStarted = Date() }
    private func revealNext() {
        guard !isFlipping else { return }
        if revealed < 3 {
            isFlipping = true
            withAnimation(.easeInOut(duration: reduceMotion ? 0.15 : 0.72)) { revealed += 1 }
            Task { @MainActor in try? await Task.sleep(for: .seconds(0.75)); isFlipping = false }
        } else { withAnimation(.easeInOut(duration: 0.6)) { phase = .finale } }
    }
}

private struct IntroTitles: View {
    let tier: DemoTier; let elapsed: TimeInterval; let impact: Bool
    var body: some View {
        ZStack {
            if impact { Color.white.opacity(max(0, 0.85 - elapsed * 1.5)).blendMode(.screen) }
            VStack(spacing: 11) {
                Spacer()
                Text(tier.title).font(.system(size: tier == .hur ? 31 : 27, weight: .black, design: .rounded))
                    .tracking(tier == .hur ? 3 : 1).foregroundStyle(.white).shadow(color: tier.accent, radius: 16)
                Text(tier.subtitle).font(.subheadline.weight(.medium)).foregroundStyle(.white.opacity(0.78))
                if impact { Image(systemName: tier == .hur ? "sun.max.trianglebadge.exclamationmark.fill" : "bolt.fill")
                    .font(.system(size: 34)).foregroundStyle(tier.accent).symbolEffect(.pulse) }
                Spacer().frame(height: 90)
            }.opacity(min(1, elapsed * 1.4))
        }
    }
}

private struct PackOpening: View {
    let tier: DemoTier; let progress: Double
    var body: some View {
        GeometryReader { geo in
            let w = min(geo.size.width * 0.62, 255.0), h = w * 1.36
            let split = max(0, (progress - 0.38) / 0.62)
            ZStack {
                ForEach(0..<12, id: \.self) { i in
                    Capsule().fill(tier.accent.opacity(0.7)).frame(width: 3, height: 75)
                        .offset(y: -h * 0.42).rotationEffect(.degrees(Double(i) * 30 + split * 12)).scaleEffect(y: split)
                }
                packHalf(width: w, height: h, left: true).offset(x: -split * w * 0.58).rotationEffect(.degrees(-split * 12))
                packHalf(width: w, height: h, left: false).offset(x: split * w * 0.58).rotationEffect(.degrees(split * 12))
                VStack(spacing: 5) {
                    Text(progress < 0.34 ? "ENERGY SEALED" : "OPEN THE WORLD")
                        .font(.caption.bold().monospaced()).tracking(2).foregroundStyle(.white.opacity(1 - split))
                    Image(systemName: "arrow.left.and.right").foregroundStyle(tier.accent).opacity(1 - split)
                }
            }.position(x: geo.size.width / 2, y: geo.size.height / 2 + 25)
        }
    }
    private func packHalf(width: Double, height: Double, left: Bool) -> some View {
        UnevenRoundedRectangle(topLeadingRadius: left ? 22 : 0, bottomLeadingRadius: left ? 22 : 0,
                               bottomTrailingRadius: left ? 0 : 22, topTrailingRadius: left ? 0 : 22)
            .fill(LinearGradient(colors: [tier.accent.opacity(0.95), .black, tier.accent.opacity(0.65)], startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: width / 2, height: height)
            .overlay { Rectangle().fill(.white.opacity(0.13)).frame(width: 1).frame(maxWidth: .infinity, alignment: left ? .trailing : .leading) }
            .shadow(color: tier.accent.opacity(0.8), radius: 18)
    }
}

private struct CardRevealStage: View {
    let tier: DemoTier; let revealed: Int; let isFlipping: Bool
    private let countries = [("IS", "ICELAND", "VOLCANIC ISLAND"), ("NZ", "NEW ZEALAND", "OCEAN FRONTIER"), ("JP", "JAPAN", "RISING ARCHIPELAGO")]
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            ZStack {
                ForEach(0..<3, id: \.self) { index in
                    DemoCard(tier: index == 2 ? tier : (tier.rank > 0 ? DemoTier.allCases[max(0, tier.rank - 1)] : .normal),
                             code: countries[index].0, country: countries[index].1, caption: countries[index].2,
                             faceUp: index < revealed)
                        .offset(x: CGFloat(index - 1) * 13, y: CGFloat(index - 1) * -7)
                        .rotationEffect(.degrees(Double(index - 1) * 3))
                        .zIndex(Double(index < revealed ? index + 5 : 3 - index))
                }
            }.frame(height: 390)
            VStack(spacing: 5) {
                Text(revealed < 3 ? "TAP TO REVEAL" : "TAP TO COMPLETE")
                    .font(.caption.bold().monospaced()).tracking(2).foregroundStyle(.white)
                Text("\(min(revealed + 1, 3)) / 3").font(.caption2).foregroundStyle(.white.opacity(0.55))
            }
            Spacer().frame(height: 52)
        }
    }
}

private struct DemoCard: View {
    let tier: DemoTier; let code: String; let country: String; let caption: String; let faceUp: Bool
    var body: some View {
        ZStack {
            cardBack.opacity(faceUp ? 0 : 1)
            cardFace.opacity(faceUp ? 1 : 0).scaleEffect(x: faceUp ? 1 : -1)
        }
        .frame(width: 226, height: 330)
        .rotation3DEffect(.degrees(faceUp ? 0 : 180), axis: (x: 0, y: 1, z: 0), perspective: 0.7)
        .shadow(color: tier.accent.opacity(faceUp ? 0.85 : 0.3), radius: faceUp ? 25 : 10)
    }
    private var cardBack: some View {
        RoundedRectangle(cornerRadius: 22).fill(.black)
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(tier.accent.opacity(0.75), lineWidth: 2))
            .overlay { ZStack { Circle().stroke(tier.accent.opacity(0.28), lineWidth: 15); Image(systemName: "globe.asia.australia.fill").font(.system(size: 82)).foregroundStyle(tier.accent.opacity(0.75)) } }
    }
    private var cardFace: some View {
        RoundedRectangle(cornerRadius: 22).fill(LinearGradient(colors: [.white.opacity(0.18), .black, tier.accent.opacity(0.35)], startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(LinearGradient(colors: [.white, tier.accent, .white.opacity(0.3)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: tier == .hur ? 4 : 2))
            .overlay {
                VStack(spacing: 12) {
                    HStack { Text(tier.rawValue).font(.caption.bold()); Spacer(); Text(code).font(.caption.monospaced().bold()) }.foregroundStyle(tier.accent)
                    ZStack { Circle().fill(tier.accent.opacity(0.12)); Circle().stroke(tier.accent.opacity(0.5), lineWidth: 1); Image(systemName: "globe.europe.africa.fill").font(.system(size: 86)).foregroundStyle(LinearGradient(colors: [.white, tier.accent], startPoint: .top, endPoint: .bottom)) }.frame(height: 160)
                    Text(country).font(.title3.bold()).minimumScaleFactor(0.6).lineLimit(1)
                    Text(caption).font(.caption2.monospaced()).tracking(1).foregroundStyle(.white.opacity(0.58))
                    Spacer()
                }.padding(18)
            }
    }
}

private struct FinaleView: View {
    let tier: DemoTier
    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "globe.americas.fill").font(.system(size: 76)).foregroundStyle(tier.accent).shadow(color: tier.accent, radius: 25)
            Text("THE WORLD IS YOURS").font(.system(.title2, design: .rounded, weight: .black)).tracking(1)
            Text("3つの大地がコレクションに加わりました").font(.subheadline).foregroundStyle(.white.opacity(0.65))
            Spacer()
            Text("画面を閉じて別のレア度も確認できます").font(.caption2).foregroundStyle(.white.opacity(0.4)).padding(.bottom, 40)
        }.frame(maxWidth: .infinity)
    }
}

private struct EarthStormScene: View {
    let tier: DemoTier; let intensity: Double
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                context.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(Gradient(colors: tier.colors), startPoint: .zero, endPoint: CGPoint(x: size.width, y: size.height)))
                drawEarth(&context, size, t)
                drawRain(&context, size, t)
                drawStorm(&context, size, t)
            }
        }
        .overlay { if tier == .hur { EclipseLayer(accent: tier.accent) } }
    }
    private func drawEarth(_ context: inout GraphicsContext, _ size: CGSize, _ t: Double) {
        let d = size.width * 1.22, rect = CGRect(x: (size.width-d)/2, y: size.height*0.47, width: d, height: d)
        context.fill(Path(ellipseIn: rect), with: .radialGradient(Gradient(colors: [tier.accent.opacity(0.45), .blue.opacity(0.38), .black]), center: CGPoint(x: rect.midX, y: rect.minY + d*0.25), startRadius: 0, endRadius: d*0.6))
        context.stroke(Path(ellipseIn: rect), with: .color(tier.accent.opacity(0.55)), lineWidth: 2)
        for i in 0..<9 {
            let a = t * (0.05 + Double(i%3)*0.01) + Double(i)*0.7
            let x = rect.midX + cos(a)*d*0.36, y = rect.minY+d*0.28+sin(a*1.7)*d*0.13
            context.fill(Path(ellipseIn: CGRect(x:x-d*0.09,y:y-d*0.025,width:d*0.18,height:d*0.05)), with:.color(.white.opacity(0.05+intensity*0.06)))
        }
    }
    private func drawRain(_ context: inout GraphicsContext, _ size: CGSize, _ t: Double) {
        let count = 45 + tier.rank * 18
        for i in 0..<count {
            let seed = Double((i * 47) % 101) / 101, x = seed * size.width
            let y = (Double(i * 83).truncatingRemainder(dividingBy: Double(size.height)) + t * (150 + Double(tier.rank)*45)).truncatingRemainder(dividingBy: Double(size.height))
            var p=Path(); p.move(to: CGPoint(x:x,y:y)); p.addLine(to:CGPoint(x:x-5,y:y+16+intensity*12))
            context.stroke(p, with:.color(tier.accent.opacity(0.10+intensity*0.18)), lineWidth: tier.rank > 1 ? 1.3 : 0.7)
        }
    }
    private func drawStorm(_ context: inout GraphicsContext, _ size: CGSize, _ t: Double) {
        guard tier.rank > 0 else { return }
        let pulse = (sin(t * (tier == .hur ? 1.7 : 3.0)) + 1) / 2
        guard pulse > (tier == .ssr ? 0.88 : 0.68) else { return }
        var p=Path(); p.move(to:CGPoint(x:size.width*(0.25+0.5*pulse),y:0))
        p.addLine(to:CGPoint(x:size.width*0.52,y:size.height*0.23)); p.addLine(to:CGPoint(x:size.width*0.43,y:size.height*0.42)); p.addLine(to:CGPoint(x:size.width*0.58,y:size.height*0.58))
        context.stroke(p, with:.color(tier.accent.opacity(intensity)), lineWidth: tier == .hur ? 6 : 3)
        context.addFilter(.blur(radius: 7)); context.stroke(p, with:.color(.white.opacity(0.7)), lineWidth: 5)
    }
}

private struct EclipseLayer: View {
    let accent: Color
    var body: some View {
        GeometryReader { geo in
            Circle().fill(.black).frame(width: 108, height: 108)
                .overlay(Circle().stroke(accent.opacity(0.9), lineWidth: 3).shadow(color: accent, radius: 24))
                .position(x: geo.size.width/2, y: geo.size.height*0.22)
        }.allowsHitTesting(false)
    }
}
