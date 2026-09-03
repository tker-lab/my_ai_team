import Foundation
import Photos
import CoreLocation

/// スライドショーの「次の1枚」を選ぶ本体。
///
/// 【原則2:判定は選ばれた時に、流しながら行う(遅延評価)】
/// あらかじめ全件を解析してから絞り込むのではなく、
///  1. まず「日時・種類・アルバム」というメタ情報だけで候補を絞り(解析不要・一瞬)
///  2. 候補をシャッフルする
///  3. シャッフル順に1枚ずつ取り出し、必要なら(雰囲気・カテゴリ指定がある時だけ)その場で解析し、
///     条件に合えば採用・合わなければ次へ進む
/// という順番で処理する。表示は1枚ずつなので、全件を先に判定し終える必要はない。
actor CandidateEngine {

    private var shuffledAssets: [PHAsset] = []
    private var cursor = 0
    private let settings: FilterSettings
    private let placeClusters: [PlaceCluster]
    /// 選択された場所クラスタとみなす半径(クラスタ生成時のマス目よりひと回り広めに取る)
    private let placeMatchRadiusMeters: CLLocationDistance = 6000

    init(settings: FilterSettings, placeClusters: [PlaceCluster]) {
        self.settings = settings
        self.placeClusters = placeClusters
    }

    /// 候補プールを準備する(原則1:選択肢は固定/自動生成済みのものだけを使い、ここでは絞り込みの実行のみ)
    func prepare() {
        let assets = Self.fetchBaseAssets(settings: settings)
        let filtered = assets.filter { Self.passesMetadataFilters($0, settings: settings, placeClusters: placeClusters, radius: placeMatchRadiusMeters) }
        shuffledAssets = filtered.shuffled()
        cursor = 0
    }

    var candidatePoolCount: Int { shuffledAssets.count }

    /// 次に表示する1枚を返す。無ければ nil(=「条件に合う写真が見つかりませんでした」)。
    func next() async -> PHAsset? {
        guard settings.needsImageAnalysis else {
            // 雰囲気・カテゴリの指定が無ければメタ情報の絞り込みだけで確定済み。即座に返せる。
            guard cursor < shuffledAssets.count else { return nil }
            defer { cursor += 1 }
            return shuffledAssets[cursor]
        }

        while cursor < shuffledAssets.count {
            let asset = shuffledAssets[cursor]
            cursor += 1

            if let analysis = await AnalysisCache.shared.analysis(for: asset.localIdentifier) {
                if Self.matches(analysis: analysis, settings: settings) {
                    return asset
                }
                continue
            }

            guard let cgImage = await Self.requestAnalysisThumbnail(asset: asset) else {
                // サムネイルが取得できなかった(端末内に無い等)場合は判定不能として次へ。落とさず読み飛ばすだけ。
                continue
            }
            let analysis = ImageAnalyzer.analyze(cgImage: cgImage)
            await AnalysisCache.shared.store(analysis, for: asset.localIdentifier)
            if Self.matches(analysis: analysis, settings: settings) {
                return asset
            }
        }
        return nil
    }

    // MARK: - メタ情報での絞り込み(解析不要・原則2の「事前にできる分」)

    private static func fetchBaseAssets(settings: FilterSettings) -> [PHAsset] {
        let options = PHFetchOptions()
        // 条件が何も無い時は predicate を設定しない(nilのまま=絞り込みなしを意味する)。
        // PHFetchOptions.predicate は「真偽値だけの定数predicate」(例: NSPredicate(value: true))を
        // 受け付けず例外を投げるため、"条件なし"を表したい時は代入自体を省略する必要がある。
        if let predicate = buildMetadataPredicate(settings: settings) {
            options.predicate = predicate
        }

        var result: [PHAsset] = []
        var seen = Set<String>()

        func appendAssets(from fetchResult: PHFetchResult<PHAsset>) {
            fetchResult.enumerateObjects { asset, _, _ in
                if seen.insert(asset.localIdentifier).inserted {
                    result.append(asset)
                }
            }
        }

        if settings.selectedAlbumIDs.isEmpty {
            appendAssets(from: PHAsset.fetchAssets(with: options))
        } else {
            let collections = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: Array(settings.selectedAlbumIDs), options: nil)
            collections.enumerateObjects { collection, _, _ in
                appendAssets(from: PHAsset.fetchAssets(in: collection, options: options))
            }
        }
        return result
    }

    /// 日時・メディア種類はPhotosフレームワーク側の predicate(=OSのインデックスを使った絞り込み)に載せ、
    /// 自前でループを回さずに済ませる。
    /// 条件が1つも無ければ nil を返す(呼び出し側で predicate への代入自体を省略するため)。
    private static func buildMetadataPredicate(settings: FilterSettings) -> NSPredicate? {
        var predicates: [NSPredicate] = []

        switch settings.dateRange {
        case .all:
            break
        case .thisYear:
            if let start = Calendar.current.date(from: Calendar.current.dateComponents([.year], from: Date())) {
                predicates.append(NSPredicate(format: "creationDate >= %@", start as NSDate))
            }
        case .thisMonth:
            if let start = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: Date())) {
                predicates.append(NSPredicate(format: "creationDate >= %@", start as NSDate))
            }
        case .custom(let from, let to):
            predicates.append(NSPredicate(format: "creationDate >= %@ AND creationDate <= %@", from as NSDate, to as NSDate))
        }

        switch settings.mediaType {
        case .all:
            break
        case .photo, .livePhoto:
            predicates.append(NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue))
        case .video:
            predicates.append(NSPredicate(format: "mediaType == %d", PHAssetMediaType.video.rawValue))
        }

        guard !predicates.isEmpty else { return nil }
        return NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
    }

    /// mediaSubtype(スクリーンショット・Live Photo)や位置情報は、Photos側のpredicateに頼らず
    /// 取得済みのPHAssetプロパティをその場でチェックするだけ(解析ではなくメタ情報の参照なので原則2の対象外)。
    private static func passesMetadataFilters(_ asset: PHAsset, settings: FilterSettings, placeClusters: [PlaceCluster], radius: CLLocationDistance) -> Bool {
        if settings.excludeScreenshots, asset.mediaSubtypes.contains(.photoScreenshot) {
            return false
        }
        if settings.mediaType == .livePhoto, !asset.mediaSubtypes.contains(.photoLive) {
            return false
        }
        if !settings.selectedPlaceIDs.isEmpty {
            guard let location = asset.location else { return false }
            let selectedClusters = placeClusters.filter { settings.selectedPlaceIDs.contains($0.id) }
            let matchesAnyCluster = selectedClusters.contains { cluster in
                location.distance(from: cluster.location) <= radius
            }
            if !matchesAnyCluster { return false }
        }
        return true
    }

    private static func matches(analysis: AssetAnalysis, settings: FilterSettings) -> Bool {
        if !settings.selectedMoods.isEmpty {
            guard let mood = analysis.mood, settings.selectedMoods.contains(mood) else { return false }
        }
        if !settings.selectedCategories.isEmpty {
            let hasMatch = analysis.categories.contains { settings.selectedCategories.contains($0) }
            if !hasMatch { return false }
        }
        return true
    }

    // MARK: - 判定用サムネイル取得

    private static func requestAnalysisThumbnail(asset: PHAsset) async -> CGImage? {
        let options = PHImageRequestOptions()
        options.deliveryMode = .fastFormat
        options.isNetworkAccessAllowed = false // 判定用の縮小画像は端末内にあるものだけで十分(iCloudへは取りに行かない)
        options.resizeMode = .fast

        return await withCheckedContinuation { continuation in
            PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width: 256, height: 256), contentMode: .aspectFill, options: options) { image, _ in
                continuation.resume(returning: image?.cgImage)
            }
        }
    }
}
