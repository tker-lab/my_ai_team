import Foundation
import Photos

/// 写真ライブラリへのアクセス許可・アルバム一覧・差分検知(原則4)を担当する。
///
/// 【原則4:増減は差分だけ追う。全走査しない】
/// 前回終了時点の PHPersistentChangeToken(写真ライブラリの「しおり」のようなもの)を
/// UserDefaults に保存しておき、次回起動時はその「しおり」以降の変化だけを取得する。
/// 初回起動時はしおりが無いので比較のしようがなく、差分検知はスキップする(=何もしない。全件を自分でなめて回ることはしない)。
@MainActor
final class PhotoLibraryManager: ObservableObject {
    static let shared = PhotoLibraryManager()

    @Published private(set) var authorizationStatus: PHAuthorizationStatus

    private let tokenDefaultsKey = "PhotoTimer.PersistentChangeToken.v1"

    private init() {
        authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    func refreshAuthorizationStatus() {
        authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    /// 写真へのアクセスを依頼する。すでに許可/拒否済みならOSは即座に現在の状態を返す(再度ダイアログは出ない)。
    @discardableResult
    func requestAccess() async -> PHAuthorizationStatus {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        authorizationStatus = status
        return status
    }

    var isUsable: Bool {
        authorizationStatus == .authorized || authorizationStatus == .limited
    }

    /// 起動時に呼ぶ。前回からの差分だけを確認し、変化があれば true を返す。
    /// 「原則4」の実装本体。ここが重い全件スキャンにならないことが重要。
    @discardableResult
    func checkForChangesSinceLastLaunch() -> Bool {
        guard isUsable else { return false }

        let previousToken = loadToken()
        var hasChanges = false

        if let previousToken {
            // しおりがある = 2回目以降の起動。差分だけ取得する。
            if let result = try? PHPhotoLibrary.shared().fetchPersistentChanges(since: previousToken) {
                // enumerate するだけで「何か変化があったか」を確認する。
                // (どの写真がどう変わったかの詳細は使わず、既存キャッシュを念のため再利用可能かの判断材料にのみ使う)
                for _ in result {
                    hasChanges = true
                    break
                }
            }
        } else {
            // 初回起動。差分の比較対象が無いため「全部が差分」とみなすが、
            // ここで全アセットを自分でループすることはしない。あくまで
            // 「場所クラスタ・カテゴリ順序といった補助データが未構築」という扱いにするだけ。
            hasChanges = true
        }

        // 次回のために「しおり」を更新しておく
        let newToken = PHPhotoLibrary.shared().currentChangeToken
        saveToken(newToken)

        return hasChanges
    }

    private func loadToken() -> PHPersistentChangeToken? {
        guard let data = UserDefaults.standard.data(forKey: tokenDefaultsKey) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: PHPersistentChangeToken.self, from: data)
    }

    private func saveToken(_ token: PHPersistentChangeToken) {
        guard let data = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true) else { return }
        UserDefaults.standard.set(data, forKey: tokenDefaultsKey)
    }

    // MARK: - アルバム一覧(標準の仕組みでの取得。フリー入力なし)

    struct AlbumInfo: Identifiable, Hashable {
        let id: String // localIdentifier
        let title: String
        let assetCount: Int
    }

    /// ユーザー・スマート両方のアルバム一覧を取得する。
    /// PHAssetCollection の取得は写真本体のデコードを伴わない軽い問い合わせなので、起動時に呼んでも待たされない。
    func fetchAlbums() -> [AlbumInfo] {
        guard isUsable else { return [] }
        var albums: [AlbumInfo] = []

        func append(from fetchResult: PHFetchResult<PHAssetCollection>) {
            fetchResult.enumerateObjects { collection, _, _ in
                let count = PHAsset.fetchAssets(in: collection, options: nil).count
                guard count > 0, let title = collection.localizedTitle else { return }
                albums.append(AlbumInfo(id: collection.localIdentifier, title: title, assetCount: count))
            }
        }

        append(from: PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil))
        append(from: PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .any, options: nil))

        return albums.sorted { $0.assetCount > $1.assetCount }
    }
}
