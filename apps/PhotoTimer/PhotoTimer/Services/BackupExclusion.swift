import Foundation

/// 端末内DBのファイルを iCloudバックアップの対象から外すための小さな共通処理。
///
/// 【なぜ必要か(CEO判断・2026-09-04)】
/// 解析結果(AssetAnalysis)と場所データ(PlaceCluster・場所の集計インデックス)は、
/// 自宅周辺の座標・地名を含みうる。バックアップ経由で意図せず他の場所(iCloud等)に
/// コピーが残ることを避けるため、これらのファイルは明示的にバックアップ対象外にする。
/// (アプリ自体が外部へ送信するわけではないが、「バックアップにも含めない」という
/// 一段階踏み込んだ対応をCEOが選んだ)
enum BackupExclusion {
    /// 指定したファイルの isExcludedFromBackup を true にする。失敗しても動作自体には
    /// 支障がないため(単にバックアップに含まれてしまうだけ)、エラーは無視する。
    static func exclude(_ fileURL: URL) {
        var url = fileURL
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }
}
