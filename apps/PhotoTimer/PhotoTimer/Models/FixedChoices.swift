import Foundation

// MARK: - 固定選択肢の定義
//
// 【なぜここで固定リストにしているか】
// 設計方針の「原則1: 選択肢は固定リストにする。マスタを事前に作らない」に基づく。
// 色・雰囲気・カテゴリは「その人の写真を見なくても用意できる」選択肢なので、
// 起動時に写真を解析してリストを作ることはしない。フリー入力も一切使わない。

/// 雰囲気・色の選択肢。
/// 判定は「選ばれた時に、流しながら」行う(原則2)。ここでは選択肢の定義だけ。
///
/// 【2026-09-05 CEO判断:「緑」をUIの選択肢から削除】
/// 他の選択肢(暖色系・寒色系・モノトーン・鮮やか・淡い等)が「雰囲気」という軸なのに対し、
/// 「緑」だけ具体的な色を指していて浮いている、というCEOの指摘による。
/// ただし enum のケース自体は残してある。過去に保存された設定(FilterSettings.selectedMoods)や
/// 解析キャッシュ(AssetAnalysis.mood)に "緑" というraw valueが残っていた場合、ここでケースごと
/// 削除してしまうとJSONの読み込み(デコード)自体が失敗し、緑以外も含めた設定全体が消えてしまう
/// (Codableは列挙型の未知のraw valueを許容せずデコード全体を失敗させるため)。
/// ケースを残しつつ `allCases` だけ独自定義して選択肢一覧(UI)からは外すことで、
/// 「表示はしないが、古いデータを読んでも壊れない」という安全な削除ができる。
/// 保存済みの設定に緑が残っていた場合は FilterSettingsStore.load() 側で自動的に除去する
/// (詳細はそちらのコメント参照)。
enum MoodTag: String, Identifiable, Codable {
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

extension MoodTag: CaseIterable {
    /// UI(絞り込み画面のチップ一覧)に出す選択肢。「緑」は含めない(2026-09-05 CEO判断)。
    static var allCases: [MoodTag] { [.warm, .cool, .monotone, .vivid, .pastel, .bright, .dark] }
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

    /// Visionの一般分類ラベル(例: "carpet" "beach_ball")が、このカテゴリのキーワードに
    /// **単語として**一致するかどうか。
    ///
    /// 【2026-09-05修正:部分一致による誤爆】
    /// 以前は `identifier.contains(keyword)` という文字列の部分一致で判定していたため、
    /// 短いキーワードが無関係な語の一部にたまたま一致してしまっていた
    /// (例: "car" が "carpet"/"cartoon"/"carnival" に、"ball" が "balloon" に、
    /// "art" が "heart" に一致)。これは「見た目(写っているもの)が似ている」という
    /// カテゴリの緩さ(犬を選んだら羊が出る、等。CEO方針で維持)とは別種の、
    /// 「文字面がたまたま似ているだけ」の説明のつかない誤りなので、ここだけを直す。
    /// 信頼度のしきい値(呼び出し側のgeneralConfidenceThreshold/dedicatedConfidenceThreshold)は変更しない。
    ///
    /// 【単語単位への直し方】Visionのラベルは "beach_ball" のように単語をアンダースコアで
    /// つないだ形式で返ってくる。ラベル・キーワードの両方を「文字・数字以外(アンダースコア・
    /// 空白・ハイフン等)」で単語に分割し、キーワード側の単語の並びが、ラベル側の単語の並びの
    /// 中に(連続した部分列として)そのまま含まれているかで判定する。
    /// 1単語のキーワード("car"等)なら「単語一致」そのものになり、"carpet"のような
    /// 1単語に埋もれた部分一致は起こらなくなる。"dark sky"のような複数語キーワードも、
    /// 空白区切りで書いていても正しく複数単語として扱われる
    /// (以前は空白のままだったため、Visionの実際の区切り文字〔アンダースコア〕とは
    /// 表記が食い違い、そもそも一致しようがなかった。今回あわせて直る)。
    func matchesGeneralClassifierLabel(_ identifier: String) -> Bool {
        let labelWords = Self.words(in: identifier)
        return generalClassifierKeywords.contains { keyword in
            let keywordWords = Self.words(in: keyword)
            guard !keywordWords.isEmpty else { return false }
            return Self.containsSubsequence(keywordWords, in: labelWords)
        }
    }

    private static func words(in text: String) -> [String] {
        text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
    }

    /// `needle`(キーワードを単語分割したもの)が `haystack`(ラベルを単語分割したもの)の中に
    /// 連続した並びとしてそのまま含まれているかどうか。
    private static func containsSubsequence(_ needle: [String], in haystack: [String]) -> Bool {
        guard needle.count <= haystack.count else { return false }
        guard needle.count > 0 else { return false }
        for start in 0...(haystack.count - needle.count) {
            if Array(haystack[start..<(start + needle.count)]) == needle {
                return true
            }
        }
        return false
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
