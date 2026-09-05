import Foundation
import Photos
import CoreLocation

/// 解析完了と時間切れのうち、先に来た結果だけをcontinuationへ返すための小さな同期箱。
private final class FirstResultBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Never>?
    private var finished = false

    init(_ continuation: CheckedContinuation<Value, Never>) { self.continuation = continuation }

    func finish(_ value: Value) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true
        let continuation = continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(returning: value)
    }
}

/// スライドショーの「次の1枚」を選ぶ本体。
///
/// 【原則2:判定は選ばれた時に、流しながら行う(遅延評価)】
/// あらかじめ全件を解析してから絞り込むのではなく、
///  1. まず「日時・種類・アルバム」というメタ情報だけで候補を絞り(解析不要・一瞬)
///  2. 候補をシャッフルする
///  3. シャッフル順に必要な分だけ解析し、条件を満たしたものを見つけ次第流す
/// という順番で処理する。表示は1枚ずつなので、全件を先に判定し終える必要はない。
///
/// 【2026-09-05変更:合格優先のストリーミング探索】
/// 6枚窓ごとに最高点を必ず返す方式では、窓に犬がいなくても「犬に一番近い非犬」が流れていた。
/// 窓を大きくしても欠陥は消えず、最初の表示待ちだけが増えるため、窓そのものを廃止した。
/// 選んだカテゴリ・雰囲気に実際に該当する候補を見つけ次第返し、該当しない写真は飛ばす。
/// **軸によって「該当しない」の緩さが異なる。**カテゴリ軸は一般分類が対象ラベルの根拠を返した
/// 近似候補まで許可する(「犬を選んだのに羊が出る」は説明できる範囲として歓迎)。
/// 雰囲気軸は近似を許可せず、選んだ雰囲気と完全一致した候補のみを返す(「暖色を選んだのに
/// 寒色が出る」はCEOが「面白くない」と判断したため。詳細はSubjectMatch.isExplainableApproximation参照)。
/// 該当が1件も無いまま全候補を一巡した場合のみ、カテゴリは根拠のある近似を最後に1回返す
/// (雰囲気はこの最後の1回も含めて近似候補が無いため、正直に「見つかりませんでした」になる)。
/// 解析済みキャッシュと2枚先読みはそのまま使うので、初回は必要な所までだけ調べ、使うほど速くなる。
actor CandidateEngine {

    private var shuffledAssets: [PHAsset] = []
    private var cursor = 0
    private var emittedExactMatch = false
    private var emittedFallback = false
    /// 犬・猫の専用検出を探す間に見つけた「一般分類にも犬/猫の根拠がある」候補。
    private var bestExplainableApproximation: (asset: PHAsset, score: Double)?
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
    private var prefetchQueue = GenerationBoundedQueue<PHAsset>(limit: 2)
    /// キューを maxPrefetchDepth 件まで満たすための裏Task。存在する間は「補充中」を意味する
    /// (二重に補充が走らないようにするためのガード)。
    private var prefetchTask: Task<Void, Never>?
    /// cancel済みの旧Taskが、後から開始した新Taskの参照をnilにしないための世代番号。
    /// 1回の探索予算で区切っただけで、まだライブラリ末尾まで見ていないことを呼び出し側へ伝える。
    private var pausedWithRemainingCandidates = false
    /// 先読みしておく件数(現在表示中の1枚とは別に、裏で判定を済ませておく件数)。
    /// 【2026-09-05 CEO指示:1枚先読み→2〜3枚先読みへ拡張】
    /// 解析が表示時間より遅い場合にも待ちを隠せる範囲として2を選んだ。
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
    func prepare() async {
        // シャッフルし直す(=候補の並びが変わる)ので、古い並びを前提に先読みしていた分は捨てる。
        prefetchQueue.advanceGeneration(clear: true)
        prefetchTask?.cancel()
        prefetchTask = nil
        let assets = Self.fetchBaseAssets(settings: settings)
        let filtered = assets.filter { Self.passesMetadataFilters($0, settings: settings) }
        // 既知の強一致→既知の説明可能近似→未判定を優先。各群は毎周shuffleし、
        // 一巡するまでは同じ写真を再利用しない。
        if !settings.selectedMoods.isEmpty || !settings.selectedCategories.isEmpty {
            let indexed = await AnalysisCache.shared.subjectCandidateIDs(settings: settings)
            let strong = Set(indexed.strong)
            let approximate = Set(indexed.approximate)
            func rank(_ id: String) -> Int { strong.contains(id) ? 0 : (approximate.contains(id) ? 1 : 2) }
            let randomized = filtered.shuffled()
            shuffledAssets = [0, 1, 2].flatMap { wantedRank in
                randomized.filter { rank($0.localIdentifier) == wantedRank }
            }
        } else {
            shuffledAssets = filtered.shuffled()
        }
        cursor = 0
        emittedExactMatch = false
        emittedFallback = false
        bestExplainableApproximation = nil
        hadUndeterminedCandidatesThisPass = false
        pausedWithRemainingCandidates = false
    }

    /// ✕で閉じた・タイマーが終わった時に呼ぶ。先読み中の判定を打ち切る。
    /// 【なぜ必要か】先読み(prefetchNext)は呼び出し元(TimerController.runSlideLoop)のTaskとは
    /// 別の独立したTaskとして動くため、呼び出し元のTaskをキャンセルしただけではこの先読みタスクは
    /// 止まらない。指摘Aで直した「閉じたらすぐ裏の処理も止まる」を、先読み追加によって
    /// 再び壊さないための後始末。
    func cancelPrefetch() {
        prefetchQueue.advanceGeneration(clear: false)
        prefetchTask?.cancel()
        prefetchTask = nil
    }

    var candidatePoolCount: Int { shuffledAssets.count }

    /// 指摘H対応: 今回のひと巡りで「判定できなかった」候補が1件でもあったか。
    var hadUndeterminedCandidates: Bool { hadUndeterminedCandidatesThisPass }
    var hasPendingSearchWork: Bool { pausedWithRemainingCandidates }

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

        if let prefetched = prefetchQueue.popFirst() {
            return prefetched
        }
        // 補充が既に走っている時は同じcursorを別経路から探索せず、その結果を短時間だけ待つ。
        // actorはawait中に他処理を進められるため、補充Taskがキューへ追加することを妨げない。
        if let runningPrefetch = prefetchTask {
            await runningPrefetch.value
            if let prefetched = prefetchQueue.popFirst() { return prefetched }
        }
        // キューが空(先読みがまだ間に合っていない最初の1枚、または候補プールを使い切った直後)。
        // その場で判定する(これまで通りの「待つしかない」経路)。
        // 【8-4対応】refillPrefetchQueue()と同じく、呼び出し時点の世代番号を渡すよう揃える。
        // 今のところ next() 実行中に prepare()/cancelPrefetch() が並行に割り込むことは無いため
        // 実害は無かったが、渡さないと「世代が変わっても気づけない」経路になってしまっていた。
        return await findNextMatch(expectedGeneration: prefetchQueue.generation)
    }

    /// 今表示している1枚の表示時間を使って、次以降(最大 maxPrefetchDepth 枚先まで)の判定を
    /// 裏で進めておく(先読み)。判定不要な設定(雰囲気・カテゴリどちらも指定なし)の時は
    /// next() 自体が一瞬で終わるため、先読みする意味が無い(むしろ余計なTaskを作るだけ)ので何もしない。
    /// 既に補充中(prefetchTaskが動いている)なら二重に始めない
    /// (次に表示を始めるたびに呼ばれるので、補充が終わっていれば毎回また呼ばれてキューが満杯を保つ)。
    func prefetchNext() {
        guard settings.needsImageAnalysis, prefetchTask == nil else { return }
        let generation = prefetchQueue.advanceGeneration(clear: false)
        prefetchTask = Task {
            await self.refillPrefetchQueue(generation: generation)
            // prepare/cancel/new taskで世代が変わっていたら、現行Taskの参照には触らない。
            if self.prefetchQueue.isCurrent(generation) {
                self.prefetchTask = nil
            }
        }
    }

    /// キューが maxPrefetchDepth 件になるまで、`findNextMatch()`を繰り返し呼んで補充する。
    /// 【なぜ1件ずつ逐次か】`findNextMatch()`は「シャッフル済み候補の中の今の位置(cursor)」や
    /// 「窓の中の残り」といった状態を直接書き換える(このactor内の状態)ため、並行に何個も
    /// 同時実行すると同じ写真を重複して払い出す・cursorが競合するおそれがある。このメソッド自体は
    /// prefetchTaskという単一のTaskの中だけで呼ばれる(prefetchNext()のガードで二重起動を防止)ため、
    /// actor全体が単一実行(直列)であることと合わせて、逐次呼び出しで安全に順番を保てる。
    private func refillPrefetchQueue(generation: UInt64) async {
        while prefetchQueue.elements.count < Self.maxPrefetchDepth {
            guard !Task.isCancelled, prefetchQueue.isCurrent(generation) else { return }
            guard let asset = await findNextMatch(expectedGeneration: generation) else { return }
            guard !Task.isCancelled, prefetchQueue.isCurrent(generation) else { return }
            _ = prefetchQueue.append(asset, generation: generation)
        }
    }

    /// 雰囲気・カテゴリの判定をしながら次の1枚を探す本体(遅延評価。原則2)。
    /// `next()`(即座に呼ばれる経路)と `prefetchNext()`(裏で先読みする経路)の両方から使う。
    ///
    /// 合格候補を見つけ次第返す。専用検出が0件でも根拠のある近似候補だけを返す。
    private func findNextMatch(expectedGeneration: UInt64? = nil) async -> PHAsset? {
        guard !Task.isCancelled, generationIsCurrent(expectedGeneration) else { return nil }
        pausedWithRemainingCandidates = false
        var budget = CandidateSearchBudget(maximumCount: 18, maximumSeconds: 0.8)
        let searchStartedAt = ContinuousClock.now
        while cursor < shuffledAssets.count {
            // 【指摘A対応】1枚判定するたびにキャンセルされていないか確認する。
            // 以前はここに確認が無かったため、✕ボタンで閉じてもタイマーが0になっても、
            // このループは「候補を最後の1枚まで判定し終える」まで裏で走り続けてしまっていた
            // (写真が多いほど、CPUを使い切ったまま数分〜十数分止まらない状態になりうる不具合)。
            // 呼び出し元がタイマー停止・画面を閉じた時にこのTaskをcancel()するので
            // (先読み分は cancelPrefetch() 経由)、ここでその状態を毎回確認してすぐ打ち切れるようにする。
            guard !Task.isCancelled, generationIsCurrent(expectedGeneration) else { return nil }

            let elapsedBefore = durationSeconds(searchStartedAt.duration(to: .now))
            guard budget.beginCandidate(elapsedSeconds: elapsedBefore) else {
                pausedWithRemainingCandidates = true
                return nil
            }

            let asset = shuffledAssets[cursor]
            cursor += 1

            // 1枚のVision処理自体が長引く場合も、この呼び出しの残り予算で打ち切る。
            let elapsed = searchStartedAt.duration(to: .now)
            let remaining = max(.zero, .milliseconds(800) - elapsed)
            guard remaining > .zero else {
                pausedWithRemainingCandidates = true
                return nil
            }
            guard let analysis = await analyzedResult(for: asset, timeout: remaining) else {
                guard !Task.isCancelled, generationIsCurrent(expectedGeneration) else { return nil }
                // 判定できなかった(サムネイル取得失敗・Vision解析失敗)。この1枚は今回は諦めて次へ。
                hadUndeterminedCandidatesThisPass = true
                if budget.isExhausted(elapsedSeconds: durationSeconds(searchStartedAt.duration(to: .now))) {
                    pausedWithRemainingCandidates = cursor < shuffledAssets.count
                    return nil
                }
                continue
            }
            guard !Task.isCancelled, generationIsCurrent(expectedGeneration) else { return nil }
            // AIでのスクショ・書類らしい写真の除外(iOS 18以降)。
            if settings.strictScreenshotDetection, analysis.isUtilityImage == true {
                if budget.isExhausted(elapsedSeconds: durationSeconds(searchStartedAt.duration(to: .now))) {
                    pausedWithRemainingCandidates = cursor < shuffledAssets.count
                    return nil
                }
                continue
            }

            let score = Self.score(analysis: analysis, settings: settings)
            if SubjectMatch.isStrong(analysis: analysis, settings: settings) {
                emittedExactMatch = true
                return asset
            }
            if SubjectMatch.isExplainableApproximation(analysis: analysis, settings: settings),
               bestExplainableApproximation == nil || score > bestExplainableApproximation!.score {
                bestExplainableApproximation = (asset, score)
            }

            // 専用検出を優先するため少しだけ先を見る。ただし短いスライド間隔で待たせないよう、
            // 18枚または0.8秒の早い方で、根拠のある近似候補へ切り替える。
            if budget.isExhausted(elapsedSeconds: durationSeconds(searchStartedAt.duration(to: .now))) {
                if let approximation = bestExplainableApproximation {
                    bestExplainableApproximation = nil
                    emittedExactMatch = true
                    return approximation.asset
                }
                pausedWithRemainingCandidates = cursor < shuffledAssets.count
                return nil
            }
        }

        guard !Task.isCancelled, generationIsCurrent(expectedGeneration) else { return nil }
        // 一巡中に該当を1枚でも返していれば、非該当候補は混ぜない。
        // 専用検出が本当に0件だった場合も、対象ラベルの根拠がある近似を一度だけ返す。
        guard !emittedExactMatch, !emittedFallback,
              let fallback = bestExplainableApproximation?.asset else { return nil }
        emittedFallback = true
        return fallback
    }

    private func generationIsCurrent(_ generation: UInt64?) -> Bool {
        guard let generation else { return true }
        return prefetchQueue.isCurrent(generation)
    }

    private func durationSeconds(_ duration: Duration) -> TimeInterval {
        let components = duration.components
        return TimeInterval(components.seconds) + TimeInterval(components.attoseconds) / 1e18
    }

    /// 解析Taskをキャンセル可能な別Taskとして走らせ、残り時間を超えたら待機だけを終了する。
    /// 解析が完了しても(打ち切られていても)結果自体はキャッシュへ保存される(8-2対応。
    /// analyzedResult(for:)参照)。
    private func analyzedResult(for asset: PHAsset, timeout: Duration) async -> AssetAnalysis? {
        await withCheckedContinuation { continuation in
            let box = FirstResultBox<AssetAnalysis?>(continuation)
            // 【8-3対応・2026-09-05】以前はタイムアウト用の待機Taskへの参照を保持しておらず、
            // 解析が予算より早く終わってもこのTaskを止める手段が無かった。そのため解析1回ごとに
            // 「使い道の無くなったsleep(timeout)だけのTask」が必ず1つ残り、1回の探索(最大18枚)で
            // 最大18個も滞留していた。参照を保持し、解析が先に終わった時点でキャンセルするようにする。
            final class TimeoutTaskBox: @unchecked Sendable {
                var task: Task<Void, Never>?
            }
            let timeoutBox = TimeoutTaskBox()
            let analysisTask = Task { [weak self] in
                guard let self else { timeoutBox.task?.cancel(); box.finish(nil); return }
                let result = await self.analyzedResult(for: asset)
                timeoutBox.task?.cancel()
                box.finish(result)
            }
            timeoutBox.task = Task {
                try? await Task.sleep(for: timeout)
                guard !Task.isCancelled else { return }
                analysisTask.cancel()
                box.finish(nil)
            }
        }
    }

}

