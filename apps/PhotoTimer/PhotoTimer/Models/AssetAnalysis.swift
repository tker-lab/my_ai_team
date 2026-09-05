import Foundation

/// 1枚の写真・動画を解析した結果。localIdentifier(写真ライブラリ内でのその写真固有のID)をキーに
/// 端末内DBへ蓄積する(原則3: 同じ写真は二度と解析しない)。
struct AssetAnalysis: Codable {
    var mood: MoodTag?
    var categories: [CategoryTag]
    /// カテゴリごとの根拠の強さ。犬・猫の専用検出は 1.0+信頼度、一般分類は0〜1の信頼度。
    /// nilは旧キャッシュとの互換用で、analyzerVersion更新により順次再解析される。
    var categoryConfidences: [CategoryTag: Double]?
    /// 「よく撮れてる度」(2026-09-05追加。CEO指示によりMVPから復活)。
    /// Visionの CalculateImageAestheticsScoresRequest(iOS 18以降専用)による-1〜1のスコア
    /// (高いほど「よく撮れている」)。iOS 17以下の端末では判定できないため常にnil。
    var aestheticsScore: Double?
    /// 「実用目的の画像(スクリーンショット・書類・レシート・メモ等)らしいか」のフラグ。
    /// 同じくiOS 18以降でのみ判定できる(iOS 17以下では常にnil)。
    /// MVPの「スクリーンショットを除く」モードは撮影時のメタ情報(mediaSubtypes)だけを見ているため、
    /// カメラで書類を撮っただけの「スクショではないが実用目的の写真」までは除けなかった。
    /// このフラグが使えるiOS 18以降では、その精度を補うために使う(FilterSettings.strictScreenshotDetection参照)。
    var isUtilityImage: Bool?
    /// この結果を作った時のロジックのバージョン。判定ロジックを改善した時に再解析させるための版番号。
    var analyzerVersion: Int

    /// 【2026-09-04: 1→2に更新】ImageAnalyzerのロジックを変更した(雰囲気の色しきい値を緩和、
    /// カテゴリ解析失敗時にキャッシュしないよう修正)ため、古いロジックで作られた結果は
    /// 再解析させる必要がある。バージョンを上げることで、次に選ばれた時に自動的に再解析される
    /// (原則3「同じ写真は二度と解析しない」の対象は「今のロジックで解析済みのもの」に限る)。
    /// 【2026-09-05: 2→3に更新】「緑」を選択肢から削除し、旧・緑の色相帯を暖色/寒色に
    /// 振り分け直したため、古いバージョンで "緑" と判定されキャッシュされた結果を再解析させる。
    /// 【2026-09-05: 3→4に更新】「よく撮れてる度」(aestheticsScore・isUtilityImage)を追加したため、
    /// 既存のキャッシュ済み結果(この2つが常にnilのまま)を再解析させ、値を埋める。
    /// 【2026-09-05: 4→5に更新】犬・猫で専用検出を優先しつつ、説明可能な一般分類候補も
    /// 短い待ち上限後に使えるよう、カテゴリごとの検出根拠を保存するようにした。
    static let currentVersion = 5
}

