import Foundation

/// 国ごとの豆知識(最大10個)を保持する。
///
/// 【content状況・重要】trivia.jsonには現時点で主要8カ国分しか用意していない。
/// 193カ国×10個=1,930個を今夜だけで正確に作るのは、事実確認の観点で無理を
/// しないことにした【判断】。データの無い国は「準備中」と表示する(存在しない
/// カードを作らないのと同じ考え方で、不確かな豆知識を推測で埋めない)。
@MainActor
final class TriviaDatabase: ObservableObject {
    static let shared = TriviaDatabase()

    private struct TriviaFile: Codable {
        let countries: [String: [String]]
    }

    private let factsByIso3: [String: [String]]

    private init() {
        guard let url = Bundle.main.url(forResource: "trivia", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(TriviaFile.self, from: data) else {
            self.factsByIso3 = [:]
            return
        }
        self.factsByIso3 = file.countries
    }

    /// この国の豆知識(用意されていなければnil)。
    func facts(for iso3: String) -> [String]? {
        factsByIso3[iso3]
    }
}
