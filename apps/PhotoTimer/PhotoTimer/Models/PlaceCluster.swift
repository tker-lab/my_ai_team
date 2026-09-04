import Foundation
import CoreLocation

/// 「場所」フィルタの1選択肢。ユーザー自身の写真の撮影地から自動生成する(フリー入力なし)。
///
/// 【id について(2026-09-04修正)】
/// 以前は id をクラスタの中心座標(平均値)から作っていたため、写真が1枚増減するだけで
/// 中心が少しずれて id が変わってしまい、保存しておいた「選んだ場所」がすぐ無効になる不具合があった。
/// 現在は id に `LocationClusterer` の「マス目(bucketKey)」をそのまま使う。マス目は写真の増減に
/// 左右されない安定した値なので、この不具合は起きない([[location-cluster-id-stability]]参照)。
struct PlaceCluster: Codable, Identifiable, Equatable {
    let id: String
    var displayName: String
    var centerLatitude: Double
    var centerLongitude: Double
    /// このかたまりに含まれるおおよその写真枚数(選択肢の並び順に使う)
    var assetCount: Int

    var location: CLLocation {
        CLLocation(latitude: centerLatitude, longitude: centerLongitude)
    }
}

/// 端末内に保存する「場所」選択肢一覧(表示用の要約のみ)。
/// クラスタ計算に必要な内部状態(マス目ごとの集計・写真ごとの所属マス目)は
/// `LocationClusterer` が別ファイルで保持する(こちらは「今の選択肢一覧」のスナップショットのみ)。
///
/// 【2026-09-04変更】保存先を UserDefaults から端末内(Application Support配下)のJSONファイルに変更。
/// 理由: 場所データ(自宅周辺の座標・地名を含みうる)をCEO判断でiCloudバックアップ対象外にするため
/// (UserDefaultsの値は個別にバックアップ除外を指定できないが、ファイルなら isExcludedFromBackup を
/// 設定できる。BackupExclusion.swift参照)。
enum PlaceClusterStore {
    private static let fileURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("place_clusters.json")
    }()

    static func load() -> [PlaceCluster] {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([PlaceCluster].self, from: data) else {
            return []
        }
        return decoded
    }

    static func save(_ clusters: [PlaceCluster]) {
        guard let data = try? JSONEncoder().encode(clusters) else { return }
        try? data.write(to: fileURL, options: .atomic)
        BackupExclusion.exclude(fileURL)
    }
}
