import Foundation
import UIKit
import CoreImage
import Vision

/// 1枚の画像から「雰囲気(色)」と「カテゴリ」を判定する。
///
/// 【原則2:判定は選ばれた時に、流しながら行う】
/// ここは常に「シャッフルされた候補の中から今まさに表示しようとしている1枚」に対してだけ呼ばれる。
/// アプリ全体の写真を先回りしてまとめて解析することはしない。
///
/// 【原則3で使う】結果は呼び出し側(CandidateEngine)が AnalysisCache に保存し、次回以降は再利用する。
enum ImageAnalyzer {

    /// 一般分類・専用検出(犬猫)・人物検出のどれかがこの信頼度を超えたら「該当する」とみなす。
    /// 「見逃すより拾いすぎる側に倒す」方針のため、やや低めに設定。
    private static let generalConfidenceThreshold: Float = 0.15
    private static let dedicatedConfidenceThreshold: Float = 0.3

    static func analyze(cgImage: CGImage) -> AssetAnalysis {
        let mood = analyzeMood(cgImage: cgImage)
        let categories = analyzeCategories(cgImage: cgImage)
        return AssetAnalysis(mood: mood, categories: categories, analyzerVersion: AssetAnalysis.currentVersion)
    }

    // MARK: - 雰囲気・色(CoreImageで平均色を取り、色相・彩度・明度から分類)

    private static func analyzeMood(cgImage: CGImage) -> MoodTag? {
        guard let avg = averageColor(cgImage: cgImage) else { return nil }
        let (h, s, b) = avg

        // 各しきい値は「固定8種類の選択肢(FixedChoices.swift)を、平均色1点だけからそれらしく
        // 振り分ける」ための目安値。HSB(色相・彩度・明度)はいずれも0〜1の範囲。
        // 数値解析による最適化ではなく、実際の写真で試しながら決めた経験則であることに注意
        // (=精度を追い込む種類のしきい値ではない。色に関する条件は「多少ずれても実害が小さい」
        // 性質のため、これで十分と判断した)。
        //  - 明度(b) < 0.25: 暗所・夜景など、画面全体が暗いと感じられる目安として「暗め」判定
        //  - 明度(b) > 0.85 かつ 彩度(s) < 0.2: 白背景に近いくらい明るく色味が薄い時に「明るめ」判定
        //  - 彩度(s) < 0.15: ほぼ無彩色(白黒グレー)とみなせる目安で「モノトーン」判定
        //  - 彩度(s) < 0.35: 上より色はあるがまだ淡い程度の目安で「淡い」判定
        // これらに当てはまらない場合のみ、下の色相(hue)による暖色・寒色・緑の判定に進む。
        if b < 0.25 { return .dark }
        if b > 0.85 && s < 0.2 { return .bright }
        if s < 0.15 { return .monotone }
        if s < 0.35 { return .pastel }

        // 色相(0〜1)で暖色/寒色/緑を判定。0=赤,0.17=黄,0.33=緑,0.5=シアン,0.66=青,0.83=マゼンタ
        switch h {
        case 0.22..<0.45:
            return .green
        case 0.0..<0.16, 0.92...1.0:
            return s > 0.5 ? .vivid : .warm
        case 0.16..<0.22:
            return .warm
        case 0.45..<0.7:
            return .cool
        default:
            return s > 0.5 ? .vivid : .cool
        }
    }

    /// 画像を1x1に縮小して平均色を取り、HSBへ変換する。写真全体をピクセル単位で見るわけではなく
    /// CoreImageのGPUフィルタで一瞬で計算できるため、これも「流しながら」の判定に十分間に合う。
    private static func averageColor(cgImage: CGImage) -> (hue: CGFloat, saturation: CGFloat, brightness: CGFloat)? {
        let ciImage = CIImage(cgImage: cgImage)
        let extent = ciImage.extent
        guard let filter = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: ciImage,
            kCIInputExtentKey: CIVector(cgRect: extent)
        ]) else { return nil }
        guard let outputImage = filter.outputImage else { return nil }

        var bitmap = [UInt8](repeating: 0, count: 4)
        let context = CIContext(options: [.workingColorSpace: NSNull()])
        context.render(outputImage, toBitmap: &bitmap, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                        format: .RGBA8, colorSpace: nil)

        let color = UIColor(red: CGFloat(bitmap[0]) / 255, green: CGFloat(bitmap[1]) / 255, blue: CGFloat(bitmap[2]) / 255, alpha: 1)
        var h: CGFloat = 0, s: CGFloat = 0, br: CGFloat = 0, a: CGFloat = 0
        color.getHue(&h, saturation: &s, brightness: &br, alpha: &a)
        return (h, s, br)
    }

    // MARK: - カテゴリ(犬・猫・人は専用検出、それ以外は一般分類)

    private static func analyzeCategories(cgImage: CGImage) -> [CategoryTag] {
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        let classifyRequest = VNClassifyImageRequest()
        let animalRequest = VNRecognizeAnimalsRequest()
        let humanRequest = VNDetectHumanRectanglesRequest()

        // 3つのリクエストを1回のハンドラでまとめて実行(画像デコードを使い回す)
        try? handler.perform([classifyRequest, animalRequest, humanRequest])

        var found: Set<CategoryTag> = []

        // 犬・猫(専用検出。VNRecognizeAnimalsRequest)
        if let animalResults = animalRequest.results {
            for observation in animalResults {
                for label in observation.labels where label.confidence >= dedicatedConfidenceThreshold {
                    if label.identifier == "Dog" { found.insert(.dog) }
                    if label.identifier == "Cat" { found.insert(.cat) }
                }
            }
        }

        // 人(専用検出。VNDetectHumanRectanglesRequest = 体の存在検出。誰かの特定は行わない)
        if let humanResults = humanRequest.results, !humanResults.isEmpty {
            found.insert(.person)
        }

        // それ以外は一般分類のキーワード一致で拾う(拾いすぎる側に倒す)
        if let classifications = classifyRequest.results {
            let hits = classifications
                .filter { $0.confidence >= generalConfidenceThreshold }
                .map { $0.identifier.lowercased() }

            for tag in CategoryTag.allCases where !tag.hasDedicatedDetector {
                let keywords = tag.generalClassifierKeywords
                if hits.contains(where: { identifier in keywords.contains(where: { identifier.contains($0) }) }) {
                    found.insert(tag)
                }
            }
        }

        return Array(found)
    }
}
