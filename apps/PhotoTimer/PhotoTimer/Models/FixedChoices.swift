import Foundation

// MARK: - 固定選択肢の定義
//
// 【なぜここで固定リストにしているか】
// 設計方針の「原則1: 選択肢は固定リストにする。マスタを事前に作らない」に基づく。
// 色・雰囲気・カテゴリは「その人の写真を見なくても用意できる」選択肢なので、
// 起動時に写真を解析してリストを作ることはしない。フリー入力も一切使わない。

/// 雰囲気・色の選択肢(固定8種類)
/// 判定は「選ばれた時に、流しながら」行う(原則2)。ここでは選択肢の定義だけ。
enum MoodTag: String, CaseIterable, Identifiable, Codable {
    case warm = "暖色"
    case cool = "寒色"
    case monotone = "モノトーン"
    case vivid = "鮮やか"
    case pastel = "淡い"
    case green = "緑"
    case bright = "明るめ"
    case dark = "暗め"

    var id: String { rawValue }
}

/// カテゴリの選択肢(固定20種類)。
/// 「犬・猫・人」だけVisionの専用検出機能を使い、それ以外は一般分類を使う(2026-09-04方針)。
/// サンプル解析は並べ替えにのみ使い、この一覧自体を絞り込む(隠す)ことはしない。
enum CategoryTag: String, CaseIterable, Identifiable, Codable {
    case dog = "犬"
    case cat = "猫"
    case person = "人"
    case food = "食べ物"
    case drink = "飲み物"
    case flower = "花"
    case sky = "空"
    case sea = "海"
    case mountain = "山"
    case snow = "雪"
    case night = "夜景"
    case fireworks = "花火"
    case building = "建物・街並み"
    case vehicle = "乗り物"
    case sport = "スポーツ"
    case otherAnimal = "動物(犬猫以外)"
    case nature = "自然・植物"
    case document = "書類・テキスト"
    case art = "アート・イラスト"
    case music = "音楽・楽器"

    var id: String { rawValue }

    /// 専用の検出機能(高精度)を使うかどうか。それ以外は一般分類(拾いすぎる側に倒す)。
    var hasDedicatedDetector: Bool {
        switch self {
        case .dog, .cat, .person: return true
        default: return false
        }
    }

    /// 一般分類(Vision の VNClassifyImageRequest)が返すラベルとの対応表。
    /// Apple側のラベル体系は非公開・変動があるため、それらしい単語を広めに拾う(見逃し防止優先)。
    var generalClassifierKeywords: [String] {
        switch self {
        case .dog: return ["dog", "puppy"]
        case .cat: return ["cat", "kitten"]
        case .person: return [] // 専用検出器(VNDetectHumanRectanglesRequest)を使うため未使用
        case .food: return ["food", "meal", "dessert", "fruit", "vegetable", "dish", "cuisine", "bakery", "snack"]
        case .drink: return ["beverage", "drink", "coffee", "tea", "cocktail", "wine", "beer"]
        case .flower: return ["flower", "blossom", "petal", "bouquet"]
        case .sky: return ["sky", "cloud", "sunset", "sunrise", "horizon"]
        case .sea: return ["ocean", "sea", "beach", "coast", "wave", "shore"]
        case .mountain: return ["mountain", "hill", "peak", "valley"]
        case .snow: return ["snow", "ski", "winter", "snowman", "blizzard"]
        case .night: return ["night", "nightclub", "dark sky"]
        case .fireworks: return ["fireworks", "firework"]
        case .building: return ["building", "architecture", "skyline", "cityscape", "street", "urban", "house", "bridge"]
        case .vehicle: return ["car", "vehicle", "train", "airplane", "bicycle", "motorcycle", "boat", "ship", "bus"]
        case .sport: return ["sport", "athlete", "stadium", "ball", "soccer", "baseball", "basketball", "golf", "tennis"]
        case .otherAnimal: return ["bird", "fish", "horse", "animal", "wildlife", "insect", "reptile", "rabbit"]
        case .nature: return ["nature", "forest", "tree", "landscape", "park", "garden", "leaf", "plant"]
        case .document: return ["document", "text", "paper", "receipt", "screenshot", "menu", "book", "newspaper"]
        case .art: return ["art", "illustration", "painting", "drawing", "sculpture", "graffiti"]
        case .music: return ["music", "guitar", "piano", "instrument", "concert", "microphone"]
        }
    }
}

/// メディアの種類フィルタ(標準メタ情報。解析不要=即時取得)
enum MediaTypeFilter: String, CaseIterable, Identifiable, Codable {
    case all = "すべて"
    case photo = "写真"
    case video = "動画"
    case livePhoto = "Live Photo"

    var id: String { rawValue }
}

/// 日時フィルタのプリセット(標準メタ情報)
enum DateRangeFilter: Equatable, Codable {
    case all
    case thisYear
    case thisMonth
    case custom(from: Date, to: Date)
}
