import SwiftUI

/// What a template receives: the brand name and the two faces, each with the playground
/// settings. A template draws only from this, so it works on Reading cards today and on Set later.
struct PairContext {
    let brand: String
    let display: FaceSpec
    let body: FaceSpec
    let tick: Int

    /// Text in the Display face at a role size (1.0 = the Display base size).
    func headline(_ text: String, _ ratio: CGFloat = 1) -> FaceText {
        FaceText(face: display, text: text, ratio: ratio, tick: tick)
    }
    /// Text in the Reading face at a role size (1.0 = the Reading base size).
    func text(_ text: String, _ ratio: CGFloat = 1) -> FaceText {
        FaceText(face: body, text: text, ratio: ratio, tick: tick)
    }
}

/// One presentation template: a name and a function from context to a view.
///
/// To add a template: create one file in this folder with a small `View` that takes a
/// `PairContext` and a `static let descriptor`, then add that descriptor to `Templates.all`.
/// React: a registry of `{ id, label, render }` entries.
struct TemplateDescriptor: Identifiable {
    let id: String
    let title: String
    let make: (PairContext) -> AnyView
}

enum Templates {
    static let all: [TemplateDescriptor] = [
        ArticleTemplate.descriptor,
        HeroTemplate.descriptor,
        AppUITemplate.descriptor,
        PosterTemplate.descriptor,
    ]

    static func descriptor(_ id: String) -> TemplateDescriptor { all.first { $0.id == id } ?? all[0] }
}

/// Short sample copy for playground previews and the Set placeholder. Neutral on purpose.
enum SampleCopy {
    static let paragraphs = [
        "Book a table for four and we hold it until you arrive. Your name is on the list, the kitchen knows, and the first round is already poured.",
        "They know the window seat is yours and the music stays low. Nothing to confirm, nothing to repeat.",
    ]
    static let displayHeadline = "Good things, held warm."
}

/// Neutral sample copy for templates. No client names.
enum TemplateCopy {
    static let articleHeadline = "The quiet details people remember"
    static let articleDeck = "Small decisions in type and spacing add up to how a place feels."
    static let byline = "By Alex Morgan \u{00B7} 6 min read"
    static let paragraphs = [
        "Good typography works the way good service does. You notice it when it is missing. A line that breathes, a number that lines up, a heading that sits where the eye expects it.",
        "Start with one face you trust for long reading, then let a second face carry the headlines. The pair should feel decided, not accidental.",
    ]
    static let pullQuote = "\u{201C}Decide once, then let the details repeat.\u{201D}"

    static let heroHeadline = "Make the first impression the lasting one"
    static let heroSub = "A calmer way to plan, track and share your work with the people who need it."
    static let heroPrimary = "Get started"
    static let heroSecondary = "See how it works"
    static let heroSmall = "Free for 14 days. No card needed."

    static let cardTitle = "Weekly summary"
    static let cardBody = "Three tasks are due this week. Two are on track."
    static let cardMeta = "Updated 9:41 AM"
    static let rows: [(String, String, String)] = [
        ("Design review", "Tuesday", "12"),
        ("Client call", "Wednesday", "4"),
        ("Ship update", "Friday", "28"),
    ]
    static let field = "Email address"
    static let fieldValue = "name@example.com"

    static let posterCaption = "Spring season \u{00B7} Doors at seven"
    static let posterNumbers = "No. 24  2026  1,280"
}
