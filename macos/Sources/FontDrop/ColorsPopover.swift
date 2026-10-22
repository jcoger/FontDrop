import AppKit
import SwiftUI

extension AppModel {
    /// The brand's three template colors. Paper until the designer sets them.
    var palette: TemplatePalette { brandStyle.palette(brand: brandID) }

    /// The template Reading draws, with this brand's colors and the chosen layout filled in.
    var activeTemplate: TemplateDescriptor {
        let base = Templates.descriptor(templateID)
        return base.configured(palette: palette, variant: brandStyle.variant(base))
    }
}

/// The layout menu beside the template picker: Essay or Feature, Statement or Product, and so on.
/// The choice is remembered per template.
struct TemplateVariantPicker: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let template = Templates.descriptor(model.templateID)
        Picker(Lexicon.Colors.layoutLabel, selection: Binding(
            get: { model.brandStyle.variant(template) },
            set: { model.brandStyle.setVariant($0, template: template) })) {
            ForEach(template.variants) { Text($0.title).tag($0.id) }
        }
        .pickerStyle(.menu).fixedSize()
        .help(Lexicon.Colors.layoutHelp)
        .accessibilityLabel(Lexicon.Colors.layoutLabel)
    }
}

/// "Colors" with three overlapping dots: the brand's background, text and accent. Opens the popover.
struct ColorsButton: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var style = model.brandStyle
        let p = model.palette
        Button { style.showColors.toggle() } label: {
            HStack(spacing: 6) {
                HStack(spacing: -4) {
                    ForEach([p.background, p.text, p.accent], id: \.hex) { c in
                        Circle().fill(c.color).frame(width: 12, height: 12)
                            .overlay(Circle().strokeBorder(Color.white, lineWidth: 1))
                            .overlay(Circle().strokeBorder(.quaternary, lineWidth: 0.5))
                    }
                }
                Text(Lexicon.Colors.button)
            }
        }
        .help(Lexicon.Colors.buttonHelp)
        .accessibilityLabel(Lexicon.Colors.button)
        .accessibilityValue(p.presetID.map { $0.capitalized } ?? "Custom")
        .popover(isPresented: $style.showColors, arrowEdge: .bottom) {
            ColorsPopover().environment(model)
        }
    }
}

/// The popover: presets, the three roles, the contrast line. Clicking a role opens the color field under it.
struct ColorsPopover: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var style = model.brandStyle
        let p = model.palette
        VStack(alignment: .leading, spacing: 14) {
            presets(p)
            Divider()
            VStack(spacing: 2) {
                ForEach(ColorRole.allCases) { role in
                    roleRow(role, p)
                    if style.editingRole == role {
                        ColorField(color: Binding(
                            get: { model.palette[keyPath: role.keyPath] },
                            set: { model.brandStyle.setColor(role, $0, brand: model.brandID) }),
                                   recents: style.recents,
                                   onCommit: { model.brandStyle.remember($0) })
                            .padding(.top, 6).padding(.bottom, 10)
                            .transition(.opacity)
                    }
                }
            }
            contrast(p)
            footer
        }
        .padding(14)
        .frame(width: 300)
        .background(MatchAppAppearance())
    }

    // MARK: Presets

    private func presets(_ current: TemplatePalette) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Lexicon.Colors.presets).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                ForEach(TemplatePalette.presets) { preset in
                    let selected = current == preset.palette
                    Button { model.brandStyle.setPalette(preset.palette, brand: model.brandID) } label: {
                        VStack(spacing: 4) {
                            tile(preset.palette)
                                .overlay(RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(selected ? Color.accentColor : Color.secondary.opacity(0.3),
                                                  lineWidth: selected ? 2 : 1))
                            Text(preset.name).font(.caption).foregroundStyle(.primary)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Lexicon.Colors.presetLabel(preset.name, selected: selected))
                }
            }
        }
    }

    /// "Aa" in the Display face on the preset's background, with a dot of its accent.
    private func tile(_ p: TemplatePalette) -> some View {
        HStack(spacing: 3) {
            Group {
                if let face = model.displayFace {
                    FaceText(face: face, text: "Aa", ratio: 16 / CGFloat(face.settings.size), tick: model.fontTick, useLineHeight: false)
                } else {
                    Text("Aa").font(.system(size: 16, design: .serif))
                }
            }
            .foregroundStyle(p.text.color)
            Circle().fill(p.accent.color).frame(width: 5, height: 5)
        }
        .frame(width: 52, height: 36)
        .background(RoundedRectangle(cornerRadius: 6).fill(p.background.color))
    }

    // MARK: Roles

    private func roleRow(_ role: ColorRole, _ p: TemplatePalette) -> some View {
        let color = p[keyPath: role.keyPath]
        let open = model.brandStyle.editingRole == role
        return Button {
            withAnimationIfAllowed { model.brandStyle.editingRole = open ? nil : role }
        } label: {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 5).fill(color.color)
                    .frame(width: 22, height: 22)
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.quaternary))
                Text(role.title).font(.callout)
                Spacer()
                Text(color.hex).font(.caption.monospaced()).foregroundStyle(.secondary)
                Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(open ? 90 : 0))
            }
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Lexicon.Colors.swatchLabel(role.title, color.hex))
        .accessibilityHint(Lexicon.Colors.swatchHint(role.title))
        .accessibilityValue(open ? "expanded" : "collapsed")
    }

    // MARK: Contrast and footer

    private func contrast(_ p: TemplatePalette) -> some View {
        let band = p.contrastBand
        let tint: Color = switch band { case .fine: .green; case .largeOnly: .orange; case .tooLow: .red }
        return HStack(spacing: 8) {
            Image(systemName: Lexicon.Colors.bandSymbol(band)).foregroundStyle(tint)
            Text(Lexicon.Colors.contrast(ContrastBand.display(p.contrastRatio))).font(.caption)
            Spacer()
            Text(Lexicon.Colors.band(band)).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.5)))
        .accessibilityElement(children: .combine)
    }

    /// "Use brand colors" appears only for a brand that has colors of its own. None do yet, so it is hidden.
    private var footer: some View {
        HStack {
            Spacer()
            Text(Lexicon.Colors.savedTo(model.brand?.name ?? "your brand")).font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// A popover window can open with the system appearance while the app is set to the other one
/// (the screenshot runner does this). This copies the app's appearance onto the popover's window.
private struct MatchAppAppearance: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async {
            if let appearance = NSApp.appearance { view.window?.appearance = appearance }
        }
    }
}
