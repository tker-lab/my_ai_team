import SwiftUI

struct BatchObservationView: View {
    let cards: [Card]; let isNew: [Bool]
    @ObservedObject private var database = CardDatabase.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: Phase = .paused
    @State private var index = 0
    @State private var fastPulse = false
    @State private var progressOrbit = false
    @State private var packOpen = false
    @State private var awaitingPackOpen = false
    @State private var task: Task<Void, Never>?
    @State private var filter: ResultFilter = .all
    @State private var selectedCard: Card?
    private enum Phase: Equatable { case paused, cinematic, fastForward, rareStopped(faceUp: Bool), done }
    private enum ResultFilter: String, CaseIterable { case all = "すべて", rare = "SSR+", new = "NEW" }
    private var highest: Rarity { cards.map(\.rarity).max() ?? .n }
    private var highestIndex: Int? { cards.indices.max(by: { cards[$0].rarity < cards[$1].rarity }) }
    private var filteredRemaining: [Int] { cards.indices.filter { index in
        guard index != highestIndex else { return false }
        switch filter { case .all: return true; case .rare: return cards[index].rarity >= .ssr; case .new: return isNew.indices.contains(index) && isNew[index] }
    } }

    var body: some View { ZStack(alignment: .topTrailing) {
        switch phase {
        case .paused, .cinematic:
            Button { handleIntroTap() } label: {
                ZStack {
                    GachaStormScene(rarity: highest, isPlaying: phase == .cinematic)
                    GachaPackOpening(rarity: highest, open: packOpen)
                    if phase == .cinematic {
                        Circle().trim(from: 0.08, to: 0.82).stroke(EarthColors.cyan.opacity(0.7), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                            .frame(width: 286, height: 286).rotationEffect(.degrees(progressOrbit ? 360 : 0))
                            .animation(reduceMotion ? nil : .linear(duration: 1.6).repeatForever(autoreverses: false), value: progressOrbit)
                            .allowsHitTesting(false).accessibilityHidden(true)
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity).contentShape(Rectangle())
            }
                .buttonStyle(BatchImmediateResponseStyle()).accessibilityIdentifier("batchIntroArea")
            Button("スキップ") { beginSkip() }.buttonStyle(EarthActionButtonStyle(variant: .secondary)).padding().accessibilityIdentifier("batchSkipButton")
        case .fastForward:
            ZStack {
                ForEach(0..<5, id: \.self) { layer in
                    RoundedRectangle(cornerRadius: 18).fill(EarthColors.ink).overlay(RoundedRectangle(cornerRadius: 18).stroke(EarthColors.cyan.opacity(0.55)))
                        .frame(width: 150, height: 210).offset(x: CGFloat(layer - 2) * 8, y: fastPulse ? -10 : 10).opacity(0.35 + Double(layer) * 0.12)
                }
                Capsule().fill(EarthColors.cyan.opacity(0.7)).frame(width: 230, height: 3).offset(y: fastPulse ? -120 : 120).blur(radius: 2)
            }.animation(.linear(duration: 0.08), value: fastPulse).accessibilityElement().accessibilityLabel("カード高速観測中").accessibilityIdentifier("batchFastForward")
            Button("スキップ") { beginSkip() }.buttonStyle(EarthActionButtonStyle(variant: .secondary)).padding().accessibilityIdentifier("batchSkipButton")
        case .rareStopped(let faceUp):
            if cards.indices.contains(index) {
                Button { revealRareCard() } label: {
                    CollectibleCardView(card: cards[index], country: faceUp ? database.country(for: cards[index].iso3) : nil, size: .hero, revealState: faceUp ? .revealed : .hidden, emphasis: .featured)
                        .frame(maxWidth: .infinity, maxHeight: .infinity).contentShape(Rectangle())
                }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(faceUp ? "batchRareCardFace" : "batchRareCardBack")
                    .id("batch-card-\(index)-\(faceUp)")
                if faceUp { CardTurnFlash(rarity: cards[index].rarity).id(index) }
            }
            Button("スキップ") { beginSkip() }.buttonStyle(EarthActionButtonStyle(variant: .secondary)).padding().accessibilityIdentifier("batchSkipButton")
        case .done:
            ScrollView { VStack(spacing: 14) {
                Text("観測完了・\(cards.count)枚").font(.title2.bold()).accessibilityIdentifier("batchResultSummary")
                if let hero = highestIndex { resultCard(hero, size: .hero) }
                ArchiveSegmentSwitch(items: ResultFilter.allCases.map { ($0, $0.rawValue) }, selection: $filter)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 78), spacing: 8)], spacing: 10) { ForEach(filteredRemaining, id: \.self) { resultCard($0, size: .mini) } }
            }.padding() }
        }
    }.onDisappear { task?.cancel() }
      .sheet(item: $selectedCard) { card in SheetWithAdDock { CardDetailOverlay(card: card, country: database.country(for: card.iso3)) } }
    }

    private func begin() {
        guard phase == .paused else { return }; phase = .cinematic; task?.cancel()
        packOpen = false; awaitingPackOpen = false
        progressOrbit = false; DispatchQueue.main.async { progressOrbit = true }
        let testMode = ProcessInfo.processInfo.arguments.contains("-uiTestBatchStops")
        let total = testMode ? 0.1 : reduceMotion ? 0.35 : (highest == .hur ? 7.15 : 5.9)
        task = Task {
            try? await Task.sleep(for: .seconds(total * 0.72)); guard !Task.isCancelled else { return }
            packOpen = true
            try? await Task.sleep(for: .seconds(total * 0.28)); guard !Task.isCancelled else { return }
            startFastForward()
        }
    }
    private func handleIntroTap() {
        guard phase == .cinematic else { begin(); return }
        if awaitingPackOpen {
            awaitingPackOpen = false; packOpen = true; task?.cancel()
            task = Task { try? await Task.sleep(for: .milliseconds(reduceMotion ? 120 : 650)); guard !Task.isCancelled else { return }; startFastForward() }
        } else if packOpen {
            task?.cancel(); startFastForward()
        } else {
            task?.cancel(); awaitingPackOpen = true
        }
    }
    private func beginSkip() { task?.cancel(); phase = .done }
    private func startFastForward() {
        guard cards.indices.contains(index) else { phase = .done; return }
        phase = .fastForward; task?.cancel(); task = Task {
            while cards.indices.contains(index) {
                if cards[index].rarity >= .ssr { phase = .rareStopped(faceUp: false); return }
                index += 1; fastPulse.toggle()
                try? await Task.sleep(for: .milliseconds(25))
                guard !Task.isCancelled else { return }
            }
            phase = .done
        }
    }
    private func revealRareCard() {
        guard case .rareStopped(faceUp: false) = phase, cards.indices.contains(index) else { return }
        phase = .rareStopped(faceUp: true); let rarity = cards[index].rarity
        task?.cancel(); task = Task {
            let testMode = ProcessInfo.processInfo.arguments.contains("-uiTestBatchStops")
            let hold = testMode ? 1800 : (rarity == .hur ? 1300 : rarity == .ur ? 1000 : 650)
            try? await Task.sleep(for: .milliseconds(hold))
            guard !Task.isCancelled else { return }; index += 1; startFastForward()
        }
    }

    private func resultCard(_ index: Int, size: CollectibleCardSize) -> some View {
        let fresh = isNew.indices.contains(index) && isNew[index]
        return VStack(spacing: 3) {
            Button { selectedCard = cards[index] } label: { CollectibleCardView(card: cards[index], country: database.country(for: cards[index].iso3), size: size, emphasis: fresh ? .new : .standard, animationPolicy: .static) }.buttonStyle(.plain)
            Text(fresh ? "NEW" : "DUPLICATE +1pt").font(.system(size: 8, weight: .bold)).foregroundStyle(fresh ? EarthColors.gold : EarthColors.secondary)
        }
    }
}

private struct BatchImmediateResponseStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed ? 0.985 : 1).brightness(configuration.isPressed ? 0.12 : 0)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}
