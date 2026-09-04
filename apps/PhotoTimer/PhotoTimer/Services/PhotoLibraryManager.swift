import Foundation
import Photos

/// 写真ライブラリへのアクセス許可・アルバム一覧・差分検知(原則4)を担当する。
///
/// 【原則4:増減は差分だけ追う。全走査しない】
/// 前回終了時点の PHPersistentChangeToken(写真ライブラリの「しおり」のようなもの)を
/// UserDefaults に保存しておき、次回起動時はその「しおり」以降に追加・更新・削除された
/// 写真の localIdentifier 一覧だけを取得する。初回起動時、またはしおりが古すぎて
/// 失効している時は比較のしようがないため「全部が差分(=全件を対象にする)」として扱う。
///
/// 【2026-09-04修正(指摘A対応)】
/// `fetchAlbums()` と `checkForChangesSinceLastLaunch()` を `nonisolated`(= @MainActorの外)にした。
/// 修正前はこのクラス全体が @MainActor だったため、呼び出し側で `Task { ... }` に包んでいても
/// 実際には画面スレッド(MainActor)上で実行され続けていた(写真が数万枚あると起動直後に
/// 数秒間タップを受け付けなくなる原因)。`nonisolated` にすることで、呼び出し側が
/// バックグラウンドから安全に呼べるようになる。`authorizationStatus` の公開状態(@Published)は
/// 引き続き画面表示に使うため、そこだけメインスレッド(MainActor)のままにしている。
@MainActor
final class PhotoLibraryManager: ObservableObject {
    static let shared = PhotoLibraryManager()

    @Published private(set) var authorizationStatus: PHAuthorizationStatus

    // 定数(書き換わらない値)なので nonisolated にして、バックグラウンドの nonisolated メソッドからも
    // await無しで参照できるようにする(このクラス全体は@MainActorだが、これは例外として問題ない)。
    nonisolated private static let tokenDefaultsKey = "PhotoTimer.PersistentChangeToken.v1"

