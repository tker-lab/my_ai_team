import Foundation
import Photos

/// フィルタ画面で使う「補助データ」(アルバム一覧・場所の選択肢・カテゴリの並び順)をまとめて持つ。
///
/// これらはすべてバックグラウンドで組み立て、タイマー画面はこれの完成を待たずに使える状態にする
/// (「アプリを開いたら即タイマーが使える」を満たすため)。未完成の間は各セクションに
/// 「読み込み中」を出しつつ、フィルタなし=全件対象のタイマーはすぐ押せる。
@MainActor
final class LibraryIndex: ObservableObject {
    static let shared = LibraryIndex()

    @Published private(set) var albums: [PhotoLibraryManager.AlbumInfo] = []
    @Published private(set) var placeClusters: [PlaceCluster] = PlaceClusterStore.load()
    @Published private(set) var isBuildingPlaces = false
    @Published private(set) var isSamplingCategories = false
    /// サンプル解析で多かった順に並べたカテゴリ一覧。まだ解析が終わっていない間は定義順(固定リストそのまま)を使う。
    @Published private(set) var orderedCategories: [CategoryTag] = CategoryTag.allCases

    private init() {}

    /// 起動時に1回呼ぶ。原則4により「差分があった時だけ」場所・カテゴリ順を作り直す。
    func refreshIfNeeded() {
        let manager = PhotoLibraryManager.shared
        guard manager.isUsable else { return }

        // アルバム一覧はメタ情報の取得だけなので毎回さっと更新して問題ない
        albums = manager.fetchAlbums()

        let hasChanges = manager.checkForChangesSinceLastLaunch()
        let hasExistingPlaces = !placeClusters.isEmpty

        // 「差分がある」または「まだ一度も場所クラスタを作っていない」時だけバックグラウンドで作る
        if hasChanges || !hasExistingPlaces {
            Task { await buildPlaceClusters() }
        }
        if hasChanges || UserDefaults.standard.object(forKey: "PhotoTimer.HasSampledCategories") == nil {
            Task { await sampleCategories() }
        }
    }

    private func buildPlaceClusters() async {
        isBuildingPlaces = true
        defer { isBuildingPlaces = false }

        let options = PHFetchOptions()
        let fetchResult = PHAsset.fetchAssets(with: options)
        var assets: [PHAsset] = []
        assets.reserveCapacity(fetchResult.count)
        fetchResult.enumerateObjects { asset, _, _ in
            if asset.location != nil { assets.append(asset) }
        }

        let clusters = await LocationClusterer.buildClusters(from: assets)
        placeClusters = clusters
        PlaceClusterStore.save(clusters)
    }

    private func sampleCategories() async {
        isSamplingCategories = true
        defer { isSamplingCategories = false }

        let fetchResult = PHAsset.fetchAssets(with: nil)
        let counts = await CategorySampler.sampleCategoryCounts(allAssets: fetchResult)
        UserDefaults.standard.set(true, forKey: "PhotoTimer.HasSampledCategories")

        // 出現回数が多い順。0件のものも末尾に残す(隠さない。原則:サンプル解析は並べ替えにのみ使う)
        orderedCategories = CategoryTag.allCases.sorted { (counts[$0] ?? 0) > (counts[$1] ?? 0) }
    }
}
