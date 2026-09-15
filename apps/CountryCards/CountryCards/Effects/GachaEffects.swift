import SwiftUI
import UIKit

struct GachaStormScene: View {
    let rarity: Rarity
    let isPlaying: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var surge = false
    @State private var stage = 0
    @State private var progressionTask: Task<Void, Never>?

    private var tier: Int { rarity == .hur ? 3 : rarity == .ur ? 2 : rarity == .ssr ? 1 : 0 }
    private var stormColor: Color { tier == 3 ? EarthColors.gold : tier == 2 ? .purple : tier == 1 ? .blue : EarthColors.cyan }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color.black, EarthColors.navy, stormColor.opacity(0.38)], startPoint: .top, endPoint: .bottom)
            Canvas { context, size in
                let rainCount = [45, 63, 81, 99][tier] + stage * 16
                for index in 0..<rainCount {
                    let x = CGFloat((index * 47) % 101) / 101 * size.width
                    let y = CGFloat((index * 83) % 109) / 109 * size.height
                    var path = Path(); path.move(to: CGPoint(x: x, y: y)); path.addLine(to: CGPoint(x: x - 7, y: y + 25))
                    context.stroke(path, with: .color(.white.opacity(0.08 + Double(tier) * 0.03 + Double(stage) * 0.045)), lineWidth: 0.8 + Double(stage) * 0.12)
                }
            }
            Ellipse().fill(.black.opacity(0.48)).frame(width: 330, height: 92).blur(radius: 24).offset(x: -105 + CGFloat(stage * 24), y: -230)
            Ellipse().fill(stormColor.opacity(0.13 + Double(stage) * 0.05)).frame(width: 310, height: 80).blur(radius: 26).offset(x: 125 - CGFloat(stage * 30), y: -180)
            Circle().fill(RadialGradient(colors: [EarthColors.cyan.opacity(0.5), .blue.opacity(0.18), .clear], center: .center, startRadius: 12, endRadius: 160))
                .frame(width: 310, height: 310).offset(y: 116).scaleEffect((surge ? 1.04 : 0.94) + Double(stage) * 0.035)
            ForEach(0..<(tier + 9), id: \.self) { index in
                Capsule().fill(LinearGradient(colors: [.clear, stormColor.opacity(0.78), .white, .clear], startPoint: .top, endPoint: .bottom))
                    .frame(width: CGFloat(1 + tier), height: CGFloat(160 + index * 18))
                    .rotationEffect(.degrees(Double(index * 29 - 50))).offset(x: CGFloat((index % 3 - 1) * 78), y: -70)
                    .opacity(isPlaying && index < tier + 3 + stage * 2 ? (surge ? 0.9 : 0.28) : 0.06)
            }
            EarthEmblem(size: 126).offset(y: 105).shadow(color: stormColor.opacity(0.55 + Double(stage) * 0.14), radius: CGFloat((tier == 3 ? 40 : 22) + stage * 9))
        }
        .ignoresSafeArea().onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: tier == 3 ? 10 : 8).repeatForever(autoreverses: true)) { surge = true }
        }
        .onChange(of: isPlaying) { _, playing in
            progressionTask?.cancel(); stage = 0
            guard playing else { return }
            progressionTask = Task {
                for next in 1...3 {
                    try? await Task.sleep(for: .milliseconds(reduceMotion ? 110 : (next == 3 ? 1150 : 1450)))
                    guard !Task.isCancelled else { return }
                    withAnimation(reduceMotion ? .easeOut(duration: 0.18) : .easeInOut(duration: 0.75)) { stage = next }
                }
            }
        }
        .onDisappear { progressionTask?.cancel() }
    }
}

