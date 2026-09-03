import Foundation
import CoreLocation

/// 「場所」フィルタの1選択肢。ユーザー自身の写真の撮影地から自動生成する(フリー入力なし)。
struct PlaceCluster: Codable, Identifiable, Equatable {
    let id: String
    var displayName: String
    var centerLatitude: Double
    var centerLongitude: Double
    /// このかたまりに含まれるおおよその写真枚数(選択肢の並び順に使う)
    var assetCount: Int

    var location: CLLocation {
        CLLocation(latitude: centerLatitude, longitude: centerLongitude)
    }
}

/// 端末内に保存する「場所」選択肢一覧。地名変換(reverse geocoding)はOS標準のCLGeocoderのみ使用し、
/// 独自サーバーへは一切送信しない。
enum PlaceClusterStore {
    private static let key = "PhotoTimer.PlaceClusters.v1"

    static func load() -> [PlaceCluster] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([PlaceCluster].self, from: data) else {
            return []
        }
        return decoded
    }

    static func save(_ clusters: [PlaceCluster]) {
        guard let data = try? JSONEncoder().encode(clusters) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
