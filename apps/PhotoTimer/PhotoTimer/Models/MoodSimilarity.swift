import Foundation

/// 「雰囲気(色)」タグ同士がどれくらい近いかの目安表。
///
/// 【2026-09-05追加(CEO判断):候補の出し方を「満たす/満たさない」から「近い順」に変更】
/// 「鮮やか×犬」のように該当が少ない組み合わせを選ぶと、以前は1枚も見つからず
/// 「見つかりませんでした」になってしまっていた。今は「どれだけ条件に近いか」を点数化し、
/// 高い順に流すことで必ず何か表示されるようにする(詳細はCandidateEngine.swift参照)。
///
/// ここではその「近さ」のうち雰囲気(色)の軸を担当する。写真の色は最終的に固定8種類
/// (実際にUIで選べるのは7種類。緑は選択肢から削除済み)のどれか1つに分類されるため、
/// 「選んだ雰囲気」と「写真の雰囲気」が完全一致しない時に、どれくらい近いとみなすかを
/// あらかじめ決めておく必要がある。
///
/// 【原則1】この表は固定値であり、写真を見なくても用意できる(事前解析不要)。
/// 【なぜ数値解析ではなく手動の目安表か】ImageAnalyzerのしきい値と同じ考え方で、
/// 色相・彩度・明度のどれで近いと感じるかという経験則にもとづく目安であり、
/// 精度を追い込む種類の数値ではない(=多少ずれても実害が小さい)。
enum MoodSimilarity {

    /// 2つの雰囲気タグの近さ(1.0=完全一致、0.0に近いほど正反対)。
    static func similarity(_ a: MoodTag, _ b: MoodTag) -> Double {
        if a == b { return 1.0 }
        let key = a.rawValue < b.rawValue ? "\(a.rawValue)|\(b.rawValue)" : "\(b.rawValue)|\(a.rawValue)"
        // 表に無い組み合わせ(基本的に無いはずだが保険)は「あまり近くない」を既定値にする。
        return table[key] ?? 0.1
    }

    /// キーは "小さい方のrawValue|大きい方のrawValue"(文字列比較順)で統一し、登録漏れ・重複を防ぐ。
    private static let table: [String: Double] = [
        pair(.warm, .vivid): 0.6,
        pair(.warm, .pastel): 0.5,
        pair(.warm, .bright): 0.4,
        pair(.warm, .cool): 0.05,
        pair(.warm, .monotone): 0.1,
        pair(.warm, .dark): 0.1,

        pair(.cool, .vivid): 0.5,
        pair(.cool, .pastel): 0.5,
        pair(.cool, .bright): 0.4,
        pair(.cool, .monotone): 0.15,
        pair(.cool, .dark): 0.2,

        pair(.monotone, .pastel): 0.4,
        pair(.monotone, .dark): 0.35,
        pair(.monotone, .bright): 0.3,
        pair(.monotone, .vivid): 0.05,

        pair(.pastel, .bright): 0.5,
        pair(.pastel, .dark): 0.05,
        pair(.pastel, .vivid): 0.15,

        pair(.vivid, .bright): 0.35,
        pair(.vivid, .dark): 0.1,

        pair(.bright, .dark): 0.02,
    ]

    private static func pair(_ a: MoodTag, _ b: MoodTag) -> String {
        a.rawValue < b.rawValue ? "\(a.rawValue)|\(b.rawValue)" : "\(b.rawValue)|\(a.rawValue)"
    }
}
