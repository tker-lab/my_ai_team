import Foundation

/// 国ごとの豆知識(最大10個)を保持する。
///
/// 【content状況】2026-09-14に国連加盟193カ国全カ国分(10個ずつ)を用意済み。
/// 万が一データの無い国があっても「準備中」と表示する(存在しないカードを
/// 作らないのと同じ考え方で、不確かな豆知識を推測で埋めない)。
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