struct GachaPackOpening: View {
    let rarity: Rarity
    let open: Bool
    @State private var progress = 0.0
    private var accent: Color { rarity == .hur ? EarthColors.gold : rarity == .ur ? .purple : rarity == .ssr ? .blue : EarthColors.cyan }
    var body: some View {
        GeometryReader { geo in
            let width = min(geo.size.width * 0.62, 255.0), height = width * 1.36
            let split = max(0, (progress - 0.38) / 0.62)
            ZStack {
                ForEach(0..<12, id: \.self) { index in Capsule().fill(accent.opacity(0.72)).frame(width: 3, height: 75).offset(y: -height * 0.42).rotationEffect(.degrees(Double(index) * 30 + split * 12)).scaleEffect(y: split) }
                packHalf(width: width, height: height, left: true).offset(x: -split * width * 0.58).rotationEffect(.degrees(-split * 12))
                packHalf(width: width, height: height, left: false).offset(x: split * width * 0.58).rotationEffect(.degrees(split * 12))
                EarthEmblem(size: 92).opacity(1 - min(1, split * 2))
                RadialGradient(colors: [.white.opacity(0.62 * split), accent.opacity(0.4 * split), .clear], center: .center, startRadius: 2, endRadius: width * 0.75).frame(width: width * 1.8, height: width * 1.8).blendMode(.screen)
            }.position(x: geo.size.width / 2, y: geo.size.height / 2 + 25)
        }
        .onAppear { progress = open ? 1 : 0 }
        .onChange(of: open) { _, value in withAnimation(.spring(response: 0.62, dampingFraction: 0.58)) { progress = value ? 1 : 0 } }
    }

    private func packHalf(width: Double, height: Double, left: Bool) -> some View {
        UnevenRoundedRectangle(topLeadingRadius: left ? 22 : 0, bottomLeadingRadius: left ? 22 : 0, bottomTrailingRadius: left ? 0 : 22, topTrailingRadius: left ? 0 : 22)
            .fill(LinearGradient(colors: [accent.opacity(0.95), .black, accent.opacity(0.65)], startPoint: .topLeading, endPoint: .bottomTrailing)).frame(width: width / 2, height: height)
            .overlay { Rectangle().fill(.white.opacity(0.13)).frame(width: 1).frame(maxWidth: .infinity, alignment: left ? .trailing : .leading) }.shadow(color: accent.opacity(0.8), radius: 18)
    }
}

/// Triggered from the individual card rarity; it never intercepts taps.
struct CardTurnFlash: View {
    let rarity: Rarity
    @State private var peak = false
    @State private var bloom = false

    private var duration: Double { rarity == .hur ? 1.25 : rarity == .ur ? 0.95 : 0.55 }
    private var colors: [Color] {
        switch rarity { case .ssr: [.purple, .white, .purple]; case .ur: [EarthColors.gold, .white, EarthColors.gold]; case .hur: [EarthColors.gold, .white, EarthColors.cyan]; default: [.clear] }
    }

    var body: some View {
        if rarity >= .ssr {
            ZStack {
                Color.white.opacity(peak ? 0 : (rarity == .hur ? 0.92 : 0.72))
                ForEach(0..<(rarity == .hur ? 4 : 2), id: \.self) { index in
                    Circle().stroke(AngularGradient(colors: colors, center: .center), lineWidth: CGFloat(5 - min(index, 3)))
                        .frame(width: bloom ? CGFloat(280 + index * 90) : 24, height: bloom ? CGFloat(280 + index * 90) : 24).opacity(bloom ? 0 : 0.92)
                }
                ForEach(0..<(rarity == .hur ? 34 : 18), id: \.self) { index in
                    Circle().fill(colors[index % colors.count]).frame(width: CGFloat(3 + index % 5), height: CGFloat(3 + index % 5))
                        .offset(y: bloom ? -CGFloat(90 + index * 7) : -18).rotationEffect(.degrees(Double(index) * 137.5)).opacity(bloom ? 0 : 0.95)
                }
            }
            .ignoresSafeArea().allowsHitTesting(false)
            .onAppear {
                withAnimation(.easeOut(duration: duration * 0.24)) { peak = true }
                withAnimation(.easeOut(duration: duration).delay(0.04)) { bloom = true }
            }
        }
    }
}
