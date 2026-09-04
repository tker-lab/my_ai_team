import Foundation
import Photos

/// カテゴリ選択肢の「並び順」だけを決めるためのサンプル解析。
///
/// 【2026-09-04方針】サンプル解析はメニューの並べ替えにのみ使う。カテゴリを隠さない。
/// 0件のカテゴリでも一覧からは消さない(実際に絞り込む時は毎回全写真が対象になる。原則2)。
enum CategorySampler {
    private static let sampleSize = 200

    /// ランダムに最大200枚をサンプリングして解析し、カテゴリごとの出現回数を返す。
    /// 解析結果は AnalysisCache に保存されるため、後で実際にそのカテゴリで絞り込む時に再利用できる(原則3)。
    static func sampleCategoryCounts(allAssets: PHFetchResult<PHAsset>) async -> [CategoryTag: Int] {
        let total = allAssets.count
        guard total > 0 else { return [:] }

        let sampleCount = min(sampleSize, total)
        let indices = Array(0..<total).shuffled().prefix(sampleCount)

        var counts: [CategoryTag: Int] = [:]
        let imageManager = PHCachingImageManager()
        let requestOptions = PHImageRequestOptions()
        requestOptions.deliveryMode = .fastFormat
        requestOptions.isNetworkAccessAllowed = false // iCloudからのダウンロードはしない(端末内にあるものだけ)
        requestOptions.resizeMode = .fast

        for index in indices {
            let asset = allAssets.object(at: index)
            guard asset.mediaType == .image else { continue } // サンプルは静止画のみで十分(動画のサムネイルはコスト高)

            if let cached = await AnalysisCache.shared.analysis(for: asset.localIdentifier) {
                for category in cached.categories { counts[category, default: 0] += 1 }
                continue
            }

            guard let cgImage = await requestSmallCGImage(asset: asset, manager: imageManager, options: requestOptions) else { continue }
            // 解析(Vision)自体が失敗した場合は nil が返る(2026-09-04変更)。並び順のためだけの
            // サンプリングなので、その1枚は諦めて次へ進む(キャッシュにも保存しない。呼び出し側
            // CandidateEngine 側と同じ「判定できなかったものは残さない」という扱いに揃えている)。
            guard let analysis = ImageAnalyzer.analyze(cgImage: cgImage) else { continue }
            await AnalysisCache.shared.store(analysis, for: asset.localIdentifier)
            for category in analysis.categories { counts[category, default: 0] += 1 }

            // OSに一方的に負荷をかけ続けないよう一呼吸置く(バックグラウンドの並べ替え用データなので急ぐ必要はない)
            try? await Task.sleep(nanoseconds: 5_000_000)
        }

        await AnalysisCache.shared.persist()
        return counts
    }

    private static func requestSmallCGImage(asset: PHAsset, manager: PHCachingImageManager, options: PHImageRequestOptions) async -> CGImage? {
        await withCheckedContinuation { continuation in
            manager.requestImage(for: asset, targetSize: CGSize(width: 128, height: 128), contentMode: .aspectFill, options: options) { image, _ in
                continuation.resume(returning: image?.cgImage)
            }
        }
    }
}
