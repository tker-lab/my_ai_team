import SwiftUI

/// アプリ全体の配色テーマ。CEO要望(2026-09-06):設定画面からいつでも切り替えられる
/// 2種類を用意する。表示名は色の名前だけ(「ブルー」「クリーム」)で確定している
/// (性別を示す言葉は使わない、というCEO決定・2026-09-06)。
/// 判定ロジックには一切関わらない、見た目の色・字体だけを差し替えるための値。
enum AppTheme: String, CaseIterable, Identifiable {
    /// 青系統を基調にした爽やかな配色。
    case oceanBlue
    /// クリーム色のような柔らかい色合いの、落ち着いた配色。
    case creamSoft

    var id: String { rawValue }

    static let `default`: AppTheme = .oceanBlue

    var displayName: String {
        switch self {
        case .oceanBlue: return "ブルー"
        case .creamSoft: return "クリーム"
        }
    }

    /// テーマごとの字体(CEO要望・2026-09-06)。SwiftUIの`Font.Design`を切り替えるだけで、
    /// 文言や機能には一切関わらない。
    /// ブルー:直線的でシャープな印象にするため、標準(SF Pro)のまま。
    /// クリーム:丸みのある柔らかい印象にするため、SF Roundedデザインにする。
    var fontDesign: Font.Design {
        switch self {
        case .oceanBlue: return .default
        case .creamSoft: return .rounded
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

private struct ThemedFontDesignModifier: ViewModifier {
    @AppStorage(AppThemeStore.key) private var themeRawValue: String = AppTheme.default.rawValue
    private var theme: AppTheme { AppTheme(rawValue: themeRawValue) ?? .default }
    func body(content: Content) -> some View {
        content.fontDesign(theme.fontDesign)
    }
}

extension View {
    /// ボタン・アイコンなどの基調色を、選ばれているテーマのアクセントカラーに合わせる。
    func themedTint() -> some View { modifier(ThemedTintModifier()) }

    /// 文字の書体を、選ばれているテーマの字体(丸み/直線的)に合わせる。
    /// 明示的にdesignを指定しているFont(例:Font.system(size:weight:design:))には効かない点に注意
    /// (SwiftUIの仕様。その場合は呼び出し側でtheme.fontDesignを直接渡す)。
    func themedFontDesign() -> some View { modifier(ThemedFontDesignModifier()) }

    /// Form/Listの標準背景を消し、代わりにテーマの背景色を敷く。
    func themedFormBackground() -> some View {
        self.scrollContentBackground(.hidden).background(ThemedScreenBackground())
    }
}
