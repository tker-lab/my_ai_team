import Foundation

/// スライドショーの絞り込み条件。MVP確定範囲(2026-09-04)の7項目すべてを持つ。
/// UserDefaults に JSON で保存し、次回起動時も同じ条件を復元する。
struct FilterSettings: Codable, Equatable {
    var dateRange: DateRangeFilter = .all
    var mediaType: MediaTypeFilter = .all
    var excludeScreenshots: Bool = true
    /// 選んだアルバムの localIdentifier の集合。空 = 全アルバム(絞り込みなし)。
    var selectedAlbumIDs: Set<String> = []
    /// 空 = 絞り込みなし(すべての雰囲気を許可)。
    var selectedMoods: Set<MoodTag> = []
    /// 空 = 絞り込みなし。PlaceCluster.id を指す。
    var selectedPlaceIDs: Set<String> = []
    /// 空 = 絞り込みなし。
    var selectedCategories: Set<CategoryTag> = []

    /// 画像解析(雰囲気 or カテゴリ)が必要かどうか。
    /// 原則2の「遅延評価」に載せるべき条件がひとつでもあるかの判定に使う。
    var needsImageAnalysis: Bool {
        !selectedMoods.isEmpty || !selectedCategories.isEmpty
    }

    static let `default` = FilterSettings()
}

// MARK: - 永続化
enum FilterSettingsStore {
    private static let key = "PhotoTimer.FilterSettings.v1"

    static func load() -> FilterSettings {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode(FilterSettings.self, from: data) else {
            return .default
        }
        return decoded
    }

    static func save(_ settings: FilterSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
