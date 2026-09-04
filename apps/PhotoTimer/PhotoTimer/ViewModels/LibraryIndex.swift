import Foundation
import Photos

/// フィルタ画面で使う「補助データ」(アルバム一覧・場所の選択肢・カテゴリの並び順)をまとめて持つ。
///
/// これらはすべてバックグラウンドで組み立て、タイマー画面はこれの完成を待たずに使える状態にする
/// (「アプリを開いたら即タイマーが使える」を満たすため)。未完成の間は各セクションに
/// 「読み込み中」を出しつつ、フィルタなし=全件対象のタイマーはすぐ押せる。
///
/// 【2026-09-04修正(指摘A対応)】
/// 修正前は `Task { await buildPlaceClusters() }` のように書かれていたが、`LibraryIndex` 自体が
/// `@MainActor` クラスだったため、この `Task` の中身は実際には画面スレッド(MainActor)上で
/// 実行され続けていた(`Task{}` は「別スレッドで動く」ことを保証しない。呼び出し元のアクターを
/// 引き継ぐ)。今回、実際の処理(PHAssetの列挙・Visionでの解析など)はすべて `nonisolated` な
/// メソッド+ `Task.detached` に切り出し、確実に画面スレッドの外で動くようにした。
/// `@Published` プロパティへの反映だけ、その都度 `MainActor.run` で画面スレッドに戻している。
@MainActor
final class LibraryIndex: ObservableObject {
    static let shared = LibraryIndex()

    @Published private(set) var albums: [PhotoLibraryManager.AlbumInfo] = []
    @Published private(set) var placeClusters: [PlaceCluster] = PlaceClusterStore.load()
    @Published private(set) var isBuildingPlaces = false
    @Published private(set) var isSamplingCategories = false
    /// サンプル解析で多かった順に並べたカテゴリ一覧。まだ解析が終わっていない間は定義順(固定リストそのまま)を使う。
    @Published private(set) var orderedCategories: [CategoryTag] = CategoryTag.allCases

    /// 前回のカテゴリ並べ替え対象日時の保存キー(サンプル解析を毎回やり直さないための目印)。
    /// 定数なので nonisolated にして、バックグラウンドの nonisolated メソッドからも参照できるようにする。
    nonisolated private static let hasSampledCategoriesKey = "PhotoTimer.HasSampledCategories"

    /// 【指摘C対応】「場所の全走査(rebuildPlacesFully)を1回でも完了させたか」の目印。
    /// 以前は `placeClusters.isEmpty` で「まだ全走査していない」を判定していたが、これだと
    /// 「位置情報付きの写真が1枚も無いユーザー」は全走査してもクラスタが0件のままなので
    /// 区別が付かず、変化が無い起動のたびに毎回全走査(絶対制約「起動時に全走査しない」に抵触)して
    /// いた。この目印を使い、「まだ1度もやっていない」と「やった結果0件だった(確定した空)」を
    /// はっきり分けることで、後者では起動のたびの全走査を起こさないようにする。
    nonisolated private static let hasCompletedPlaceScanKey = "PhotoTimer.HasCompletedPlaceScan"

    /// 画面(ContentView)は onAppear のたびに refreshIfNeeded() を呼ぶことがあるため、
    /// バックグラウンド処理が重複して走らないようにする簡単なガード。
    private var isRefreshing = false

    private init() {}

