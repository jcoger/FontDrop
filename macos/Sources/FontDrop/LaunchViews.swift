import AppKit
import SwiftUI

// The first thing a new install shows, and the plain empty state. Spec: "Launch" in the look doc, board 20.

/// First run, library scanning: a recessed scan screen with a Doto counter and a dot-matrix progress row,
/// the invitation to start, and two buttons that dismiss the screen into Display or Text.
struct ScanScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme

    private static let dots = 36

    var body: some View {
        let p = model.scanProgressNow
        let read = Int((p.fraction * Double(p.files)).rounded())
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(Lexicon.Launch.scanTitle).moduleLabel()
                    Spacer()
                    Text(Lexicon.Launch.percent(p.fraction)).moduleLabel()
                }
                HStack(alignment: .lastTextBaseline, spacing: 14) {
                    Text(verbatim: "\(read)").font(InstrumentFonts.doto(64)).foregroundStyle(theme.textPrimary.color)
                        .lineLimit(1).minimumScaleFactor(0.5).monospacedDigit()
                    if p.files > 0 {
                        Text(Lexicon.Launch.ofFiles(p.files, families: p.families)).moduleLabel().padding(.bottom, 8)
                    }
                }
                dotRow(fraction: p.fraction)
            }
            .padding(.horizontal, 24).padding(.vertical, 20)
            .frame(width: 560)
            .recessed(radius: 20)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Lexicon.Launch.scanAccessibility(p.fraction, read: read, of: p.files))

            VStack(spacing: 8) {
                Text(Lexicon.Launch.headline).font(.system(size: 22, weight: .semibold)).foregroundStyle(theme.textPrimary.color)
                Text(Lexicon.Launch.body).font(.system(size: 14)).foregroundStyle(theme.textSecondary.color)
                    .multilineTextAlignment(.center).frame(maxWidth: 400)
            }
            .padding(.top, 36)

            HStack(spacing: 10) {
                Button(Lexicon.Launch.startDisplay) { model.startWith(.display) }.buttonStyle(PrimaryButtonStyle(large: true))
                Button(Lexicon.Launch.startText) { model.startWith(.reading) }.buttonStyle(GlassButtonStyle(large: true))
            }
            .padding(.top, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.panelContent.color)
    }

    /// Lit dots are the files read, one red dot is where the scan is, the rest wait.
    private func dotRow(fraction: Double) -> some View {
        let lit = min(Int(fraction * Double(Self.dots)), Self.dots - 1)
        return HStack(spacing: 0) {
            ForEach(0..<Self.dots, id: \.self) { i in
                ZStack {
                    if i == lit {
                        Circle().fill(theme.signal.color).frame(width: 6, height: 6)
                            .modifier(Glow(layers: theme.signalGlow, color: theme.signal.color))
                    } else {
                        Circle().fill(i < lit ? theme.textPrimary.color : theme.sliderTrack.color).frame(width: 5, height: 5)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 10)
    }
}

/// The scan finished and found no fonts: say so, and point to Font Book.
struct EmptyLibraryState: View {
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "textformat").font(.system(size: 28, weight: .regular)).foregroundStyle(theme.textSecondary.color)
                .padding(.bottom, 6)
            Text(Lexicon.Launch.emptyTitle).font(.system(size: 17, weight: .semibold)).foregroundStyle(theme.textPrimary.color)
            Text(Lexicon.Launch.emptyBody).font(.system(size: 13)).foregroundStyle(theme.textSecondary.color)
                .multilineTextAlignment(.center).frame(maxWidth: 360)
            Button(Lexicon.Launch.openFontBook) {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Font Book.app"))
            }
            .buttonStyle(PrimaryButtonStyle(large: true))
            .padding(.top, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.panelContent.color)
    }
}