enum SubjectMatch {
    static func isStrong(analysis: AssetAnalysis, settings: FilterSettings) -> Bool {
        if !settings.selectedMoods.isEmpty {
            guard let mood = analysis.mood, settings.selectedMoods.contains(mood) else { return false }
        }
        if !settings.selectedCategories.isEmpty {
            let matched = settings.selectedCategories.intersection(analysis.categories)
            guard !matched.isEmpty else { return false }
            // 複数選択はOR。犬・猫以外の一致、または犬・猫の専用検出が1つでもあれば即採用する。
            if !matched.subtracting([.dog, .cat]).isEmpty { return true }
            guard matched.contains(where: { (analysis.categoryConfidences?[$0] ?? 0) > 1 }) else { return false }
        }
        return true
    }

    /// 【2026-09-05修正:雰囲気軸は近似を許可しない】
    /// 以前は雰囲気の近さがMoodSimilarity(手作りの目安表)で0.4以上あれば近似候補として許可していたが、
    /// 「暖色」を選ぶと鮮やか・淡い・明るめが、「淡い」を選ぶと暖色・寒色・明るめ・モノトーンまで
    /// 通ってしまうほど緩く、CEOが実機で「暖色を選んだのに寒色が出るのは面白くない」と判断した。
    /// 一方カテゴリ軸の緩さ(「犬を選んだのに羊が出る」)は仕様として歓迎されている(理由が
    /// 説明できる範囲であれば良い、という判断)。同じ関数で軸ごとに緩さの意味が違うと分かりづらいため、
    /// 雰囲気軸は「選んだ雰囲気と完全一致するかどうか」(=isStrongと同じ条件)のみを許可するよう
    /// 引き上げた。呼び出し順としてisStrongが必ず先にチェックされ、真ならその時点で結果が確定して
    /// この関数まで来ないため、雰囲気だけを選んだ検索ではこの関数が真を返すことは実質無くなり、
    /// 「雰囲気は完全一致以外の候補を絶対に出さない」という意図どおりの動きになる
    /// (一致が1件も無ければ、この一巡では説明可能な近似も無し=正直に「見つかりませんでした」側へ回る)。
    static func isExplainableApproximation(analysis: AssetAnalysis, settings: FilterSettings) -> Bool {
        if !settings.selectedMoods.isEmpty {
            guard let mood = analysis.mood, settings.selectedMoods.contains(mood) else { return false }
        }
        if settings.selectedCategories.isEmpty {
            return !settings.selectedMoods.isEmpty
        }
        // カテゴリ軸はこれまでどおり緩いまま維持する(CEO判断:「犬を選んだのに羊が出る」は歓迎)。
        // 一般分類で15%以上の犬/猫等ラベルが実際に返った候補だけを許可する。
        // 単に窓内最高点だった無関係写真(score=0)はここを通らない。
        return settings.selectedCategories.contains { (analysis.categoryConfidences?[$0] ?? 0) >= 0.15 }
    }

}