    /// 起動時(および画面再表示時)に呼ぶ。原則4により「差分があった時だけ」場所・カテゴリ順を作り直す。
    /// この関数自体はMainActor上で即座に返り、重い処理はバックグラウンドに委ねる。
    func refreshIfNeeded() {
        guard !isRefreshing else { return }
        isRefreshing = true
        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            await self.performRefresh()
            await MainActor.run { self.isRefreshing = false }
        }
    }

    /// 実際の処理本体。`nonisolated` なので `Task.detached` から呼んでも画面スレッドを使わない。
    private nonisolated func performRefresh() async {
        // PhotoLibraryManager.shared 自体はMainActor隔離のプロパティなので、参照を取り出す瞬間だけ
        // MainActorへ一度ホップする(一瞬で戻るので体感的なコストはない)。以降はこの参照(manager)経由で
        // nonisolatedなメソッドを呼ぶだけなので、重い処理自体は画面スレッドに乗らない。
        let manager = await MainActor.run { PhotoLibraryManager.shared }

        // アルバム一覧の取得(件数の問い合わせを含むため、画面スレッドでは行わない。指摘A対応)
        let albums = manager.fetchAlbums()
        await MainActor.run { self.albums = albums }

        // 前回からの差分だけを確認する(原則4の本体)
        let changeSet = manager.checkForChangesSinceLastLaunch()
        // 【指摘C対応】「場所の選択肢が空かどうか」ではなく「全走査を1度でも完了させたか」で判定する。
        // 前者だと位置情報付きの写真が1枚も無いユーザーは永遠に「まだ」判定になり、変化が無い起動でも
        // 毎回全走査してしまう。
        let hasCompletedScanBefore = UserDefaults.standard.bool(forKey: Self.hasCompletedPlaceScanKey)

        if changeSet.requiresFullRebuild {
            // 初回起動、またはしおりが失効した時だけ全件を対象にする(原則4の例外)
            await rebuildPlacesFully()
        } else if changeSet.hasAnyChange {
            // 通常経路: 変化のあった写真だけを対象にした軽い問い合わせで差分を反映する
            await applyPlaceChanges(changeSet)
        } else if !hasCompletedScanBefore {
            // 何らかの事情でまだ一度も全走査を終えていない場合のみの保険(通常は起きない)。
            await rebuildPlacesFully()
        }

        // 削除された写真の解析結果(色・カテゴリ)をキャッシュから取り除く(軽微な指摘対応)。
        // ここで新たに写真を探しにいくコストは無く、上で取得済みの差分をそのまま渡すだけ。
        if !changeSet.deletedIdentifiers.isEmpty {
            await AnalysisCache.shared.removeAnalyses(for: changeSet.deletedIdentifiers)
        }

        // 【指摘J対応】差分を実際に反映し終えた「ここ」で初めて、しおりを保存する。
        // ここより前(checkForChangesSinceLastLaunch()の直後)で保存してしまうと、保存した直後に
        // アプリが終了した場合、上の反映処理(rebuildPlacesFully/applyPlaceChanges等)が
        // 実行されなかったのに「もう反映済み」という記録だけが残り、その分の差分を次回二度と
        // 拾えなくなってしまう。
        if let pendingToken = changeSet.pendingToken {
            manager.commitToken(pendingToken)
        }

        let hasSampledBefore = UserDefaults.standard.object(forKey: Self.hasSampledCategoriesKey) != nil
        if changeSet.hasAnyChange || !hasSampledBefore {
            await sampleCategories()
        }
    }

    /// 全件からの場所クラスタ再構築(初回起動時・しおり失効時のみ)。
    private nonisolated func rebuildPlacesFully() async {
        await MainActor.run { self.isBuildingPlaces = true }

        let fetchResult = PHAsset.fetchAssets(with: nil)
        var assets: [PHAsset] = []
        assets.reserveCapacity(fetchResult.count)
        fetchResult.enumerateObjects { asset, _, _ in
            if asset.location != nil { assets.append(asset) }
        }

        let clusters = await LocationClusterer.shared.rebuildFully(assets: assets)
        PlaceClusterStore.save(clusters)
        // 全走査が完了したことを記録する(指摘C対応)。クラスタが0件(=位置情報付きの写真が無かった)
        // 場合でも「完了した」ことに変わりはないので、結果によらずここで記録する。
        UserDefaults.standard.set(true, forKey: Self.hasCompletedPlaceScanKey)
        await MainActor.run {
            self.placeClusters = clusters
            self.isBuildingPlaces = false
        }
    }

    /// 差分だけを反映した場所クラスタの更新(通常経路。原則4)。
    private nonisolated func applyPlaceChanges(_ changeSet: PhotoLibraryManager.ChangeSet) async {
        await MainActor.run { self.isBuildingPlaces = true }

        // 変化のあった写真だけを対象にした軽い問い合わせ(全件スキャンではない)
        var insertedOrUpdatedAssets: [PHAsset] = []
        if !changeSet.insertedOrUpdatedIdentifiers.isEmpty {
            let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: changeSet.insertedOrUpdatedIdentifiers, options: nil)
            insertedOrUpdatedAssets.reserveCapacity(fetchResult.count)
            fetchResult.enumerateObjects { asset, _, _ in insertedOrUpdatedAssets.append(asset) }
        }

        let clusters = await LocationClusterer.shared.applyChanges(
            insertedOrUpdated: insertedOrUpdatedAssets,
            deletedIdentifiers: changeSet.deletedIdentifiers
        )
        PlaceClusterStore.save(clusters)
        await MainActor.run {
            self.placeClusters = clusters
            self.isBuildingPlaces = false
        }
    }

    private nonisolated func sampleCategories() async {
        await MainActor.run { self.isSamplingCategories = true }

        let fetchResult = PHAsset.fetchAssets(with: nil)
        let counts = await CategorySampler.sampleCategoryCounts(allAssets: fetchResult)
        UserDefaults.standard.set(true, forKey: Self.hasSampledCategoriesKey)

        // 出現回数が多い順。0件のものも末尾に残す(隠さない。原則:サンプル解析は並べ替えにのみ使う)。
        // 同数(特に0件同士)の場合は、CategoryTagの定義順(常に同じ)を並び順として使う。
        // これを指定しないと、標準ライブラリのsortedが同順位の要素の並びを保証しないため、
        // 実行するたびに0件カテゴリ同士の表示順が変わってしまう不具合があった。
        let indexed = Array(CategoryTag.allCases.enumerated())
        let ordered = indexed
            .sorted { lhs, rhs in
                let lhsCount = counts[lhs.element] ?? 0
                let rhsCount = counts[rhs.element] ?? 0
                if lhsCount != rhsCount { return lhsCount > rhsCount }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
        await MainActor.run {
            self.orderedCategories = ordered
            self.isSamplingCategories = false
        }
    }
}
