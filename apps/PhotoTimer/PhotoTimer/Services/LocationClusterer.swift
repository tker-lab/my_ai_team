import Foundation
import Photos
import CoreLocation

/// 「場所」フィルタの選択肢を、ユーザー自身の写真の撮影地から自動生成・維持する。
///
/// 設計書の方針:
/// 「座標を読む(一瞬)→ 近いもの同士をクラスタリング(30〜50箇所に収束)→
///   かたまりの中心だけ地名変換。フリー入力不要、撮っていない場所は出ない。」
///
/// 【2026-09-04大幅修正(チェック工程の指摘対応)】
/// 修正前は「起動のたびに全写真を読み直してクラスタを作り直す」実装だった(原則4違反)。
/// 今は状態を持つアクターにして、以下の3つを端末内に保持し、写真の増減の「差分」だけを反映する:
///  1. マス目(バケット)ごとの緯度・経度の合計値と枚数(クラスタの中心を出すための材料)
///  2. 「どの写真がどのマス目に属していたか」(写真が削除された時に(1)から正しく引き算するため。
///     削除された写真そのものからは、もう緯度経度を読めないため)
///  3. マス目ごとに一度変換した地名のキャッシュ(原則3と同じ考え方。地名変換をやり直さないことで、
///     Apple地名変換サーバーへのリクエスト回数も最小限にする=指摘Gのレート制限対策を兼ねる)
///
/// 地名変換(reverse geocoding)は CLGeocoder という「OS標準機能」を使う。これは端末から
/// Apple の地図サーバーへ座標を送って地名を受け取る仕組みだが、CEOの制約における「外部送信禁止」の
/// 例外として明示的に許可されている(このアプリ自身が独自サーバーと通信するわけではない)。
/// マス目1つにつき一度だけ変換すればよいため、送信されるのは「だいたいの地域の代表点」だけ。
actor LocationClusterer {
    static let shared = LocationClusterer()

    /// 経度・緯度をこの度数間隔でまとめて、同じマスに入った写真を1クラスタとする。
    /// 【軽微指摘対応: コメントの不正確さ】緯度1度は世界のどこでも約111kmなので、緯度方向は
    /// 常に約5.5km(=111km×0.05)。ただし経度1度の距離は緯度によって変わり(赤道に近いほど長い)、
    /// 日本付近(北緯35度前後)では約91km/度のため、経度方向は約4.5km(=91km×0.05)。
    /// つまりマス目は正確には「約5.5km(南北)×約4.5km(東西)」の長方形であり、「5.5km四方」という
    /// 正方形の表現は緯度方向にしか当てはまらない(絞り込みの正しさには影響しない。あくまで
    /// コメント上の説明の精度の話)。
    private static let gridSize = 0.05

    /// 「場所」の絞り込み一致判定は、以前は独立した半径(6km)を使っていたが、マス目(約5.5km四方)と
    /// サイズがズレており隣のマスまで混ざって拾ってしまう不具合があった(指摘H)。
    /// 今は「同じマス目(bucketKey)に属するか」で厳密に判定するように変更したため、
    /// 独立した半径パラメータ自体が不要になった(=ズレが原理的に起こらない)。
    /// 判定の実体は `CandidateEngine` 側で `LocationClusterer.bucketKey(for:)` を直接使っている。

    // MARK: - 永続化する内部状態

    private struct BucketAggregate: Codable {
        var sumLatitude: Double
        var sumLongitude: Double
        var count: Int
        /// 一度変換できた地名のキャッシュ。あれば再変換しない(原則3 + 指摘G対策)。
        var placeName: String?
    }

    private struct AssetLocation: Codable {
        var bucketKey: String
        var latitude: Double
        var longitude: Double
    }

    private struct PersistedState: Codable {
        var buckets: [String: BucketAggregate] = [:]
        var assetLocations: [String: AssetLocation] = [:]
    }

    private var state = PersistedState()
    private var isLoaded = false

    private let fileURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("location_index.json")
    }()

    private func loadIfNeeded() {
        guard !isLoaded else { return }
        isLoaded = true
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode(PersistedState.self, from: data) else {
            return
        }
        state = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: fileURL, options: .atomic)
        // CEO判断(2026-09-04): 場所データ(自宅周辺の座標・地名を含みうる)はバックアップ対象外にする
        BackupExclusion.exclude(fileURL)
    }

    // MARK: - マス目の計算(純粋な関数。アクターの状態を使わないので nonisolated で呼び出し可能)

    /// 緯度経度からマス目のキー文字列を作る。写真の増減があっても、その写真自身の座標が
    /// 変わらない限りこの値は変わらない(=安定した識別子。指摘Fへの対応)。
    nonisolated static func bucketKey(for coordinate: CLLocationCoordinate2D) -> String {
        let latBucket = (coordinate.latitude / gridSize).rounded(.down)
        let lonBucket = (coordinate.longitude / gridSize).rounded(.down)
        return "\(latBucket)_\(lonBucket)"
    }

    // MARK: - 差分の反映(原則4の本体)

    /// 初回起動時、またはトークンが失効して差分を追えなくなった時だけ呼ぶ、全件からの再構築。
    /// 呼び出し側(LibraryIndex)がバックグラウンドスレッドで組み立てた `[PHAsset]` を渡す想定。
    func rebuildFully(assets: [PHAsset]) async -> [PlaceCluster] {
        loadIfNeeded()
        // 【指摘F対応】以前はここで `state = PersistedState()` により地名キャッシュ(placeName)ごと
        // まっさらにしていたため、しおり失効等で全件再構築が起きるたびに、最大50箇所の地名変換を
        // 1.1秒間隔で全部やり直していた(最悪2〜3分)。マス目番号(bucketKey)は写真の増減で変わらない
        // 安定した値なので、集計(合計座標・枚数)は作り直しても、既に変換済みの地名だけは
        // マス目番号をキーに引き継げる。ここで一旦地名だけ退避しておき、集計をゼロから作り直した後に
        // 同じマス目が残っていれば書き戻す。
        let previousPlaceNames: [String: String] = state.buckets.compactMapValues(\.placeName)
        state = PersistedState()
        for asset in assets {
            guard let coordinate = asset.location?.coordinate else { continue }
            addContribution(assetID: asset.localIdentifier, coordinate: coordinate)
        }
        for (key, name) in previousPlaceNames {
            guard var bucket = state.buckets[key] else { continue } // そのマス目に写真がもう無ければ引き継がない
            bucket.placeName = name
            state.buckets[key] = bucket
        }
        return await resolveClusters()
    }

    /// 前回からの差分(追加・更新・削除)だけを反映する。これが原則4の通常経路。
    /// 削除は localIdentifier だけで処理できる(位置は不要)。追加・更新は対象の PHAsset を渡す。
    func applyChanges(insertedOrUpdated: [PHAsset], deletedIdentifiers: [String]) async -> [PlaceCluster] {
        loadIfNeeded()
        for id in deletedIdentifiers {
            removeContribution(assetID: id)
        }
        for asset in insertedOrUpdated {
            if let coordinate = asset.location?.coordinate {
                addContribution(assetID: asset.localIdentifier, coordinate: coordinate)
            } else {
                // 位置情報が無い(元々無い、または編集で消えた)場合は、以前の分だけ取り消す
                removeContribution(assetID: asset.localIdentifier)
            }
        }
        return await resolveClusters()
    }

    private func addContribution(assetID: String, coordinate: CLLocationCoordinate2D) {
        // 更新イベントで同じ写真が来ることもあるため、先に古い分があれば取り消してから入れ直す
        removeContribution(assetID: assetID)
        let key = Self.bucketKey(for: coordinate)
        var bucket = state.buckets[key] ?? BucketAggregate(sumLatitude: 0, sumLongitude: 0, count: 0, placeName: nil)
        bucket.sumLatitude += coordinate.latitude
        bucket.sumLongitude += coordinate.longitude
        bucket.count += 1
        state.buckets[key] = bucket
        state.assetLocations[assetID] = AssetLocation(bucketKey: key, latitude: coordinate.latitude, longitude: coordinate.longitude)
    }

    private func removeContribution(assetID: String) {
        guard let loc = state.assetLocations.removeValue(forKey: assetID),
              var bucket = state.buckets[loc.bucketKey] else { return }
        bucket.sumLatitude -= loc.latitude
        bucket.sumLongitude -= loc.longitude
        bucket.count -= 1
        if bucket.count <= 0 {
            state.buckets.removeValue(forKey: loc.bucketKey)
        } else {
            state.buckets[loc.bucketKey] = bucket
        }
    }

    // MARK: - 一覧の組み立て・地名変換

    private struct BuiltList {
        var clusters: [PlaceCluster]
        /// 今回新しく地名変換が必要になったマス目のキー(まだ未変換のもの)
        var pendingGeocodeKeys: [String]
    }

    /// 枚数が多い順に並べ、上限50箇所までに絞る(設計書の「30〜50箇所に収束」に合わせる)。
    /// まだ地名変換していないマス目は座標そのままのラベル(仮表示)にしておき、
    /// そのマス目のキーを `pendingGeocodeKeys` に載せる(呼び出し側の resolveClusters() が
    /// これを見て実際の地名変換を行い、終わったら改めてこの関数を呼んで正式なラベルを得る)。
    private func buildClusterList() -> BuiltList {
        let top = state.buckets.sorted { $0.value.count > $1.value.count }.prefix(50)
        var clusters: [PlaceCluster] = []
        var pending: [String] = []
        for (key, bucket) in top {
            guard bucket.count > 0 else { continue }
            let centerLat = bucket.sumLatitude / Double(bucket.count)
            let centerLon = bucket.sumLongitude / Double(bucket.count)
            if let name = bucket.placeName {
                clusters.append(PlaceCluster(id: key, displayName: name, centerLatitude: centerLat, centerLongitude: centerLon, assetCount: bucket.count))
            } else {
                pending.append(key)
                let placeholder = String(format: "北緯%.1f, 東経%.1f 付近", centerLat, centerLon)
                clusters.append(PlaceCluster(id: key, displayName: placeholder, centerLatitude: centerLat, centerLongitude: centerLon, assetCount: bucket.count))
            }
        }
        return BuiltList(clusters: clusters.sorted { $0.assetCount > $1.assetCount }, pendingGeocodeKeys: pending)
    }

    /// 一覧を組み立て、まだ地名変換していないマス目だけレート制限をかけながら変換し、結果をキャッシュに保存する。
    private func resolveClusters() async -> [PlaceCluster] {
        let built = buildClusterList()
        guard !built.pendingGeocodeKeys.isEmpty else {
            persist()
            return built.clusters
        }

        for key in built.pendingGeocodeKeys {
            guard var bucket = state.buckets[key] else { continue }
            let centerLat = bucket.sumLatitude / Double(bucket.count)
            let centerLon = bucket.sumLongitude / Double(bucket.count)
            let name = await reverseGeocodeNameRateLimited(latitude: centerLat, longitude: centerLon)
            bucket.placeName = name
            state.buckets[key] = bucket
        }
        persist()
        return buildClusterList().clusters
    }

    // MARK: - 地名変換(レート制限つき。指摘G対応)

    /// CLGeocoderは短時間に連続で呼ぶとレート制限にかかり、失敗が増える(指摘G)。
    /// 呼び出し間隔を約1.1秒空け、失敗時は少し待って1回だけ再試行する。
    /// マス目ごとに一度変換すれば以後は再利用する(このメソッド自体が呼ばれるのは「新しいマス目」の時だけ)ので、
    /// 通常運用でこの間隔が問題になるのは初回起動時などまとまった数の新しい場所が一度に出た時だけ。
    private var lastGeocodeAt: Date?
    private static let minGeocodeInterval: TimeInterval = 1.1

    private func reverseGeocodeNameRateLimited(latitude: Double, longitude: Double) async -> String {
        if let lastGeocodeAt {
            let elapsed = Date().timeIntervalSince(lastGeocodeAt)
            if elapsed < Self.minGeocodeInterval {
                try? await Task.sleep(nanoseconds: UInt64((Self.minGeocodeInterval - elapsed) * 1_000_000_000))
            }
        }
        lastGeocodeAt = Date()

        if let name = await reverseGeocodeName(latitude: latitude, longitude: longitude) {
            return name
        }
        // レート制限・電波不良などの一時的な失敗を想定し、少し間を置いて1回だけ再試行する
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        lastGeocodeAt = Date()
        if let name = await reverseGeocodeName(latitude: latitude, longitude: longitude) {
            return name
        }
        return String(format: "北緯%.1f, 東経%.1f 付近", latitude, longitude)
    }

    private func reverseGeocodeName(latitude: Double, longitude: Double) async -> String? {
        let geocoder = CLGeocoder()
        let location = CLLocation(latitude: latitude, longitude: longitude)
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            if let place = placemarks.first {
                // 「市区町村」を優先し、無ければ都道府県・国の順にフォールバック
                return place.locality ?? place.administrativeArea ?? place.country ?? "不明な場所"
            }
        } catch {
            // 呼び出し側でリトライ、それでも失敗すれば座標表示にフォールバックする
        }
        return nil
    }
}
