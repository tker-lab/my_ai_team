import Foundation

/// カード1種類分の定義データ(「日本の人口カード」のような、ゲーム内に存在する
/// カードの"設計図")。プレイヤーが実際に持っているかどうかはこの構造体には
/// 含まれない(所持状況は OwnedCollection が別に管理する)。
struct Card: Codable, Identifiable, Hashable {
    /// "JPN_population" のような一意なID(国コード+要素で決まる)。
    let id: String
    let iso3: String
    let element: CardElement
    /// 元になった数値そのもの(北朝鮮のGDPカードだけは値が無いのでnil)。
    let value: Double?
    /// その数値が何年のデータか(公用語の数・隣接国の数は「変化しない情報」
    /// という扱いのため年を持たずnil)。
    let year: Int?
    /// 対数正規化 or 線形正規化した0〜100点のスコア。レア度はこのスコアの
    /// 「両端への近さ」から機械的に決まる(generate_cards.py参照)。
    let score: Double
    let rarity: Rarity
    /// 北朝鮮のGDPカードのような、通常の集計に含めない特別カードかどうか。
    let isSpecial: Bool
    /// 特別カードで、数値の代わりに表示する文字列(例:「データ非公開」)。
    let displayValueOverride: String?

    /// カードに表示する数値の文字列。
    /// 【2026-09-13 修正】カンマ区切り(例:124,000,000)は読みにくいという指摘を受け、
    /// 大きな数値は日本語の位取り(兆・億・万)表記に統一する(例:「1億2400万」)。
    var displayValue: String {
        if let override = displayValueOverride {
            return override
        }
        guard let value else { return "-" }
        switch element {
        case .population, .area:
            return Self.japaneseLargeNumber(value)
        case .gdp:
            return formattedLargeCurrency(value)
        case .childRatio, .popGrowth, .forestRatio:
            return String(format: "%.1f", value)
        case .lifeExpectancy:
            return String(format: "%.1f", value)
        case .co2:
            return String(format: "%.1f", value)
        case .officialLanguages, .neighboringCountries:
            return String(Int(value))
        }
    }

    /// 人口・面積のような大きな整数を「1億2400万」のように日本語の位取りで表示する。
    /// 読みやすさを優先し、1万未満の端数は四捨五入で丸める(1万未満の値はそのまま
    /// 整数表示にする。値が小さいのでカンマも不要)。
    static func japaneseLargeNumber(_ value: Double) -> String {
        let rounded = value.rounded()
        guard rounded >= 10_000 else {
            return String(format: "%.0f", rounded)
        }
        let manCount = Int64((rounded / 10_000).rounded()) // 1万単位に丸めた個数
        let cho = manCount / 100_000_000 // 1兆 = 1億万
        var remainder = manCount % 100_000_000
        let oku = remainder / 10_000 // 1億 = 1万万
        remainder %= 10_000
        let man = remainder

        var parts: [String] = []
        if cho > 0 { parts.append("\(cho)兆") }
        if oku > 0 { parts.append("\(oku)億") }
        if man > 0 { parts.append("\(man)万") }
        return parts.isEmpty ? "0" : parts.joined()
    }

    /// GDPは兆・億単位が大きすぎて桁区切りだけでは読みにくいため、
    /// 「4兆4351億ドル」のような日本語の位取りで表示する。
    private func formattedLargeCurrency(_ value: Double) -> String {
        let oku = value / 100_000_000 // 1億
        if oku >= 10_000 {
            let cho = oku / 10_000
            return String(format: "%.1f兆ドル", cho)
        } else if oku >= 1 {
            return String(format: "%.0f億ドル", oku)
        } else {
            return String(format: "%.0fドル", value)
        }
    }
}
