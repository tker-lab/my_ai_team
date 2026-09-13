import SwiftUI

/// アプリ全体の見た目(色・ボタンの質感)をまとめる置き場。
///
/// 【2026-09-13追加】CEOの実機確認フィードバック「全体的にiPhone標準UIそのままの
/// 見た目で安っぽく感じる」への対応。既存の配色ルール(レア度ごとの色・要素ごとの
/// 縁の色。app_team_country_cards.mdの「配色のルール」参照)はそのまま軸に使いつつ、
/// コレクション・ガチャ入り口・対戦・プロフィールなど画面全体の底上げをする。
///
/// 【対象外(触っていない)】ガチャの導入映像・パック開封演出・カードめくり演出
/// そのもの(GachaPlayView内のintro/reveal部分)はCodexへ別途発注済みのため、
/// ここでは一切変更しない。
enum AppTheme {
    /// アプリのキーカラー(金〜オレンジ系)。カードゲームらしい華やかさを狙う。
    static let keyColorStart = Color(red: 0.98, green: 0.75, blue: 0.20)
    static let keyColorEnd = Color(red: 0.93, green: 0.45, blue: 0.15)

    static let keyGradient = LinearGradient(
        colors: [keyColorStart, keyColorEnd],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    /// タブ選択色など、システム部品に使うアクセントカラー。
    static let accent = Color(red: 0.90, green: 0.42, blue: 0.12)

    /// 画面全体の背景に薄く敷くグラデーション(白一色のiPhone標準感から脱するため)。
    static func screenBackground(_ colorScheme: ColorScheme) -> LinearGradient {
        let colors: [Color] = colorScheme == .dark
            ? [Color(red: 0.07, green: 0.08, blue: 0.13), Color(red: 0.11, green: 0.08, blue: 0.16)]
            : [Color(red: 0.97, green: 0.96, blue: 1.0), Color(red: 0.93, green: 0.93, blue: 0.99)]
        return LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
    }
}

/// 主要な操作(「対戦を始める」「対戦する」等)に使う、グラデーション+影付きの
/// 目立つボタンスタイル。標準の.borderedProminentより「ゲームらしさ」を出す。
struct GamePrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.bold))
            .foregroundStyle(.white)
            .padding(.vertical, 12)
            .padding(.horizontal, 22)
            .frame(minWidth: 0)
            .background(AppTheme.keyGradient, in: Capsule())
            .shadow(color: AppTheme.keyColorEnd.opacity(0.45), radius: configuration.isPressed ? 2 : 7, y: configuration.isPressed ? 1 : 3)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == GamePrimaryButtonStyle {
    static var gamePrimary: GamePrimaryButtonStyle { GamePrimaryButtonStyle() }
}

/// カード状の情報ブロックに使う共通の見た目(角丸+影)。プロフィール画面の
/// 王冠エリアなど、Listの中に「浮かせた」印象を出したい場所で使う。
struct RaisedCardBackground: ViewModifier {
    var cornerRadius: CGFloat = 20

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.background)
                    .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
            )
    }
}

extension View {
    func raisedCard(cornerRadius: CGFloat = 20) -> some View {
        modifier(RaisedCardBackground(cornerRadius: cornerRadius))
    }
}
