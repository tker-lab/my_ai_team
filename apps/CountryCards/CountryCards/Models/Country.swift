import Foundation

/// 国連加盟国1カ国分の基本情報(国旗・国名など、要素に依存しない情報)。
/// cards.json の "countries" 配列と1対1で対応する。
struct Country: Codable, Identifiable, Hashable {
    /// ISO 3166-1 alpha-3コード(例: "JPN")。カードのidにも使われる、国を一意に表すキー。
    let iso3: String
    let iso2: String
    let nameJa: String
    let nameEn: String
    /// flagcdn.com から国旗画像を取ってくる時に使うコード(iso2の小文字)。
    let flagCode: String

    var id: String { iso3 }

    /// flagcdn.com の国旗画像URL(高さ数百pxくらいのPNG)。
    /// 通信が不要なオフライン動作を壊さないよう、この画像は「表示できればうれしい
    /// おまけ」として使い、取得に失敗しても国名だけで成立する画面設計にすること。
    func flagImageURL(width: Int = 320) -> URL? {
        URL(string: "https://flagcdn.com/w\(width)/\(flagCode).png")
    }
}
