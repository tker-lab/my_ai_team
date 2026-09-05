import Foundation
import Photos
import Vision
import UIKit

// 【調査専用・2026-09-05・検証後に削除予定】
//
// 「Visionの一般分類(VNClassifyImageRequest)がCEOの実際の写真に対してどのラベルを
// どれだけ返しているか」を実測するための診断コード。過去の「場所」調査
// (RootView.runLocationDiagnosticIfRequested)と同じ手法:
//  - #if DEBUG かつ環境変数ゲートの二重ガード(CEOの普段の利用では絶対に動かない)
//  - 読み取り専用(写真・動画を書き換えない。削除もしない)
//  - 結果は件数・ラベル名・信頼度などの集計値のみをNSLogに出す(写真データそのものは
//    保存・送信しない)
//  - 検証が終わったらこのファイルごと削除する
//
// 知りたいこと(依頼内容):
//  1. よく返ってくるラベルの一覧と出現数(上位100件程度)
//  2. pig/monkey/primate等、現在のキーワードに無い動物ラベルが返るか
//  3. 人が写った写真に対して、動物系のラベルがどの程度の信頼度で返るか
//  4. 現在の generalClassifierKeywords が実際にどれだけヒットしているか(カテゴリ別)
//
// 全件走査は時間がかかるため、無作為な数百枚のサンプルで計測する(依頼どおり)。
#if DEBUG
enum DiagLabelMeasurement {

    /// 現行コード(ImageAnalyzer.swift)と同じ、一般分類の合格ラインの閾値。
    private static let generalConfidenceThreshold: Float = 0.15

    /// 依頼にある「サンプルは数百枚程度で十分」を踏まえたサンプル数。
    private static let sampleSize = 300

    /// pig/monkey等、現在のキーワード一覧に無い動物を探すための手がかり語。
    /// (課金コンテンツ候補の「豚・猿」の可否判断に使う実測が目的。この語自体を
    /// カテゴリ判定のキーワードとしてコードに組み込むわけではない。)
    private static let animalsOfInterestNeedles = [
        "pig", "hog", "swine", "boar", "monkey", "ape", "primate",
        "chimpanzee", "gorilla", "orangutan", "baboon"
    ]

