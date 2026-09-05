import Foundation

/// CEOが写真ライブラリから自分で選んだ写真・動画をまとめた「自作リスト」1件分。
///
/// 【なぜ localIdentifier だけを保存するか】
/// 「写真本体は複製しない」という設計方針(自由なアルバムと同じ考え方)に従う。ここに保存するのは
/// PHAsset.localIdentifier(写真ライブラリ内での背番号のようなもの)の並びだけで、画像データそのものは
/// 一切コピーしない。実際に表示する時は、その都度 localIdentifier から本物の写真を取得する
/// (CustomListEditView・CandidateEngine参照)。
struct CustomPhotoList: Codable, Identifiable, Equatable {
    let id: String
    var name: String
    /// ユーザーが選んだ順を保つ(PHPickerConfiguration.selection = .ordered を使って取得)。
    var assetLocalIdentifiers: [String]
    var createdAt: Date
    var updatedAt: Date

    init(id: String = UUID().uuidString, name: String, assetLocalIdentifiers: [String], createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.assetLocalIdentifiers = assetLocalIdentifiers
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// 自作リスト一覧の永続化。
///
/// 【保存先について】場所データ(PlaceCluster)・解析結果(AssetAnalysis)と同じ「端末内(Application
/// Support配下)のJSONファイル + isExcludedFromBackup」の方式に揃える。ここに入っているのは
/// リストの名前とlocalIdentifierの並びだけで座標のような機微な情報は含まないが、
/// 「CEOがどんな写真を選んでリスト化したか」という個人の趣向が読み取れる情報ではあるため、
/// 他の端末内DBと同じ扱い(バックアップにも含めない)にしておく。
enum CustomPhotoListStore {
    private static let fileURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("custom_photo_lists.json")
    }()

    static func load() -> [CustomPhotoList] {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([CustomPhotoList].self, from: data) else {
            return []
        }
        return decoded
    }

    static func save(_ lists: [CustomPhotoList]) {
        guard let data = try? JSONEncoder().encode(lists) else { return }
        try? data.write(to: fileURL, options: .atomic)
        BackupExclusion.exclude(fileURL)
    }
}
