import Foundation

/// 1枚の写真・動画を解析した結果。localIdentifier(写真ライブラリ内でのその写真固有のID)をキーに
/// 端末内DBへ蓄積する(原則3: 同じ写真は二度と解析しない)。
struct AssetAnalysis: Codable {
    var mood: MoodTag?
    var categories: [CategoryTag]
    /// この結果を作った時のロジックのバージョン。判定ロジックを改善した時に再解析させるための版番号。
    var analyzerVersion: Int

    static let currentVersion = 1
}

/// AssetAnalysis を localIdentifier ごとに端末内(Documents配下のJSONファイル)へ保存するキャッシュ。
/// 「使うほど速くなる」を実現する本体。iCloudには置かない(端末内のみ)。
actor AnalysisCache {
    static let shared = AnalysisCache()

    private var storage: [String: AssetAnalysis] = [:]
    private var isLoaded = false
    private var isDirty = false

    private let fileURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("analysis_cache.json")
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
    private func scheduleSaveIfNeeded() {
        guard saveTask == nil else { return }
        saveTask = Task {
            // 書き込みをまとめるため少し待ってから保存する(1枚ごとにディスクI/Oしない)
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await self.persist()
            self.saveTask = nil
        }
    }

    func persist() {
        guard isDirty else { return }
        isDirty = false
        guard let data = try? JSONEncoder().encode(storage) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    /// 端末内に蓄積された解析件数(設定画面などでの表示用)
    func count() -> Int {
        loadIfNeeded()
        return storage.count
    }
}