    static func run() async {
        let overallStart = Date()
        let fetchResult = PHAsset.fetchAssets(with: .image, options: nil)
        let total = fetchResult.count
        guard total > 0 else {
            NSLog("[PhotoTimer][DiagLabels] 静止画が0枚のため計測できません")
            return
        }

        let count = min(sampleSize, total)
        // 重複を許した無作為抽出(母数が大きいので実用上ほぼ重複しない)。
        let sampleIndices = (0..<count).map { _ in Int.random(in: 0..<total) }

        var labelCounts: [String: Int] = [:]
        var animalOfInterestHits: [String: (count: Int, maxConfidence: Float)] = [:]
        var keywordHitCounts: [String: Int] = [:]
        var humanPhotoCount = 0
        var humanPhotoAnimalLabelHits: [String: [Float]] = [:]
        var analyzed = 0
        var thumbnailFailures = 0
        var visionFailures = 0

        for idx in sampleIndices {
            if Task.isCancelled { break }
            let asset = fetchResult.object(at: idx)
            guard let cgImage = await requestThumbnail(asset: asset) else {
                thumbnailFailures += 1
                continue
            }

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            let classifyRequest = VNClassifyImageRequest()
            let humanRequest = VNDetectHumanRectanglesRequest()
            do {
                try handler.perform([classifyRequest, humanRequest])
            } catch {
                visionFailures += 1
                continue
            }
            analyzed += 1

            let hasHuman = !(humanRequest.results?.isEmpty ?? true)
            if hasHuman { humanPhotoCount += 1 }

            guard let classifications = classifyRequest.results else { continue }

            for observation in classifications where observation.confidence >= generalConfidenceThreshold {
                let identifier = observation.identifier.lowercased()
                labelCounts[identifier, default: 0] += 1

                if animalsOfInterestNeedles.contains(where: { identifier.contains($0) }) {
                    var entry = animalOfInterestHits[identifier] ?? (count: 0, maxConfidence: 0)
                    entry.count += 1
                    entry.maxConfidence = max(entry.maxConfidence, observation.confidence)
                    animalOfInterestHits[identifier] = entry
                }

                if hasHuman {
                    let looksAnimalRelated = identifier.contains("animal")
                        || animalsOfInterestNeedles.contains(where: { identifier.contains($0) })
                        || CategoryTag.otherAnimal.generalClassifierKeywords.contains(where: { identifier.contains($0) })
                        || CategoryTag.dog.generalClassifierKeywords.contains(where: { identifier.contains($0) })
                        || CategoryTag.cat.generalClassifierKeywords.contains(where: { identifier.contains($0) })
                    if looksAnimalRelated {
                        humanPhotoAnimalLabelHits[identifier, default: []].append(observation.confidence)
                    }
                }
            }

            // 現行の部分一致キーワード判定(ImageAnalyzer.swift:188と同じロジック)を
            // そのまま再現し、カテゴリごとの実ヒット数を数える(誤爆修正の効果測定にも使う)。
            for tag in CategoryTag.allCases where tag != .person {
                let keywords = tag.generalClassifierKeywords
                guard !keywords.isEmpty else { continue }
                let hit = classifications.contains { observation in
                    guard observation.confidence >= generalConfidenceThreshold else { return false }
                    let identifier = observation.identifier.lowercased()
                    return keywords.contains(where: { identifier.contains($0) })
                }
                if hit { keywordHitCounts[tag.rawValue, default: 0] += 1 }
            }
        }

        let elapsed = Date().timeIntervalSince(overallStart)

        NSLog("[PhotoTimer][DiagLabels] ===== ラベル実測開始 =====")
        NSLog("[PhotoTimer][DiagLabels] 静止画母数=\(total) サンプル数=\(sampleIndices.count) 解析成功=\(analyzed) サムネイル取得失敗=\(thumbnailFailures) Vision失敗=\(visionFailures) 所要時間=\(String(format: "%.2f", elapsed))秒")
        NSLog("[PhotoTimer][DiagLabels] 人物あり(VNDetectHumanRectangles)と判定された枚数=\(humanPhotoCount)")

        NSLog("[PhotoTimer][DiagLabels] --- 上位ラベル(出現数の多い順、最大100件、信頼度0.15以上) ---")
        let sortedLabels = labelCounts.sorted { $0.value > $1.value }.prefix(100)
        for (label, count) in sortedLabels {
            NSLog("[PhotoTimer][DiagLabels] label=\(label) count=\(count)")
        }

        NSLog("[PhotoTimer][DiagLabels] --- pig/monkey系ラベル(手がかり語一致) ---")
        if animalOfInterestHits.isEmpty {
            NSLog("[PhotoTimer][DiagLabels] pig/monkey系ラベルは1件もヒットしませんでした")
        } else {
            for (label, entry) in animalOfInterestHits.sorted(by: { $0.value.count > $1.value.count }) {
                NSLog("[PhotoTimer][DiagLabels] label=\(label) count=\(entry.count) maxConfidence=\(entry.maxConfidence)")
            }
        }

        NSLog("[PhotoTimer][DiagLabels] --- 人物ありサンプルで動物系ラベルが返ったケース ---")
        if humanPhotoAnimalLabelHits.isEmpty {
            NSLog("[PhotoTimer][DiagLabels] 人物ありサンプルで動物系ラベルは1件もヒットしませんでした")
        } else {
            for (label, confidences) in humanPhotoAnimalLabelHits.sorted(by: { $0.value.count > $1.value.count }) {
                let avg = confidences.reduce(0, +) / Float(confidences.count)
                NSLog("[PhotoTimer][DiagLabels] label=\(label) count=\(confidences.count) avgConfidence=\(String(format: "%.3f", avg)) maxConfidence=\(confidences.max() ?? 0)")
            }
        }

        NSLog("[PhotoTimer][DiagLabels] --- 現行 generalClassifierKeywords のヒット数(カテゴリ別、部分一致のまま) ---")
        for tag in CategoryTag.allCases where tag != .person {
            guard !tag.generalClassifierKeywords.isEmpty else { continue }
            NSLog("[PhotoTimer][DiagLabels] category=\(tag.rawValue) hits=\(keywordHitCounts[tag.rawValue] ?? 0)")
        }
        NSLog("[PhotoTimer][DiagLabels] ===== ラベル実測終了 =====")
    }

    /// CandidateEngine.requestAnalysisThumbnail と同じ設定(判定用サムネイル。端末内のみ、iCloudへは取りに行かない)。
    private static func requestThumbnail(asset: PHAsset) async -> CGImage? {
        let options = PHImageRequestOptions()
        options.deliveryMode = .fastFormat
        options.isNetworkAccessAllowed = false
        options.resizeMode = .fast

        return await withCheckedContinuation { continuation in
            final class ResumeBox: @unchecked Sendable {
                var didResume = false
            }
            let box = ResumeBox()
            PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width: 256, height: 256), contentMode: .aspectFill, options: options) { image, _ in
                guard !box.didResume else { return }
                box.didResume = true
                continuation.resume(returning: image?.cgImage)
            }
        }
    }
}
#endif
