import SwiftUI

struct CardDetailSheet: View {
    let card: Card
    let country: Country?
    var body: some View { CardDetailOverlay(card: card, country: country) }
}
