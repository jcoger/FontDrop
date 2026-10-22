import Foundation

/// Sample copy for the templates, copied from the Paper boards. A made-up company ("Acme"), no real clients.
/// Numbers and times are written the way a real page would write them, so figure spacing shows.
enum TemplateCopy {
    // Article A, Essay
    static let essayKicker = "Essay \u{00B7} Craft"
    static let essayHeadline = "The quiet details people remember"
    static let essayStandfirst = "Small decisions in type and spacing add up to how a place feels."
    static let essayByline = "By Alex Morgan \u{00B7} 6 min read \u{00B7} 12 March 2026"
    static let essayQuote = "\u{201C}Decide once, then let the details repeat.\u{201D}"
    static let essayQuoteBy = "Sam Ito, type director"
    static let essayHeading = "1. Set the measure"
    static let essayMeasure = "Aim for 60 to 75 characters a line. In 2024 we tested 1,280 pages; at 66 characters, readers finished 18% more of each article."
    static let essayFigure = "Fig. 1"
    static let essayFigureCaption = "Completion by line length, 1,280 pages, 2024."

    // Article B, Feature
    static let featureKicker = "Feature"
    static let featureIssue = "No. 14"
    static let featureHeadline = "Built to be read twice"
    static let featureDeck = "What a 90-year-old timetable teaches about hierarchy, rhythm and the cost of one extra weight."
    static let featureDropCap = "T"
    static let featureOpening = "he timetable had one job. Get a stranger to the right platform in under ten seconds, in poor light, with luggage."
    static let featureSecond = "So every choice was earned. Times in one weight, places in another. Nothing bold that was not urgent."
    static let featureColumn = "Read the columns today and the logic holds. Departures 06:40, 07:15, 08:05 line up because the figures share one width."
    static let timetable: [(String, String)] = [("Lisbon", "06:40"), ("Porto", "07:15"), ("Coimbra", "08:05")]
    static let featureClosing = "One extra weight would have cost a second of every reader\u{2019}s day."

    // Hero A, Statement
    static let nav = ["Work", "Studio", "Journal", "Contact"]
    static let statementHeadline = "Rooms that remember you."
    static let statementSub = "Small hotels in old buildings, run by people who live upstairs."
    static let statementPrimary = "Book a stay"
    static let statementSecondary = "See rooms"

    // Hero B, Product
    static let productBadge = "New in spring: the 2026 field kit"
    static let productHeadline = "Everything you need to plan a trip, in one quiet place."
    static let productSub = "Routes, bookings and notes that stay out of your way until you need them."
    static let productPrimary = "Start free"
    static let productSecondary = "Watch the 2-min tour"
    static let productStats: [(String, String)] = [
        ("48,210", "Trips planned last month"),
        ("4.9", "Rating from 3,104 reviews"),
        ("$0", "To start, no card needed"),
    ]

    // App UI A, Detail
    static let phoneTime = "9:41"
    static let phoneTab = "Trip"
    static let detailDates = "Fri 14 \u{2013} Sun 16 March"
    static let detailTitle = "Weekend in Porto"
    static let detailRows: [(title: String, sub: String, value: String, flagged: Bool)] = [
        ("Train to Porto", "Lisbon Oriente \u{00B7} Car 4, seat 31", "07:15", false),
        ("Casa do Rio", "2 nights \u{00B7} Room 11", "\u{20AC}318.00", false),
        ("Dinner, Cantinho", "Confirm by Thursday", "20:30", true),
    ]
    static let detailTotal = "Total"
    static let detailTotalValue = "\u{20AC}412.40"
    static let detailShare = "Share itinerary"
    static let detailEdit = "Edit"

    // App UI B, Dashboard
    static let sidebarItems = ["Overview", "Bookings", "Guests", "Payouts"]
    static let sidebarGroup = "Houses"
    static let sidebarHouses = ["Casa do Rio", "Quinta Alta"]
    static let dashboardTitle = "Overview"
    static let dashboardMonth = "March 2026"
    static let dashboardLabel = "Revenue this month"
    static let dashboardRevenue = "\u{20AC}24,860"
    static let dashboardDelta = "+12.4%"
    static let dashboardHeaders = ["Guest", "Nights", "Amount"]
    static let dashboardRows: [(String, String, String)] = [
        ("Rui Almeida", "3", "\u{20AC}477.00"),
        ("Hannah Okafor", "11", "\u{20AC}1,749.00"),
        ("Lena Fischer", "2", "\u{20AC}318.00"),
        ("Tom\u{00E1}s Ib\u{00E1}\u{00F1}ez", "7", "\u{20AC}1,113.00"),
    ]

    // Poster A, Event
    static let eventLeft = ["Acme Talks", "Season 3"]
    static let eventRight = ["Free entry", "Doors 18:30"]
    static let eventTitle = ["Slow", "Type"]
    static let eventLine = "An evening on letters that take their time."
    static let eventDate = "14.03"
    static let eventPlace = ["The Old Print Works", "Rua das Flores 28, Porto"]

    // Poster B, Specimen
    static let specimenSub = "Specimen 01"
    static let specimenGlyphs = "Ag"
    static let specimenAmp = "&"
    static let specimenLine = "Harbour lights at 06:40"
    static let specimenRamp: [(String, Double)] = [("Thin", 100), ("Light", 300), ("Regular", 400), ("Bold", 700), ("Black", 900)]
    static let specimenSet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ abcdefghijklmnopqrstuvwxyz 0123456789 (&?!) \u{20AC}$\u{00A3}"
    static let specimenNote = "One face with a long memory, set beside a plain companion that keeps the small print honest."

    // Poster C, Readout
    static let readoutWord = "Kiln"
    static let readoutLine = "Fired slow, glazed by hand & sold at 9:00"
    static let readoutBody = ["Studio sale every first Saturday. Bowls, cups and the odd failed vase, 06.04 to 07.12.",
                              "Kiln Ceramics, Rua do Almada 112, Porto. Cash and card."]

    // Poster D, Blocks
    static let blocksTop = "Acme Studio"
    static let blocksWord = "Paloma"
    static let blocksSpring = ["Spring", "menu"]
    static let blocksOpen = ["Open", "Thu\u{2013}Sun"]
    static let blocksSign = ["Mesa", "Paloma"]

    // Poster E, Layered
    static let layeredWord = ["Late", "Night", "Radio"]
    static let layeredList: [(String, String)] = [
        ("22:00", "Open with the windows down"), ("22:14", "Harbour lights"), ("22:31", "Night bus to Matosinhos"),
        ("22:47", "A slow waltz for nobody"), ("23:02", "Tide tables"), ("23:15", "Neon over Bolh\u{00E3}o"),
        ("23:29", "The long way home"), ("23:41", "Rain on the Ribeira"), ("23:58", "Last call"),
        ("00:12", "Quiet hours"), ("00:26", "Fog horn, low"), ("00:40", "Second shift"),
        ("00:53", "Kitchen radio"), ("01:07", "Small hours, big room"), ("01:20", "Lanterns"),
        ("01:34", "Before the bakers"), ("01:49", "Sleepwalk"), ("02:03", "The night porter"),
        ("02:18", "Blue hour, early"), ("02:30", "Sign off"),
    ]
    static let layeredFoot = "Fridays on 97.4"
    static let layeredStation = "Acme Radio"
}