    private init() {
        authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    func refreshAuthorizationStatus() {
        authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    /// 写真へのアクセスを依頼する。すでに許可/拒否済みならOSは即座に現在の状態を返す(再度ダイアログは出ない)。
    ///
    /// 【指摘E(読み取り専用にすべき)について】
    /// 調査の結果、PhotoKit(写真を扱うApple標準の仕組み)の権限レベルには「読み取り専用」という
    /// 選択肢がそもそも存在しない。選べるのは `.readWrite`(閲覧+書き込み)と `.addOnly`
    /// (新規追加のみ・既存の写真は見えない)の2種類だけで、このアプリのように「既存の写真を
    /// 選んで表示する」用途では `.readWrite` を選ぶ以外に方法が無い(Appleの命名が誤解を招きやすいが、
    /// 実質「フルアクセス」を指す値だと考えてよい)。
    /// そのためコード上はこれまで通り `.readWrite` を指定しているが、**実際に書き込み
    /// (PHPhotoLibrary.performChanges等)を行う処理はアプリ内に一切無い**ことを確認済み。
    /// また Info.plist にも「読み取り用」の説明文(NSPhotoLibraryUsageDescription)のみを申告しており、
    /// 「追加用」の説明文(NSPhotoLibraryAddUsageDescription)は含めていない(不要な権限を申告しない、
    /// という指摘の意図はこの形で満たしている)。
    @discardableResult
    func requestAccess() async -> PHAuthorizationStatus {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        authorizationStatus = status
        return status
    }

    var isUsable: Bool {
        Self.isUsable(authorizationStatus)
    }

    nonisolated private static func isUsable(_ status: PHAuthorizationStatus) -> Bool {
        status == .authorized || status == .limited
    }

    /// 写真ライブラリの前回からの変化を表す。
    struct ChangeSet {
        /// true の時は「しおりが無い/失効した」ことを意味し、他のプロパティは空のまま使わない。
        /// この場合は呼び出し側が全件を対象として扱う必要がある(初回起動、またはごく稀に起きる
        /// トークン失効時のみ。日常的な起動では基本的に false になる)。
        var requiresFullRebuild: Bool
        var insertedOrUpdatedIdentifiers: [String]
        var deletedIdentifiers: [String]
        /// この差分を計算した時点の「新しいしおり」。まだ端末には保存していない状態のもの。
        /// 【指摘J対応】呼び出し側がこの差分を実際に反映し終えたら `commitToken(_:)` に渡して
        /// 初めて保存する(差分を検知した直後にすぐ保存すると、保存後・反映前にアプリが終了した場合、
        /// その分の差分が「もう前回のしおりより後ろなので次回は差分に出てこない」まま永久に失われるため)。
        var pendingToken: PHPersistentChangeToken?

        /// 何かしらの変化があったか(全件対象化が必要な場合も含む)。
        var hasAnyChange: Bool {
            requiresFullRebuild || !insertedOrUpdatedIdentifiers.isEmpty || !deletedIdentifiers.isEmpty
        }

        static let none = ChangeSet(requiresFullRebuild: false, insertedOrUpdatedIdentifiers: [], deletedIdentifiers: [], pendingToken: nil)
    }

    /// 起動時に呼ぶ。前回からの差分だけを確認する。「原則4」の実装本体。
    ///
    /// `nonisolated`: 画面スレッド(MainActor)をブロックしないよう、呼び出し側が
    /// バックグラウンドのTaskから呼べるようにするため(指摘A対応)。
    ///
    /// 【指摘J対応】この関数自体はもう「しおり」を保存しない(計算するだけ)。実際に保存するのは
    /// 呼び出し側が差分の反映を終えた後、`commitToken(changeSet.pendingToken)` を呼んだ時点。
    nonisolated func checkForChangesSinceLastLaunch() -> ChangeSet {
        guard Self.isUsable(PHPhotoLibrary.authorizationStatus(for: .readWrite)) else { return .none }

        let previousToken = Self.loadToken()
        var changeSet = ChangeSet.none

        if let previousToken {
            do {
                // 前回のしおり以降の変化だけを取得する(全件のスキャンではない)。
                let changes = try PHPhotoLibrary.shared().fetchPersistentChanges(since: previousToken)
                var inserted = Set<String>()
                var updated = Set<String>()
                var deleted = Set<String>()
                for change in changes {
                    // 【指摘I対応】以前は `try?` で「詳細が取得できないエラー」まで含めて握りつぶし、
                    // その変更だけを黙って読み飛ばしていた。しおり(トークン)はこの後どのみち
                    // 最新まで進めてしまうため、一度読み飛ばした変更は二度と拾えなくなる
                    // (取りこぼしが無言で起き続ける)。
                    // このメソッドは「アセット以外の変化(アルバムの並び替え等)しか無い」場合は
                    // 空の詳細(insertedLocalIdentifiers等が空)を返すだけで、エラーにはならない
                    // (Photosフレームワークのドキュメント上、正常系)。エラーを投げるのは
                    // `PHPhotosErrorPersistentChangeDetailsUnavailable`(=変更履歴からもう
                    // 現在の状態を再構築できない)ような、本当に差分を取り切れない場合だけなので、
                    // `try`(`?`を付けない)でこの下の catch まで伝播させ、その時だけ
                    // 全件再構築にフォールバックする。
                    let details = try change.changeDetails(for: .asset)
                    inserted.formUnion(details.insertedLocalIdentifiers)
                    updated.formUnion(details.updatedLocalIdentifiers)
                    deleted.formUnion(details.deletedLocalIdentifiers)
                }
                changeSet.insertedOrUpdatedIdentifiers = Array(inserted.union(updated))
                changeSet.deletedIdentifiers = Array(deleted)
            } catch {
                // しおりが古すぎて失効している等、差分を追えない場合のみ全件対象にフォールバックする。
                // (頻繁には起きない想定。日常的な起動ではこの分岐に入らない)
                changeSet.requiresFullRebuild = true
            }
        } else {
            // 初回起動。しおりが無く比較のしようがないため全件を対象とする。
            changeSet.requiresFullRebuild = true
        }

        // 「次のしおり」を計算はするが、ここではまだ保存しない(指摘J対応。保存は呼び出し側が
        // 差分の反映を終えてから commitToken(_:) で行う)。
        changeSet.pendingToken = PHPhotoLibrary.shared().currentChangeToken

        return changeSet
    }

    /// 呼び出し側が `checkForChangesSinceLastLaunch()` で受け取った差分を実際に反映し終えたら呼ぶ。
    /// ここで初めて「しおり」を端末に保存する(指摘J対応)。
    nonisolated func commitToken(_ token: PHPersistentChangeToken) {
        Self.saveToken(token)
    }

    nonisolated private static func loadToken() -> PHPersistentChangeToken? {
        guard let data = UserDefaults.standard.data(forKey: tokenDefaultsKey) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: PHPersistentChangeToken.self, from: data)
    }

    nonisolated private static func saveToken(_ token: PHPersistentChangeToken) {
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
    ///
    /// `nonisolated`: アルバムごとに枚数を数える問い合わせ(`PHAsset.fetchAssets(in:...).count`)は
    /// アルバム数によっては軽くない処理になりうるため、画面スレッド(MainActor)で行わないようにする
    /// (指摘A対応。呼び出し側はバックグラウンドのTaskから呼ぶこと)。
    nonisolated func fetchAlbums() -> [AlbumInfo] {
        guard Self.isUsable(PHPhotoLibrary.authorizationStatus(for: .readWrite)) else { return [] }
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
