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

    /// カテゴリの解析結果。Visionでの解析自体が失敗した場合は nil を返す
    /// (「判定できなかった」であって「該当カテゴリが無かった」ではないことを呼び出し側に伝えるため。
    /// 詳細は analyzeCategories 内のコメント参照)。
    ///
    /// 【2026-09-05変更:async化】「よく撮れてる度」(CalculateImageAestheticsScoresRequest)が
    /// Swiftの新しい非同期API(`request.perform(on:)`がasync throws)のため、この関数全体もasyncにした。
    /// 雰囲気・カテゴリの判定自体は元々同期処理のままで、待つのは「よく撮れてる度」の部分だけ。
    static func analyze(cgImage: CGImage) async -> AssetAnalysis? {
        let mood = analyzeMood(cgImage: cgImage)
        guard let categoryConfidences = analyzeCategories(cgImage: cgImage) else { return nil }
        let (aestheticsScore, isUtilityImage) = await analyzeAesthetics(cgImage: cgImage)
        return AssetAnalysis(
            mood: mood,
            categories: Array(categoryConfidences.keys),
            categoryConfidences: categoryConfidences,
            aestheticsScore: aestheticsScore,
            isUtilityImage: isUtilityImage,
            analyzerVersion: AssetAnalysis.currentVersion
        )
    }

    // MARK: - よく撮れてる度(iOS 18以降のみ)

    /// 【2026-09-05追加】CalculateImageAestheticsScoresRequest(iOS 18で追加されたVisionのAPI)を使い、
    /// 「よく撮れてる度」(-1〜1、高いほど良い)と「実用目的の画像らしいか」を判定する。
    /// iOS 17以下ではこのAPI自体が存在しないため、`#available` で確実に分岐し、判定せず (nil, nil) を返す
    /// (設計書の指示どおり「iOS18未満では選択肢を出さない」。呼び出し側〔FilterOptionsView〕も
    /// iOS 18未満ではこの機能に関する選択肢自体を表示しない)。
    /// 解析に失敗した場合(壊れた画像等)も同様に (nil, nil) とし、他の判定(雰囲気・カテゴリ)には
    /// 影響させない(この判定だけが「おまけ」的に付加される位置づけのため)。
    private static func analyzeAesthetics(cgImage: CGImage) async -> (score: Double?, isUtility: Bool?) {
        guard #available(iOS 18.0, *) else { return (nil, nil) }
        let request = CalculateImageAestheticsScoresRequest()
        let ciImage = CIImage(cgImage: cgImage)
        do {
            let observation = try await request.perform(on: ciImage)
            return (Double(observation.overallScore), observation.isUtility)
        } catch {
            // 一時的な解析失敗(メモリ逼迫等)。この写真自体を「判定不能」扱いにする必要は無く、
            // 「よく撮れてる度」の情報だけが無い状態として扱う(雰囲気・カテゴリの判定結果は活かす)。
            return (nil, nil)
        }
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
        //
        // 【2026-09-04調整:「緑」「鮮やか」がほとんど出ない件】
        // 実機で「暖色・寒色はしっかり出たが、緑・鮮やかは1枚しか出なかった」という報告を受けての調整。
        // 原因は「写真1枚まるごとの平均色」という判定方法そのものの性質にある。緑や鮮やかな被写体は
        // 写真の中の一部分であることが多く(例:芝生の上の犬。犬自体・空・地面の色と混ざって平均される)、
        // 画面全体を平均するとその色は薄まってしまい、平均色だけでは「緑」「鮮やか」の代表的なしきい値に
        // なかなか届かない。写真の一部分だけを見る判定(領域ごとの色分布など)に作り替えれば精度は上げられるが、
        // 実装量が増える大きめの変更になるため、今回は行っていない(報告書に改善案として記載)。
        // CEO判断(2026-09-04): 精度よりヒット数を優先し、「拾いすぎる側に倒す」方針をさらに強めてよい
        // (的外れな判定が増えるのは許容する。むしろ「犬を選んだのに違う結果が出る」ような意外性も歓迎)。
        // これを受け、無彩色寄り(モノトーン・淡い)に逃がす範囲を絞り、色相での判定に回る写真を増やし、
        // 「緑」の色相範囲を広げ、「鮮やか」に必要な彩度も下げた。
        //  - 明度(b) < 0.25: 暗所・夜景など、画面全体が暗いと感じられる目安として「暗め」判定
        //  - 明度(b) > 0.85 かつ 彩度(s) < 0.2: 白背景に近いくらい明るく色味が薄い時に「明るめ」判定
        //  - 彩度(s) < 0.15: ほぼ無彩色(白黒グレー)とみなせる目安で「モノトーン」判定
        //  - 彩度(s) < 0.22: 上より色はあるがまだ淡い程度の目安で「淡い」判定(旧0.35→0.22。
        //    ここで「淡い」に回ってしまう写真が多すぎ、緑・鮮やかにたどり着けていなかったため引き下げ)
        // これらに当てはまらない場合のみ、下の色相(hue)による暖色・寒色・緑の判定に進む。
        if b < 0.25 { return .dark }
        if b > 0.85 && s < 0.2 { return .bright }
        if s < 0.15 { return .monotone }
        if s < 0.22 { return .pastel }

        // 色相(0〜1)で暖色/寒色を判定。0=赤,0.17=黄,0.33=緑,0.5=シアン,0.66=青,0.83=マゼンタ
        // 「鮮やか」に必要な彩度は 0.5 → 0.4 に下げた(平均色は個々の鮮やかな被写体より
        // 彩度が低く出がちなため)。
        //
        // 【2026-09-05更新:「緑」を選択肢から削除(CEO判断。FixedChoices.swift参照)】
        // 以前は色相0.18〜0.48の帯を専用の「緑」に振り分けていたが、その選択肢自体をUIから
        // 無くしたため、この帯の写真を判定不能のまま迷子にしないよう、隣接する「暖色」「寒色」に
        // 振り分け直した(彩度が高ければ「鮮やか」が優先されるのは他の帯と同じ)。
        // 帯の中間(0.32付近)を境に、黄緑寄り(暖色に近い)を暖色、青緑寄り(寒色に近い)を寒色とした。
        switch h {
        case 0.0..<0.16, 0.94...1.0:
            return s > 0.4 ? .vivid : .warm
        case 0.16..<0.32:
            return s > 0.4 ? .vivid : .warm
        case 0.32..<0.7:
            return s > 0.4 ? .vivid : .cool
        default:
            return s > 0.4 ? .vivid : .cool
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

    private static func analyzeCategories(cgImage: CGImage) -> [CategoryTag: Double]? {
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        let classifyRequest = VNClassifyImageRequest()
        let animalRequest = VNRecognizeAnimalsRequest()
        let humanRequest = VNDetectHumanRectanglesRequest()

        // 3つのリクエストを1回のハンドラでまとめて実行(画像デコードを使い回す)
        do {
            try handler.perform([classifyRequest, animalRequest, humanRequest])
        } catch {
            // 【2026-09-04発見・修正】以前は try? でここのエラーを黙って握りつぶしていたため、
            // Vision側の一時的な失敗(メモリ逼迫・対応できない画像形式など)が起きても
            // 「カテゴリ0件」という"正常な結果"として扱われ、呼び出し側(CandidateEngine)が
            // それをそのままAnalysisCacheへ永久保存してしまっていた。本当は該当する写真でも、
            // たまたま解析に失敗した1回のせいで二度と該当しない扱いになる不具合の原因だった。
            // ここでは nil を返し、「判定できなかった」であることを呼び出し側に伝える
            // (呼び出し側はこれをキャッシュせず、次に選ばれた時にもう一度判定し直す)。
            return nil
        }

        var confidences: [CategoryTag: Double] = [:]

        // 犬・猫(専用検出。VNRecognizeAnimalsRequest)
        if let animalResults = animalRequest.results {
            for observation in animalResults {
                for label in observation.labels where label.confidence >= dedicatedConfidenceThreshold {
                    // 1を足して一般分類(0〜1)と区別し、候補選択側が専用検出を確実に優先できるようにする。
                    if label.identifier == "Dog" { confidences[.dog] = max(confidences[.dog] ?? 0, 1 + Double(label.confidence)) }
                    if label.identifier == "Cat" { confidences[.cat] = max(confidences[.cat] ?? 0, 1 + Double(label.confidence)) }
                }
            }
        }

        // 人(専用検出。VNDetectHumanRectanglesRequest = 体の存在検出。誰かの特定は行わない)
        if let humanResults = humanRequest.results, !humanResults.isEmpty {
            confidences[.person] = 2
        }

        // それ以外は一般分類のキーワード一致で拾う(拾いすぎる側に倒す)
        if let classifications = classifyRequest.results {
            for tag in CategoryTag.allCases where tag != .person {
                let keywords = tag.generalClassifierKeywords
                let matchingConfidences = classifications.compactMap { observation -> Float? in
                    guard observation.confidence >= generalConfidenceThreshold else { return nil }
                    let identifier = observation.identifier.lowercased()
                    return keywords.contains(where: { identifier.contains($0) }) ? observation.confidence : nil
                }
                if let confidence = matchingConfidences.max() {
                    confidences[tag] = max(confidences[tag] ?? 0, Double(confidence))
                }
            }
        }

        return confidences
    }
}
