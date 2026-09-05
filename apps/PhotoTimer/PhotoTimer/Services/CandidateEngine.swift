import Foundation
import Photos
import CoreLocation

/// スライドショーの「次の1枚」を選ぶ本体。
///
/// 【原則2:判定は選ばれた時に、流しながら行う(遅延評価)】
/// あらかじめ全件を解析してから絞り込むのではなく、
///  1. まず「日時・種類・アルバム」というメタ情報だけで候補を絞り(解析不要・一瞬)
///  2. 候補をシャッフルする
///  3. シャッフル順に一定件数だけ取り出し、必要なら(雰囲気・カテゴリ指定がある時だけ)その場で解析し、
///     「条件にどれだけ近いか」を点数化してその中で近い順に流す
/// という順番で処理する。表示は1枚ずつなので、全件を先に判定し終える必要はない。
///
/// 【2026-09-05変更(CEO判断):「満たす/満たさない」の足切りから「近い順」へ】
/// 以前は雰囲気・カテゴリの条件を1つでも満たさない写真は不採用にしていたが、
/// 「鮮やか×犬」のように該当が少ない組み合わせだと候補を使い切っても1枚も見つからず
/// 「見つかりませんでした」になってしまうことがあった(CEO実機報告)。
/// 今は不採用にする代わりに「条件にどれだけ近いか」を0〜複数の点数で表し、高い順に流す。
/// これにより「合う写真が1枚も無い」状態は原理上ほぼ起こらなくなる(何かしらは必ず流れる)。
///
/// 【遅延評価を崩さない工夫:窓(バッチ)単位での並べ替え】
/// 「近い順」を実現する素朴な方法は、全候補を先に採点してから並べ替えることだが、それでは
/// 「起動時に全走査しない」という設計4原則を破ってしまう(CEOの懸念どおり)。
/// そこでシャッフル済みの候補を`scoringBatchSize`件ずつの「窓」に区切り、窓の中だけを採点・
/// 並べ替えて流し、窓を使い切ったら次の窓を採点する、という単位で遅延評価を維持する。
/// こうすると、一度に解析する枚数は「窓のサイズ」で頭打ちになり(ライブラリの総枚数には依存しない)、
/// かつ窓の中では「近い順」が成立する。窓を小さくするほど並べ替えの効果は弱まるが1枚目までの
/// 待ちは短くなり、大きくするほど並べ替えの精度は上がるが待ちは長くなる、というトレードオフがある
/// (現在の値は報告書に記載のうえCEOに判断を仰いだ値。調整したい場合はここの定数を変えるだけでよい)。
actor CandidateEngine {

    /// 一度に採点する候補の件数(=遅延評価を保ったまま近い順に並べ替える「窓」のサイズ)。
    /// 【2026-09-05 シミュレータ検証で判明】当初20で試したところ、雰囲気・カテゴリ未指定時と違い
    /// この窓の分だけVision解析(端末内AI処理。1枚ごとに複数の判定を行う)を待ってから最初の1枚を
    /// 出す設計のため、初回(まだ何も解析していない状態)は窓のサイズがそのまま「最初の1枚が出るまでの
    /// 待ち時間」に直結すると判明(実測で20枚だと数十秒かかるケースを確認)。近い順に並べ替える効果と
    /// 最初の待ち時間の短さを両立するため6に縮小した。窓が小さいと近い順の精度(何枚の中から選ぶか)は
    /// 下がるが、窓を使い切れば自動的に次の窓の採点に進む(遅延評価は変わらず維持)ため、
    /// 「体感の待ち時間」を優先してこの値にした。
    private static let scoringBatchSize = 6

    private var shuffledAssets: [PHAsset] = []
    private var cursor = 0
    /// 現在の「窓」の中で、採点済みだがまだ表示していない候補(スコアの高い順に並んでいる)。
    private var scoredWindow: [(asset: PHAsset, score: Double)] = []
    private let settings: FilterSettings
    /// 【2026-09-04追加 → 2026-09-05拡張:先読み(プリフェッチ)を1枚→2枚先まで】
    /// 「該当が少ないカテゴリ×短い表示秒数だと、判定が表示時間に追いつかれる」という実機での
    /// CEO確認(雰囲気=雪で表示2秒設定→切り替えに2秒の時と5秒かかる時がある)を受けて追加。
    /// 以前は「今表示している1枚の表示時間が終わってから、次の1枚を探し始める」という順番だったため、
    /// 探すのに時間がかかる条件では表示時間ぴったりで待ちが発生していた。
    /// 今は「今の1枚を表示し始めた直後」に、次の1枚以降の判定を裏で始めておく。
    /// 表示時間(数秒)の間に判定が終われば、次に進む時には既に結果が出ている=待ちがゼロになる。
    /// 判定のほうが時間がかかる場合は、これまで通りその分だけ待つ(先読みは「隠せる分だけ隠す」仕組みで、
    /// 判定そのものを速くするものではない)。
    ///
    /// 【2026-09-05変更:1枚先読み→2枚先読みへ(CEO指示)】
    /// 以前は「次の1枚」だけを1つのTaskで先読みしていたが、「該当が非常に少ない条件が連続する」場合、
    /// 1枚分の先読みだけでは「今の表示時間中に次の1枚は間に合ったが、その次はまだ」という状態になりやすく、
    /// 2枚目の切り替わりでまた待ちが発生していた。そこで「捨てずに順番管理するキュー」
    /// (prefetchedQueue)を導入し、常に最大 maxPrefetchDepth 枚ぶんを裏で判定済みにしておく方式に変えた。
    /// 判定順序(近い順・原則2の遅延評価)は`findNextMatch()`が一元管理しており、キューは
    /// その結果を「表示するまでの間、順番を保ったまま一時的に保管しておく場所」に過ぎない
    /// (キューを導入したことで判定ロジック自体〔窓単位の近い順並べ替え〕は変わっていない)。
    private var prefetchedQueue: [PHAsset] = []
    /// キューを maxPrefetchDepth 件まで満たすための裏Task。存在する間は「補充中」を意味する
    /// (二重に補充が走らないようにするためのガード)。
    private var prefetchTask: Task<Void, Never>?
    /// 先読みしておく件数(現在表示中の1枚とは別に、裏で判定を済ませておく件数)。
    /// 【2026-09-05 CEO指示:1枚先読み→2〜3枚先読みへ拡張】
    /// 窓のサイズ(scoringBatchSize=6)の半分程度に留め、先読みだけで窓の判定枠を使い切って
    /// しまわないようにする値として2を選んだ(3にするとより手厚くなるが、窓の残りが1枚しか
    /// 無い状態が増え、次の窓への切り替わり頻度が上がる)。値を増減したい場合はここの定数のみでよい。
    private static let maxPrefetchDepth = 2
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
        prefetchedQueue = []
        let assets = Self.fetchBaseAssets(settings: settings)
        let filtered = assets.filter { Self.passesMetadataFilters($0, settings: settings) }
        shuffledAssets = filtered.shuffled()
        cursor = 0
        scoredWindow = []
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
    ///
    /// 【2026-09-05変更:先読みを「1枚だけ」から「キュー(最大2枚)」方式へ】
    /// 以前は「1つだけの先読みTask」の結果を待つだけだったが、今は`prefetchedQueue`に
    /// 既に判定済みの候補が溜まっていれば、それを順番(=近い順に並べた判定順)を保ったまま
    /// 取り出すだけで済む。キューが空(まだ一度も先読みが間に合っていない、または絞り込みなしで
    /// 先読み自体が不要)の場合は、これまで通りその場で判定する。
    func next() async -> PHAsset? {
        guard settings.needsImageAnalysis else {
            // 雰囲気・カテゴリの指定が無ければメタ情報の絞り込みだけで確定済み。即座に返せる。
            guard cursor < shuffledAssets.count else { return nil }
            defer { cursor += 1 }
            return shuffledAssets[cursor]
        }

        if !prefetchedQueue.isEmpty {
            return prefetchedQueue.removeFirst()
        }
        // キューが空(先読みがまだ間に合っていない最初の1枚、または候補プールを使い切った直後)。
        // その場で判定する(これまで通りの「待つしかない」経路)。
        return await findNextMatch()
    }

    /// 今表示している1枚の表示時間を使って、次以降(最大 maxPrefetchDepth 枚先まで)の判定を
    /// 裏で進めておく(先読み)。判定不要な設定(雰囲気・カテゴリどちらも指定なし)の時は
    /// next() 自体が一瞬で終わるため、先読みする意味が無い(むしろ余計なTaskを作るだけ)ので何もしない。
    /// 既に補充中(prefetchTaskが動いている)なら二重に始めない
    /// (次に表示を始めるたびに呼ばれるので、補充が終わっていれば毎回また呼ばれてキューが満杯を保つ)。
    func prefetchNext() {
        guard settings.needsImageAnalysis, prefetchTask == nil else { return }
        prefetchTask = Task {
            await self.refillPrefetchQueue()
            self.prefetchTask = nil
        }
    }

    /// キューが maxPrefetchDepth 件になるまで、`findNextMatch()`を繰り返し呼んで補充する。
    /// 【なぜ1件ずつ逐次か】`findNextMatch()`は「シャッフル済み候補の中の今の位置(cursor)」や
    /// 「窓の中の残り」といった状態を直接書き換える(このactor内の状態)ため、並行に何個も
    /// 同時実行すると同じ写真を重複して払い出す・cursorが競合するおそれがある。このメソッド自体は
    /// prefetchTaskという単一のTaskの中だけで呼ばれる(prefetchNext()のガードで二重起動を防止)ため、
    /// actor全体が単一実行(直列)であることと合わせて、逐次呼び出しで安全に順番を保てる。
    private func refillPrefetchQueue() async {
        while prefetchedQueue.count < Self.maxPrefetchDepth {
            if Task.isCancelled { return }
            guard let asset = await findNextMatch() else { return } // 候補プールを使い切った(この巡はここまで)
            prefetchedQueue.append(asset)
        }
    }

    /// 雰囲気・カテゴリの判定をしながら次の1枚を探す本体(遅延評価。原則2)。
    /// `next()`(即座に呼ばれる経路)と `prefetchNext()`(裏で先読みする経路)の両方から使う。
    ///
    /// 【2026-09-05変更】「合う/合わない」で足切りするのをやめ、窓(scoringBatchSize件)単位で
    /// 採点→並べ替え→近い順に払い出す、という動きに変えた。窓の中に候補が残っていればそこから返し、
    /// 無くなったら次の窓を採点する。候補プール全体を使い切ったら nil を返す(この時だけ「見つからない」)。
    private func findNextMatch() async -> PHAsset? {
        while true {
            // 【指摘A対応】1枚判定するたびにキャンセルされていないか確認する。
            // 以前はここに確認が無かったため、✕ボタンで閉じてもタイマーが0になっても、
            // このループは「候補を最後の1枚まで判定し終える」まで裏で走り続けてしまっていた
            // (写真が多いほど、CPUを使い切ったまま数分〜十数分止まらない状態になりうる不具合)。
            // 呼び出し元がタイマー停止・画面を閉じた時にこのTaskをcancel()するので
            // (先読み分は cancelPrefetch() 経由)、ここでその状態を毎回確認してすぐ打ち切れるようにする。
            if Task.isCancelled { return nil }

            // 窓の中に採点済みの候補が残っていれば、その中で最もスコアが高いものを返す(近い順)。
            if !scoredWindow.isEmpty {
                return scoredWindow.removeFirst().asset
            }

            // 窓が空。候補プール全体を使い切っていれば、これ以上は無い。
            guard cursor < shuffledAssets.count else { return nil }

            // 次の窓ぶん(最大 scoringBatchSize 件)をまとめて採点する。
            // ここで解析するのはこの窓の分だけで、ライブラリ全体を解析するわけではない
            // (=原則2「起動時に全走査しない」を崩さない)。
            let batchEnd = min(cursor + Self.scoringBatchSize, shuffledAssets.count)
            var newlyScored: [(asset: PHAsset, score: Double)] = []
            for i in cursor..<batchEnd {
                if Task.isCancelled { return nil }
                let asset = shuffledAssets[i]

                guard let analysis = await analyzedResult(for: asset) else {
                    // 判定できなかった(サムネイル取得失敗・Vision解析失敗)。この1枚は今回は諦めて次へ。
                    // 【指摘H対応】この「読み飛ばし」があったことを記録しておく。窓を最後まで使い切っても
                    // 候補が1枚も残らなかった場合、呼び出し側は「該当0件」ではなく「判定できなかった」を表示する。
                    hadUndeterminedCandidatesThisPass = true
                    continue
                }
                // 【2026-09-05追加:AIでのスクショ・書類らしい写真の除外(iOS 18以降)】
                // excludeScreenshots(メタ情報だけの判定)と同じ「除外」の考え方なので、近い順の
                // スコアには乗せず、この窓からはそもそも外す(mood/categoryのような「近さ」の軸ではなく、
                // excludeScreenshotsの精度を底上げする追加条件という位置づけのため)。
                if settings.strictScreenshotDetection, analysis.isUtilityImage == true {
                    continue
                }
                let score = Self.score(analysis: analysis, settings: settings)
                newlyScored.append((asset, score))
            }
            cursor = batchEnd
            // この窓の中だけを「近い順」に並べ替える(全候補ではなく窓の中だけなので計算量は小さい)。
            scoredWindow = newlyScored.sorted { $0.score > $1.score }
            // 窓の中が空(この窓は全部判定不能だった)なら、ループの先頭に戻って次の窓を試す。
        }
    }

    /// 1枚の判定結果を取得する(キャッシュ済みならそれを使い、無ければサムネイル取得→Vision解析)。
    /// 判定できなかった場合は nil(呼び出し側が hadUndeterminedCandidatesThisPass に記録する)。
    private func analyzedResult(for asset: PHAsset) async -> AssetAnalysis? {
        if let cached = await AnalysisCache.shared.analysis(for: asset.localIdentifier) {
            return cached
        }
        guard let cgImage = await Self.requestAnalysisThumbnail(asset: asset) else {
            // サムネイルが取得できなかった(端末内に無い等)。
            return nil
        }
        // サムネイル取得(await)には時間がかかることがあるため、その直後にも確認する。
        // キャンセル後にVisionでの解析(CPUを使う処理)へ進んでしまうことを防ぐ。
        if Task.isCancelled { return nil }

        guard let analysis = await ImageAnalyzer.analyze(cgImage: cgImage) else {
            // 【2026-09-04発見・修正:実機不具合「該当があるのに数枚で止まる」の調査で発覚】
            // 以前はVisionでの解析(ImageAnalyzer.analyze)が内部で失敗した場合も
            // 「カテゴリ0件」という"正常な解析結果"として扱い、AnalysisCacheに永久保存していた。
            // 解析の失敗は一時的な現象(メモリ逼迫・対応できない画像形式など)でも起こりうるため、
            // 実際には条件に合う写真(例:犬が写っている)なのに、たまたま1回解析に失敗しただけで
            // 「合わない」という誤った判定結果が固定されてしまい、その写真は二度と表示されなくなる
            // (=使うほど本当の該当数が減っていくという実害のあるバグだった)。
            // サムネイル取得失敗と同じ「判定できなかった(undetermined)」扱いにし、
            // 結果をキャッシュしない(次に選ばれた時にもう一度判定し直す機会を残す)ことで修正した。
            return nil
        }
        await AnalysisCache.shared.store(analysis, for: asset.localIdentifier)
        return analysis
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

    /// 写真が選んだ雰囲気・カテゴリに「どれだけ近いか」を点数化する(高いほど近い)。
    /// 【2026-09-05追加】以前はここで合否(Bool)を決めていたが、「合わない」を切り捨てるのをやめ、
    /// 点数として表すことで、条件にぴったり合う写真が無くても近いものから流せるようにした。
    /// 雰囲気・カテゴリの両方を選んだ場合(例:「鮮やか×犬」)は単純に加算する
    /// (CEO要望「両方の近さを合算する」への対応。各軸は選んだ時だけ0〜1の点を持ち、
    /// 選ばなかった軸は0点=順位に影響しない)。
    private static func score(analysis: AssetAnalysis, settings: FilterSettings) -> Double {
        var total = 0.0

        if !settings.selectedMoods.isEmpty {
            if let mood = analysis.mood {
                // 選んだ雰囲気の中で最も近いものとの近さを採用する(複数選んだ場合、どれか1つに
                // 近ければ十分近いとみなす。原則2の判定対象がANDではなくORの考え方に合わせている)。
                total += settings.selectedMoods.map { MoodSimilarity.similarity(mood, $0) }.max() ?? 0
            }
            // 平均色の判定自体ができなかった写真(analysis.mood == nil)は、この軸の加点が無いまま
            // (=この軸では最下位に近い扱い)進む。除外はしない(「必ず何か出す」方針のため)。
        }

        if !settings.selectedCategories.isEmpty {
            // 選んだカテゴリのうち何個が実際に写っていたか、の割合(0〜1)。
            // 複数カテゴリを選んだ場合、より多く該当する写真ほど高得点になる。
            let matchedCount = settings.selectedCategories.intersection(analysis.categories).count
            total += Double(matchedCount) / Double(settings.selectedCategories.count)
        }

        // 【2026-09-05追加:よく撮れてる度を優先(iOS 18以降)】
        // 他の軸と同じく「近い順」の考え方に沿って、足切りはせずスコアに加算するだけにする
        // (よく撮れてる度が低い写真も、他に強く条件に合うものが無ければ普通に流れる)。
        // aestheticsScoreは-1〜1の範囲なので、他の軸(0〜1)とスケールを揃えるため(x+1)/2で正規化する。
        if settings.preferHighAesthetics, let aestheticsScore = analysis.aestheticsScore {
            total += (aestheticsScore + 1) / 2
        }

        return total
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
