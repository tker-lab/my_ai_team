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
    /// 【2026-09-04追加:先読み(プリフェッチ)】
    /// 「該当が少ないカテゴリ×短い表示秒数だと、判定が表示時間に追いつかれる」という実機での
    /// CEO確認(雰囲気=雪で表示2秒設定→切り替えに2秒の時と5秒かかる時がある)を受けて追加。
    /// 以前は「今表示している1枚の表示時間が終わってから、次の1枚を探し始める」という順番だったため、
    /// 探すのに時間がかかる条件では表示時間ぴったりで待ちが発生していた。
    /// 今は「今の1枚を表示し始めた直後」に、次の1枚の判定をこのTaskとして裏で始めておく。
    /// 表示時間(数秒)の間に判定が終われば、次に進む時には既に結果が出ている=待ちがゼロになる。
    /// 判定のほうが時間がかかる場合は、これまで通りその分だけ待つ(先読みは「隠せる分だけ隠す」仕組みで、
    /// 判定そのものを速くするものではない)。
    private var prefetchTask: Task<PHAsset?, Never>?
    /// 【指摘H対応】雰囲気・カテゴリの判定用サムネイルが取得できず、「合うかどうか判定できなかった」
    /// 候補が今回のひと巡り(prepare()〜候補を使い切るまで)で1件でもあったか。
    /// 「iPhoneのストレージを最適化」設定を使っていると、端末内に無い写真が多くを占めることがあり、
    /// (判定用サムネイルは isNetworkAccessAllowed=false のためiCloudへは取りに行かない設計)
    /// 以前はこれらが黙って読み飛ばされ、実際は「判定できなかった」だけなのに「条件に合う写真が
    /// 見つかりませんでした」と表示されてしまっていた。この値を呼び出し側(TimerController)が
    /// 参照し、正しい理由(loadFailed)を出し分けられるようにする。
    private var hadUndeterminedCandidatesThisPass = false

    init(settings: FilterSettings, placeClusters: [PlaceCluster]) {
        self.settings = settings
        // placeClusters は以前「場所」の一致判定(距離計算)に使っていたが、2026-09-04の修正で
        // 「同じマス目(bucketKey)かどうか」で厳密に判定する方式に変えたため、クラスタの実体
        // (中心座標など)はもう不要になった。呼び出し側(TimerController等)のAPIを変えずに済むよう
        // 引数はそのまま受け取るが、ここでは使わない。
    }

    /// 候補プールを準備する(原則1:選択肢は固定/自動生成済みのものだけを使い、ここでは絞り込みの実行のみ)
    func prepare() {
        // シャッフルし直す(=候補の並びが変わる)ので、古い並びを前提に先読みしていた分は捨てる。
        prefetchTask?.cancel()
        prefetchTask = nil
        let assets = Self.fetchBaseAssets(settings: settings)
        let filtered = assets.filter { Self.passesMetadataFilters($0, settings: settings) }
        shuffledAssets = filtered.shuffled()
        cursor = 0
        hadUndeterminedCandidatesThisPass = false
    }

    /// ✕で閉じた・タイマーが終わった時に呼ぶ。先読み中の判定を打ち切る。
    /// 【なぜ必要か】先読み(prefetchNext)は呼び出し元(TimerController.runSlideLoop)のTaskとは
    /// 別の独立したTaskとして動くため、呼び出し元のTaskをキャンセルしただけではこの先読みタスクは
    /// 止まらない。指摘Aで直した「閉じたらすぐ裏の処理も止まる」を、先読み追加によって
    /// 再び壊さないための後始末。
    func cancelPrefetch() {
        prefetchTask?.cancel()
        prefetchTask = nil
    }

    var candidatePoolCount: Int { shuffledAssets.count }

    /// 指摘H対応: 今回のひと巡りで「判定できなかった」候補が1件でもあったか。
    var hadUndeterminedCandidates: Bool { hadUndeterminedCandidatesThisPass }

    /// 次に表示する1枚を返す。無ければ nil(=「条件に合う写真が見つかりませんでした」)。
    func next() async -> PHAsset? {
        guard settings.needsImageAnalysis else {
            // 雰囲気・カテゴリの指定が無ければメタ情報の絞り込みだけで確定済み。即座に返せる。
            guard cursor < shuffledAssets.count else { return nil }
            defer { cursor += 1 }
            return shuffledAssets[cursor]
        }

        // 先読み(prefetchNext)が既に始まっていれば、その結果を待つだけでよい
        // (表示時間中に判定が終わっていれば、ここは実質即座に返る)。
        if let task = prefetchTask {
            prefetchTask = nil
            return await task.value
        }
        return await findNextMatch()
    }

    /// 今表示している1枚の表示時間を使って、次の1枚の判定を裏で始めておく(先読み)。
    /// 判定不要な設定(雰囲気・カテゴリどちらも指定なし)の時は next() 自体が一瞬で終わるため、
    /// 先読みする意味が無い(むしろ余計なTaskを作るだけ)ので何もしない。
    /// 既に先読み中なら二重に始めない。
    func prefetchNext() {
        guard settings.needsImageAnalysis, prefetchTask == nil else { return }
        prefetchTask = Task {
            await self.findNextMatch()
        }
    }

    /// 雰囲気・カテゴリの判定をしながら次の1枚を探す本体(遅延評価。原則2)。
    /// `next()`(即座に呼ばれる経路)と `prefetchNext()`(裏で先読みする経路)の両方から使う。
    private func findNextMatch() async -> PHAsset? {
        while cursor < shuffledAssets.count {
            // 【指摘A対応】1枚判定するたびにキャンセルされていないか確認する。
            // 以前はここに確認が無かったため、✕ボタンで閉じてもタイマーが0になっても、
            // このwhileループは「候補を最後の1枚まで判定し終える」まで裏で走り続けてしまっていた
            // (写真が多いほど、CPUを使い切ったまま数分〜十数分止まらない状態になりうる不具合)。
            // 呼び出し元がタイマー停止・画面を閉じた時にこのTaskをcancel()するので
            // (先読み分は cancelPrefetch() 経由)、ここでその状態を毎回確認してすぐ打ち切れるようにする。
            if Task.isCancelled { return nil }

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
                // 【指摘H対応】この「読み飛ばし」があったことを記録しておく。全部読み飛ばして
                // 候補を使い切った場合、呼び出し側は「該当0件」ではなく「判定できなかった」を表示する。
                hadUndeterminedCandidatesThisPass = true
                continue
            }
            // サムネイル取得(await)には時間がかかることがあるため、その直後にも確認する。
            // キャンセル後にVisionでの解析(CPUを使う処理)へ進んでしまうことを防ぐ。
            if Task.isCancelled { return nil }

            guard let analysis = ImageAnalyzer.analyze(cgImage: cgImage) else {
                // 【2026-09-04発見・修正:実機不具合「該当があるのに数枚で止まる」の調査で発覚】
                // 以前はVisionでの解析(ImageAnalyzer.analyze)が内部で失敗した場合も
                // 「カテゴリ0件」という"正常な解析結果"として扱い、AnalysisCacheに永久保存していた。
                // 解析の失敗は一時的な現象(メモリ逼迫・対応できない画像形式など)でも起こりうるため、
                // 実際には条件に合う写真(例:犬が写っている)なのに、たまたま1回解析に失敗しただけで
                // 「合わない」という誤った判定結果が固定されてしまい、その写真は二度と表示されなくなる
                // (=使うほど本当の該当数が減っていくという実害のあるバグだった)。
                // サムネイル取得失敗と同じ「判定できなかった(undetermined)」扱いにし、
                // 結果をキャッシュしない(次に選ばれた時にもう一度判定し直す機会を残す)ことで修正した。
                hadUndeterminedCandidatesThisPass = true
                continue
            }
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
            // 【指摘F関連】選んだアルバムが写真アプリ側で削除されていた場合、ここでは
            // 単にそのIDが見つからず何も追加されない(=黙って0枚扱い)。ユーザーが
            // 「選んだはずのアルバムが消えている」ことに気づいて解除できるようにする対応は
            // FilterOptionsView側(表示できるアルバム一覧と選択IDを突き合わせるUI)で行っている。
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
    private static func passesMetadataFilters(_ asset: PHAsset, settings: FilterSettings) -> Bool {
        if settings.excludeScreenshots, asset.mediaSubtypes.contains(.photoScreenshot) {
            return false
        }
        if settings.mediaType == .livePhoto, !asset.mediaSubtypes.contains(.photoLive) {
            return false
        }
        if !settings.selectedPlaceIDs.isEmpty {
            guard let coordinate = asset.location?.coordinate else { return false }
            // 「場所」クラスタと同じマス目(bucketKey)に属するかで判定する(指摘H対応)。
            // 以前は「クラスタ中心から半径◯km以内」という距離判定だったが、クラスタを作る時の
            // マス目のサイズ(約5.5km四方)と半径(6km)がズレていて隣のマスまで混ざっていた。
            // 同じマス目かどうかという厳密な判定にすれば、ズレそのものが原理的に発生しない。
            let key = LocationClusterer.bucketKey(for: coordinate)
            if !settings.selectedPlaceIDs.contains(key) { return false }
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
