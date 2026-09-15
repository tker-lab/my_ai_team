import SwiftUI
import UIKit

enum GameToastKind { case success, info, warning }
struct GameToast: View {
    let message: String; var kind: GameToastKind = .info
    private var color: Color { kind == .success ? EarthColors.green : kind == .warning ? EarthColors.amber : EarthColors.cyan }
    var body: some View { HStack(spacing: 10) { Image(systemName: kind == .success ? "checkmark.seal.fill" : "info.circle.fill"); Text(message).fontWeight(.bold); Spacer() }.padding(14).foregroundStyle(EarthColors.text).background(EarthColors.raised, in: RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke(color)).shadow(color: color.opacity(0.3), radius: 12).accessibilityAddTraits(.isStaticText).onAppear { UIAccessibility.post(notification: .announcement, argument: message) } }
}

struct GameModalShell<Content: View>: View {
    let title: String; let content: Content
    @Environment(\.dismiss) private var dismiss
    init(_ title: String, @ViewBuilder content: () -> Content) { self.title = title; self.content = content() }
    var body: some View { ZStack { EarthBackdrop(variant: .archive); VStack(spacing: 16) { EarthTopBar(title: title, backAction: { dismiss() }) { EmptyView() }; content; Spacer() }.padding() } .presentationDetents([.large]).presentationDragIndicator(.hidden) }
}

struct GameEmptyState: View {
    let title: String; let message: String; var icon = "globe.asia.australia.fill"
    var body: some View { ArchivePanel { VStack(spacing: 10) { Image(systemName: icon).font(.system(size: 34)).foregroundStyle(EarthColors.cyan); Text(title).font(.headline); Text(message).font(.caption).foregroundStyle(EarthColors.secondary).multilineTextAlignment(.center) } } }
}

struct CardDetailOverlay: View {
    let card: Card; let country: Country?
    var body: some View { GameModalShell(country?.nameJa ?? card.iso3) { CollectibleCardView(card: card, country: country, size: .hero, emphasis: .featured); Text("スコア \(card.score, specifier: "%.1f")").foregroundStyle(EarthColors.secondary); CardShareButton(card: card, country: country).buttonStyle(EarthActionButtonStyle()) } }
}

private struct EarthNavigationModifier: ViewModifier {
    let title: String
    @Environment(\.dismiss) private var dismiss
    func body(content: Content) -> some View { content.toolbar(.hidden, for: .navigationBar).safeAreaInset(edge: .top, spacing: 0) { EarthTopBar(title: title, backAction: { dismiss() }) { EmptyView() }.padding(.horizontal).background(EarthColors.abyss.opacity(0.97)) } }
}
extension View { func earthNavigationTitle(_ title: String) -> some View { modifier(EarthNavigationModifier(title: title)) } }
