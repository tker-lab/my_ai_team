import SwiftUI

/// アプリ全体の配色テーマ。CEO要望(2026-09-06):設定画面からいつでも切り替えられる
/// 2種類を用意する。「男性向け/女性向け」という呼び方は暫定のラベルで、UI文言を
/// 確定するタイミングで見直してよい(演出パターン名と同じ扱い)。
/// 判定ロジックには一切関わらない、見た目の色だけを差し替えるための値。
enum AppTheme: String, CaseIterable, Identifiable {
    /// 男性向け:青系統を基調にした爽やかな配色。
    case oceanBlue
    /// 女性向け:クリーム色のような柔らかい色合いの、落ち着いた配色。
    case creamSoft

    var id: String { rawValue }

    static let `default`: AppTheme = .oceanBlue

    var displayName: String {
        switch self {
        case .oceanBlue: return "ブルー(男性向け・爽やか)"
        case .creamSoft: return "クリーム(女性向け・やわらか)"
        }
    }

    /// ボタン・選択中チップ・アイコンなどに使う基調色(いわゆるアクセントカラー)。
    var accentColor: Color {
        switch self {
        case .oceanBlue: return Color(red: 0.10, green: 0.47, blue: 0.86)
        case .creamSoft: return Color(red: 0.70, green: 0.50, blue: 0.32)
        }
    }

    /// 画面の背景に敷く、うっすらとした色(白そのものではなく、テーマの雰囲気を出す)。
    var screenBackground: Color {
        switch self {
        case .oceanBlue: return Color(red: 0.91, green: 0.95, blue: 1.0)
        case .creamSoft: return Color(red: 0.98, green: 0.95, blue: 0.88)
        }
    }

    /// スライドショー画面(常に黒背景)の上に重ねる半透明パネル(振り返り一覧・終了画面など)の色。
    var panelTint: Color {
        switch self {
        case .oceanBlue: return Color(red: 0.06, green: 0.14, blue: 0.26)
        case .creamSoft: return Color(red: 0.26, green: 0.19, blue: 0.11)
        }
    }
}

/// UserDefaultsへの保存・読み込み(端末内のみ。外部送信なし)。
enum AppThemeStore {
    /// @AppStorageからも同じキーを直接参照する(値の形はUserDefaultsの生文字列なので一致させる)。
    static let key = "PhotoTimer.AppTheme"

    static func load() -> AppTheme {
        guard let raw = UserDefaults.standard.string(forKey: key), let theme = AppTheme(rawValue: raw) else {
            return .default
        }
        return theme
    }

    static func save(_ theme: AppTheme) {
        UserDefaults.standard.set(theme.rawValue, forKey: key)
    }
}

/// Form/Listの背景にテーマ色を敷くための小さな部品。単体のViewとして持つことで
/// @AppStorageの購読も込みで完結し、呼び出し側に状態を増やさずに済む。
struct ThemedScreenBackground: View {
    @AppStorage(AppThemeStore.key) private var themeRawValue: String = AppTheme.default.rawValue
    private var theme: AppTheme { AppTheme(rawValue: themeRawValue) ?? .default }
    var body: some View {
        theme.screenBackground.ignoresSafeArea()
    }
}

private struct ThemedTintModifier: ViewModifier {
    @AppStorage(AppThemeStore.key) private var themeRawValue: String = AppTheme.default.rawValue
    private var theme: AppTheme { AppTheme(rawValue: themeRawValue) ?? .default }
    func body(content: Content) -> some View {
        content.tint(theme.accentColor)
    }
}

extension View {
    /// ボタン・アイコンなどの基調色を、選ばれているテーマのアクセントカラーに合わせる。
    func themedTint() -> some View { modifier(ThemedTintModifier()) }

    /// Form/Listの標準背景を消し、代わりにテーマの背景色を敷く。
    func themedFormBackground() -> some View {
        self.scrollContentBackground(.hidden).background(ThemedScreenBackground())
    }
}
