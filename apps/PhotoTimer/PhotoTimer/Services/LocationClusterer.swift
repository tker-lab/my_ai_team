import Foundation
import Photos
import CoreLocation

/// 「場所」フィルタの選択肢を、ユーザー自身の写真の撮影地から自動生成する。
///
/// 設計書の方針:
/// 「座標を読む(一瞬)→ 近いもの同士をクラスタリング(30〜50箇所に収束)→
///   かたまりの中心だけ地名変換。フリー入力不要、撮っていない場所は出ない。」
///
/// 地名変換(reverse geocoding)は CLGeocoder という「OS標準機能」を使う。これは端末から
/// Apple の地図サーバーへ座標を送って地名を受け取る仕組みだが、CEOの制約における「外部送信禁止」の
/// 例外として明示的に許可されている(このアプリ自身が独自サーバーと通信するわけではない)。
/// クラスタの中心1点だけを変換するので、送信されるのは「だいたいの地域の代表点」約30〜50件のみ。
enum LocationClusterer {

    /// 経度・緯度をこの度数間隔(約5.5km四方)でまとめて、同じマスに入った写真を1クラスタとする。
    /// 簡易的だが、写真ごとの解析(Vision等)を伴わないためコストはほぼゼロで、原則2の対象外(そもそも「解析」ではなくメタ情報の集計)。
    private static let gridSize = 0.05

    /// PHAsset の位置情報(メタ情報。取得済みのプロパティを読むだけで解析は不要)からクラスタを作る。
    static func buildClusters(from assets: [PHAsset]) async -> [PlaceCluster] {
        var buckets: [String: (sumLat: Double, sumLon: Double, count: Int)] = [:]

        for asset in assets {
            guard let location = asset.location else { continue }
            let key = bucketKey(for: location.coordinate)
            var bucket = buckets[key] ?? (0, 0, 0)
            bucket.sumLat += location.coordinate.latitude
            bucket.sumLon += location.coordinate.longitude
            bucket.count += 1
            buckets[key] = bucket
        }

        // 枚数が多い順に並べ、上限50箇所までに絞る(設計書の「30〜50箇所に収束」に合わせる)
        let topBuckets = buckets.values.sorted { $0.count > $1.count }.prefix(50)

        var clusters: [PlaceCluster] = []
        for bucket in topBuckets where bucket.count > 0 {
            let centerLat = bucket.sumLat / Double(bucket.count)
            let centerLon = bucket.sumLon / Double(bucket.count)
            let name = await reverseGeocodeName(latitude: centerLat, longitude: centerLon)
            let id = "\(round(centerLat * 100))_\(round(centerLon * 100))"
            clusters.append(PlaceCluster(id: id, displayName: name, centerLatitude: centerLat, centerLongitude: centerLon, assetCount: bucket.count))
        }
        return clusters
    }

    private static func bucketKey(for coordinate: CLLocationCoordinate2D) -> String {
        let latBucket = (coordinate.latitude / gridSize).rounded(.down)
        let lonBucket = (coordinate.longitude / gridSize).rounded(.down)
        return "\(latBucket)_\(lonBucket)"
    }

    private static func reverseGeocodeName(latitude: Double, longitude: Double) async -> String {
        let geocoder = CLGeocoder()
        let location = CLLocation(latitude: latitude, longitude: longitude)
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            if let place = placemarks.first {
                // 「市区町村」を優先し、無ければ都道府県・国の順にフォールバック
                return place.locality ?? place.administrativeArea ?? place.country ?? "不明な場所"
            }
        } catch {
            // ネットワーク不通・レート制限などで失敗しても、座標そのままより分かりやすい表示にフォールバック
        }
        return String(format: "北緯%.1f, 東経%.1f 付近", latitude, longitude)
    }
}
