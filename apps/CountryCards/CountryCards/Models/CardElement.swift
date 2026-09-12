import SwiftUI

/// カードの「お題」となる要素(人口・GDPなど)。
///
/// 10種類のうち8種類は世界銀行のデータ、残り2種類(公用語の数・隣接国の数)は
/// countries.dev(REST Countries互換の無料データ)から作る。
/// どちらの由来でも同じ enum で扱えるようにしてある(データの出どころの違いを
/// アプリ側のコードに持ち込まないため)。
enum CardElement: String, Codable, CaseIterable, Identifiable, Hashable {
    case population
    case childRatio
    case popGrowth
    case lifeExpectancy
    case area
    case gdp
    case forestRatio
    case co2
    case officialLanguages
    case neighboringCountries

    var id: String { rawValue }

    /// 図鑑・ガチャ画面などに出す日本語名
    var displayName: String {
        switch self {
        case .population: return "人口"
        case .childRatio: return "子どもの割合"
        case .popGrowth: return "人口増加率"
        case .lifeExpectancy: return "平均寿命"
        case .area: return "面積"
        case .gdp: return "GDP"
        case .forestRatio: return "森林の割合"
        case .co2: return "CO2排出量"
        case .officialLanguages: return "公用語の数"
        case .neighboringCountries: return "隣接国の数"
        }
    }

    /// 数値の単位(カード表示・図鑑で使う)
    var unit: String {
        switch self {
        case .population: return "人"
        case .childRatio: return "%"
        case .popGrowth: return "%"
        case .lifeExpectancy: return "歳"
        case .area: return "km²"
        case .gdp: return "米ドル"
        case .forestRatio: return "%"
        case .co2: return "百万トン(CO2換算)"
        case .officialLanguages: return "言語"
        case .neighboringCountries: return "カ国"
        }
    }

    /// 要素ごとの縁(枠線)の色。「GDP=赤、人口=青、のように、要素ごとに1色を
    /// 濃淡なしでそのまま使う」というapp_team_country_cards.mdの配色ルールに基づく。
    /// 【暫定判断】ドキュメントには人口=青・GDP=赤の2例しか無かったため、
    /// 残り8要素の色は今回新たに割り当てた(似た色が並ばないよう配慮)。
    /// 実機で見て被りが気になれば部署内でいつでも調整できるよう、この1箇所にまとめてある。
    var borderColor: Color {
        switch self {
        case .population: return .blue
        case .gdp: return .red
        case .childRatio: return .pink
        case .popGrowth: return .orange
        case .lifeExpectancy: return .mint
        case .area: return .brown
        case .forestRatio: return .green
        case .co2: return .gray
        case .officialLanguages: return .purple
        case .neighboringCountries: return .teal
        }
    }
}