extension CandidateEngine {
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
        // 【8-2対応・2026-09-05】以前はここで Task.isCancelled を確認し、真であれば
        // (=呼び出し元が0.8秒/18枚の予算切れで既に諦めた後だった場合)せっかく完了した解析結果を
        // 保存せずに捨てていた。探索予算は「候補を進めるほど残り時間が短くなる」ため、
        // 窓の後半にある写真ほど打ち切られやすく、この書き方だと後半の写真がいつまで経っても
        // キャッシュされない偏りが生まれてしまう。Vision解析(重い処理)自体は既に終わっている
        // ので、その成果を捨てる理由はなく、キャンセル済みかどうかに関わらず保存する
        // (「新しくVision解析を始めない」「時間切れTaskをcancelする」という既存の安全策=
        // 上のガード〔サムネイル取得直後の isCancelled 確認〕はそのまま残しており、ここで
        // 変えたのは「既に終わった仕事の後始末」だけ)。
        await AnalysisCache.shared.store(analysis, for: asset.localIdentifier)
        if Task.isCancelled { return nil }
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

        let hasAlbumRestriction = !settings.selectedAlbumIDs.isEmpty
        let hasListRestriction = !settings.selectedCustomListIDs.isEmpty

        if !hasAlbumRestriction && !hasListRestriction {
            appendAssets(from: PHAsset.fetchAssets(with: options))
        } else {
            // 【指摘F関連】選んだアルバムが写真アプリ側で削除されていた場合、ここでは
            // 単にそのIDが見つからず何も追加されない(=黙って0枚扱い)。ユーザーが
            // 「選んだはずのアルバムが消えている」ことに気づいて解除できるようにする対応は
            // FilterOptionsView側(表示できるアルバム一覧と選択IDを突き合わせるUI)で行っている。
            if hasAlbumRestriction {
                let collections = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: Array(settings.selectedAlbumIDs), options: nil)
                collections.enumerateObjects { collection, _, _ in
                    appendAssets(from: PHAsset.fetchAssets(in: collection, options: options))
                }
            }
            // 【2026-09-05追加:自作リスト】アルバムと同じ「メタ情報だけで絞れる」条件として扱う。
            // 両方選んでいる場合は足し算(アルバムの中の写真 ∪ リストの中の写真)。
            // リストが指す写真が後で削除されていた場合、fetchAssets(withLocalIdentifiers:)は
            // 単にその分を返さないだけで、落ちたり例外になったりしない(絶対制約どおり)。
            if hasListRestriction {
                let listAssetIDs = Set(
                    CustomPhotoListStore.load()
                        .filter { settings.selectedCustomListIDs.contains($0.id) }
                        .flatMap(\.assetLocalIdentifiers)
                )
                if !listAssetIDs.isEmpty {
                    appendAssets(from: PHAsset.fetchAssets(withLocalIdentifiers: Array(listAssetIDs), options: options))
                }
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
                // 【2026-09-05注記】isExplainableApproximationが雰囲気の近似を許可しなくなったため、
                // この加点が「説明可能な近似」の採用可否を左右することは今は無い(完全一致の場合は
                // isStrongが先に確定させる)。将来また雰囲気の近似順位付けを使う時のために残している。
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