/// AssetAnalysis を localIdentifier ごとに端末内(Application Support配下のJSONファイル。
/// 【軽微指摘対応】以前のコメントは「Documents配下」としていたが、実際の保存先(下の fileURL)は
/// Application Support配下になっており食い違っていた)へ保存するキャッシュ。
/// 「使うほど速くなる」を実現する本体。iCloudバックアップには含めない(BackupExclusion.swift参照。端末内のみ)。
actor AnalysisCache {
    static let shared = AnalysisCache()

    private var storage: [String: AssetAnalysis] = [:]
    private var isLoaded = false
    private var isDirty = false

    private let fileURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("analysis_cache.json")
        // CEO判断(2026-09-04): 解析結果はiCloudバックアップの対象外にする(BackupExclusion.swift参照)
        BackupExclusion.exclude(url)
        return url
    }()

    private func loadIfNeeded() {
        guard !isLoaded else { return }
        isLoaded = true
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([String: AssetAnalysis].self, from: data) else {
            return
        }
        storage = decoded
    }

    func analysis(for localIdentifier: String) -> AssetAnalysis? {
        loadIfNeeded()
        let result = storage[localIdentifier]
        // 古いロジックで作られた結果は「未解析」扱いにして再解析させる
        if let result, result.analyzerVersion != AssetAnalysis.currentVersion {
            return nil
        }
        return result
    }

    func store(_ analysis: AssetAnalysis, for localIdentifier: String) {
        loadIfNeeded()
        storage[localIdentifier] = analysis
        isDirty = true
        scheduleSaveIfNeeded()
    }

    private var saveTask: Task<Void, Never>?
    /// 「保存待ち」の変更が最初に発生した時刻。連続して解析が続く間の書き込み上限(下記)を
    /// 計算するために使う。書き込みが終わるたびに nil に戻す。
    private var firstDirtyAt: Date?

    /// 書き込みを保存する(=ディスクに書く)頻度を抑える仕組み(指摘K対応)。
    ///
    /// 【以前の実装の問題】store()が呼ばれるたびに「まだ保存タスクが無ければ2秒後に1回保存する」
    /// という予約をしていたが、一度予約されたタスクはそのまま2秒後に必ず発火する仕様だった。
    /// スライドショー中は数百ミリ秒〜数秒おきに新しい写真の解析が続くため、実質「2秒おきに
    /// 辞書全体(数万件だと数MB)をまるごとJSON化して書き直す」動作になっていた
    /// (書き込みのたびにファイル全体を上書きするため、件数が多いほど1回の書き込みコストも増える)。
    ///
    /// 【今の実装】store()が呼ばれるたびに「最後の変更から2秒間、操作が止まったら保存する」という
    /// デバウンス(操作が続く間は保存を先延ばしにする仕組み)に変更した。ただし、スライドショーが
    /// 途切れず長時間続くとデバウンスが永遠に保存を先延ばしにしてしまい、その間にアプリが
    /// 不意に終了すると保存されていない解析結果がまとめて失われる(=次回同じ写真をもう一度
    /// 解析し直すことになる。あくまでキャッシュなので不具合にはならないが、量が多いと勿体ない)。
    /// そのためもう1つ上限を設け、「最初の未保存の変更から最大10秒経ったら、操作が続いていても
    /// そこで必ず1回保存する」ようにしている。
    private static let quietInterval: TimeInterval = 2.0
    private static let maxDelayInterval: TimeInterval = 10.0

    private func scheduleSaveIfNeeded() {
        let now = Date()
        if firstDirtyAt == nil { firstDirtyAt = now }
        let elapsedSinceFirstDirty = now.timeIntervalSince(firstDirtyAt ?? now)
        let remainingUntilCap = max(0, Self.maxDelayInterval - elapsedSinceFirstDirty)
        let waitInterval = min(Self.quietInterval, remainingUntilCap)

        // 新しい変更があるたびに、前の予約はキャンセルして待ち直す(デバウンス本体)。
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(waitInterval * 1_000_000_000))
            guard !Task.isCancelled else { return }
            // このTaskはAnalysisCacheアクター自身の中から作られているため、persist()の呼び出しに
            // awaitは不要(不要なawaitがビルド警告になっていたのを修正)。
            self.persist()
            self.saveTask = nil
            self.firstDirtyAt = nil
        }
    }

    func persist() {
        guard isDirty else { return }
        isDirty = false
        guard let data = try? JSONEncoder().encode(storage) else { return }
        try? data.write(to: fileURL, options: .atomic)
        // ファイルが存在して初めて設定できる属性のため、書き込み後にも改めて指定する
        // (初回はファイルがまだ無い状態でこの属性を試みても効かないため)
        BackupExclusion.exclude(fileURL)
    }

    /// 端末内に蓄積された解析件数(設定画面などでの表示用)
    func count() -> Int {
        loadIfNeeded()
        return storage.count
    }


    /// 解析済み結果だけから、選択中の主題に対する強一致・説明可能な近似のID索引を返す。
    /// 保存対象は従来どおり解析JSONだけで写真本体は複製しない。起動後の全画像解析も行わない。
    func subjectCandidateIDs(settings: FilterSettings) -> (strong: [String], approximate: [String]) {
        loadIfNeeded()
        var strong: [String] = []
        var approximate: [String] = []
        for (id, analysis) in storage where analysis.analyzerVersion == AssetAnalysis.currentVersion {
            if SubjectMatch.isStrong(analysis: analysis, settings: settings) {
                strong.append(id)
            } else if SubjectMatch.isExplainableApproximation(analysis: analysis, settings: settings) {
                approximate.append(id)
            }
        }
        return (strong.shuffled(), approximate.shuffled())
    }

    /// 容量診断用。写真本体ではなく解析JSONだけの実ファイルサイズを返す。
    func diskUsageBytes() -> Int64 {
        loadIfNeeded()
        return (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? NSNumber)?.int64Value ?? 0
    }

    /// 削除された写真の解析結果をキャッシュから取り除く(軽微な指摘:削除済み写真の結果が
    /// 残り続ける問題への対応)。LibraryIndexが写真ライブラリの差分検知(原則4)で
    /// 「削除された」と分かった localIdentifier をそのまま渡す想定で、ここで新たに写真を
    /// 探しにいくことはしない。
    func removeAnalyses(for deletedLocalIdentifiers: [String]) {
        guard !deletedLocalIdentifiers.isEmpty else { return }
        loadIfNeeded()
        var didRemove = false
        for id in deletedLocalIdentifiers where storage.removeValue(forKey: id) != nil {
            didRemove = true
        }
        if didRemove {
            isDirty = true
            scheduleSaveIfNeeded()
        }
    }
}
