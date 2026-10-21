import FontDropCore
import SwiftUI

/// Draws `preferred` (a family name) in the font at `path`. The file is read off the
/// main thread; until it arrives the row reserves its height and shows nothing.
struct FontText: View {
    let path: String
    let preferred: String
    let size: CGFloat
    @State private var result: Result<FontLoader.Loaded, FontLoader.Failure>?

    var body: some View {
        let state = FontLoader.shared.load(cached: path) ?? result
        Group {
            switch state {
            case .success(let l)?:
                Text(l.sample).font(Font(l.font(size: size)))
            case .failure?:
                Text(preferred).font(.system(size: size)).foregroundStyle(.tertiary)
            case nil:
                Text(preferred).font(.system(size: size)).opacity(0)   // reserve the row height
            }
        }
        .lineLimit(1)
        .task(id: path) {
            if FontLoader.shared.load(cached: path) != nil { return }
            let p = path, t = preferred
            result = await Task.detached(priority: .userInitiated) {
                FontLoader.shared.load(path: p, preferredText: t)
            }.value
        }
    }
}

struct RootView: View {
    @State var store: Store
    let bench: Bool

    var body: some View {
        NavigationSplitView {
            SidebarView(store: store)
                .navigationSplitViewColumnWidth(min: 170, ideal: 200, max: 260)
        } content: {
            Group {
                switch store.mode {
                case .sidebar: FamilyListView(store: store)
                case .grid: FamilyGridView(store: store)
                case .flat: FlatListView(store: store)
                }
            }
            .navigationSplitViewColumnWidth(min: 340, ideal: 460, max: 760)
        } detail: {
            DetailView(store: store)
        }
        .task {
            await store.load()
            if CommandLine.arguments.contains("--refresh") { await store.refresh() }
        }
        .task(id: store.selection) {
            if let f = store.selected { await store.loadPairs(for: f) }
        }
        .task {
            let args = CommandLine.arguments
            if let i = args.firstIndex(of: "--screenshot"), i + 1 < args.count {
                await Bench.screenshot(store: store, path: args[i + 1])
            } else if bench {
                await Bench.run(store: store)
            }
        }
    }
}

struct SidebarView: View {
    @Bindable var store: Store
    var body: some View {
        List(selection: $store.mode) {
            Section("Browse") {
                ForEach(BrowseMode.allCases) { m in
                    Label(m.rawValue, systemImage: icon(m)).tag(m)
                }
            }
            Section("Load times") {
                ForEach(Array(store.timings.enumerated()), id: \.offset) { _, t in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(format: "%.1f ms", t.ms)).font(.callout.monospacedDigit())
                        Text(t.label).font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let e = store.loadError { Text(e).foregroundStyle(.red) }
            }
        }
    }
    func icon(_ m: BrowseMode) -> String {
        switch m {
        case .sidebar: "list.bullet"
        case .grid: "square.grid.2x2"
        case .flat: "textformat"
        }
    }
}

struct FamilyListView: View {
    @Bindable var store: Store
    var body: some View {
        List(store.families, selection: $store.selection) { f in
            VStack(alignment: .leading, spacing: 2) {
                FontText(path: f.filePath, preferred: f.name, size: 22)
                Text("\(f.name) · \(f.styleCount) styles · \(f.serif ? "serif" : f.skeleton)\(f.isTrial ? " · trial" : "")")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(.vertical, 3)
            .tag(f.id)
        }
        .navigationTitle("\(store.families.count) families")
    }
}

struct FamilyGridView: View {
    @Bindable var store: Store
    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 10)], spacing: 10) {
                ForEach(store.families) { f in
                    VStack(alignment: .leading, spacing: 6) {
                        FontText(path: f.filePath, preferred: f.name, size: 26)
                        Text(f.name).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(store.selection == f.id ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.05))
                    )
                    .onTapGesture { store.selection = f.id }
                }
            }
            .padding(12)
        }
        .navigationTitle("\(store.families.count) families")
    }
}

struct FlatListView: View {
    @Bindable var store: Store
    var body: some View {
        List(store.fonts) { f in
            VStack(alignment: .leading, spacing: 2) {
                FontText(path: f.filePath, preferred: f.name, size: 22)
                Text("\(f.name) · \(f.weight)").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.vertical, 3)
        }
        .navigationTitle("\(store.fonts.count) fonts")
    }
}

struct DetailView: View {
    let store: Store
    var body: some View {
        if let f = store.selected {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 4) {
                        FontText(path: f.filePath, preferred: f.name, size: 56)
                        Text("\(f.name) · \(f.styleCount) styles · skeleton \(f.skeleton)\(f.isTrial ? " · trial" : "")")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    if store.pairsLoading { ProgressView("Finding pairs") }
                    else if let e = store.pairsError { Text("font_pairs failed: \(e)").foregroundStyle(.red) }
                    else if store.buckets.isEmpty { Text("No pairs for this font.").foregroundStyle(.secondary) }
                    ForEach(store.buckets, id: \.label) { b in
                        BucketView(bucket: b)
                    }
                    if let ms = store.pairsMs {
                        Text(String(format: "font_pairs: %.0f ms (whole library scored in Rust)", ms))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            Text("Select a family").foregroundStyle(.secondary)
        }
    }
}

struct BucketView: View {
    let bucket: PairBucket
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(bucket.label).font(.headline)
                Text(bucket.description).font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(bucket.pairs, id: \.fontId) { p in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        FontText(path: p.filePath, preferred: p.family, size: 28)
                        Spacer()
                        Text("\(p.score)").font(.title3.monospacedDigit().weight(.semibold))
                    }
                    Text("\(p.family) · \(p.pairType) · \(p.reason)").font(.caption).foregroundStyle(.secondary)
                    ForEach(Array(p.evidence.enumerated()), id: \.offset) { _, e in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(e.effect >= 0 ? "+" : "−").font(.caption.monospaced().bold())
                                .foregroundStyle(e.effect >= 0 ? .green : .orange)
                            Text(e.lens).font(.caption.bold())
                            Text(e.detail).font(.caption)
                            Text("(\(e.strength))").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))
            }
        }
    }
}
