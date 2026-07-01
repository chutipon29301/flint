// Tools/ImageCompress/ImageCompressView.swift
// Image Compressor UI — D-01, D-04, D-05, D-09, D-10, INFRA-14, INFRA-15, INFRA-17.
// Multi-file drop surface + DropOverlayView + quality slider/presets + live results table.

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ImageCompressView: View {
    @State private var viewModel: ImageCompressViewModel

    /// Drag targeting state for the DropOverlayView animation.
    @State private var isDragTargeted = false

    /// Quality persisted across launches via @AppStorage (MEMORY.md pitfall: never bind to a
    /// computed PreferencesStore property — writes drop silently). Default 75 = Email preset.
    @AppStorage("imageCompressQuality") private var quality: Double = 75

    init() {
        _viewModel = State(initialValue: ImageCompressViewModel())
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Tool title — Subhead 15pt semibold, matches HashView .headline idiom
                Text("Image Compressor")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.primary)

                qualitySection
                resultsSection
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .toolShortcuts(viewModel)
        // D-01 multi-file drop: iterates ALL providers via DispatchGroup (Hash reads the first only;
        // this tool iterates every provider for batch compression).
        // Source: 05-RESEARCH.md Code Examples L391-413
        .onDrop(of: [.fileURL], isTargeted: $isDragTargeted) { providers in
            var urls: [URL] = []
            let group = DispatchGroup()
            // CR-01: loadItem callbacks fire concurrently on background queues; Array is not
            // thread-safe for concurrent append. Serialize all mutations through this queue.
            let urlsQueue = DispatchQueue(label: "com.flint.imagecompress.drop")
            for provider in providers {
                group.enter()
                _ = provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    defer { group.leave() }
                    if let data = item as? Data,
                       let url = URL(dataRepresentation: data, relativeTo: nil) {
                        urlsQueue.sync { urls.append(url) }
                    }
                }
            }
            // quality / 100.0 maps 0-100 slider to ImageIO 0.0-1.0 (RESEARCH lines 369-378).
            // WR-03: clamp — a corrupt @AppStorage value bypasses the Slider and could send
            // ImageIO a quality outside 0.0–1.0.
            let capturedQuality = min(max(quality / 100.0, 0.0), 1.0)
            group.notify(queue: .main) {
                Task { @MainActor in
                    // GAP 6: drops accumulate — append onto the existing finished batch so re-dropping
                    // the same image adds a row (and writes -compressed-1) instead of replacing it.
                    viewModel.compress(urls: urls, quality: capturedQuality, append: true)
                }
            }
            return true
        }
        .overlay {
            if isDragTargeted {
                DropOverlayView(label: "Drop images to compress")
                    .transition(.opacity.animation(.easeOut(duration: 0.15)))
            }
        }
    }

    // MARK: - Quality Controls (D-04 / D-05)

    /// Lossless gate: slider disabled when the ENTIRE current batch is lossless (PNG/TIFF).
    /// In a mixed/empty batch the slider stays enabled (applies to lossy members).
    private var isEntirelyLossless: Bool {
        !viewModel.rows.isEmpty && viewModel.rows.allSatisfy { $0.format.isLossless }
    }

    /// Live slider quality mapped to ImageIO's 0.0–1.0 range (mirrors the compress call-site clamp,
    /// line 62 / WR-03). Compared against viewModel.lastRunQuality to detect a pending quality change.
    private var mappedQuality: Double {
        min(max(quality / 100.0, 0.0), 1.0)
    }

    /// Whether to surface the explicit "Re-compress at {n}%" affordance (05-08, GAP 2 / D-04).
    /// Compress-on-drop is immediate, so a changed slider can never reach the already-dropped batch;
    /// this button is the ONLY re-run trigger (no .onChange auto-spew — T-05-08A locked decision).
    /// Shown only when: a batch exists, no batch is currently running, the live quality differs from
    /// the last run, AND the batch is not entirely lossless (for PNG/TIFF the slider doesn't apply, so
    /// a quality-only change is meaningless — keep it hidden per the locked decision, D-05).
    private var shouldShowRecompress: Bool {
        !viewModel.rows.isEmpty
            && !viewModel.isCompressing
            && !isEntirelyLossless
            && mappedQuality != viewModel.lastRunQuality
    }

    @ViewBuilder
    private var qualitySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Label row: "Quality" left, "{n}%" right
            HStack {
                Text("Quality")
                    .font(.system(size: 13))
                    .foregroundStyle(isEntirelyLossless ? Color.secondary : Color.primary)
                Spacer()
                Text("\(Int(quality))%")
                    .font(.system(size: 13))
                    .foregroundStyle(isEntirelyLossless ? Color.secondary : Color.primary)
            }

            // Slider: 0-100 integer steps; quality / 100.0 applied at compress call site
            Slider(value: $quality, in: 0...100, step: 1)
                .disabled(isEntirelyLossless)
                .accessibilityLabel("Compression quality")
                .accessibilityValue("\(Int(quality)) percent")
                .accessibilityHint(isEntirelyLossless ? "Disabled — the dropped images are lossless" : "")

            // Lossless helper line (D-05) — shown when entirely lossless batch
            if isEntirelyLossless {
                Text("PNG and TIFF are lossless — they're re-encoded, but quality doesn't apply.")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.secondary)
            }

            // Three presets (D-04): Web=60, Email=75, Max=95
            HStack(spacing: 8) {
                presetButton(label: "Web", value: 60)
                presetButton(label: "Email", value: 75)
                presetButton(label: "Max", value: 95)
            }

            // Choose Images… secondary affordance (optional per plan)
            HStack {
                Button("Choose Images\u{2026}") {
                    chooseImages()
                }
                .accessibilityLabel("Choose Images from file picker")
            }
        }
    }

    @ViewBuilder
    private func presetButton(label: String, value: Double) -> some View {
        let isActive = Int(quality) == Int(value)
        let button = Button(label) {
            quality = value
        }
        if isActive {
            button.buttonStyle(.borderedProminent)
                .accessibilityLabel("\(label) quality preset")
                .accessibilityHint("Sets quality to \(Int(value)) percent")
                .accessibilityAddTraits(.isSelected)
        } else {
            button.buttonStyle(.bordered)
                .accessibilityLabel("\(label) quality preset")
                .accessibilityHint("Sets quality to \(Int(value)) percent")
                .accessibilityAddTraits([])
        }
    }

    // MARK: - Results Section (D-09)

    @ViewBuilder
    private var resultsSection: some View {
        if viewModel.rows.isEmpty {
            // Empty state
            Text("Drop images here to compress them.")
                .font(.system(size: 13))
                .foregroundStyle(Color.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 8)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                // Results heading + optional Cancel button
                HStack {
                    Text("Results")
                        .font(.system(size: 15, weight: .semibold))
                    Spacer()
                    if viewModel.isCompressing {
                        Button("Cancel") {
                            viewModel.cancel()
                        }
                        .foregroundStyle(Color.red)
                        .accessibilityLabel("Cancel compression")
                    } else if shouldShowRecompress {
                        // Explicit re-run affordance (05-08). Mutually exclusive with Cancel:
                        // shouldShowRecompress requires !isCompressing, so only one is ever visible.
                        // The button press is the ONLY re-compression trigger (no auto-spew, T-05-08A).
                        Button("Re-compress at \(Int(quality))%") {
                            viewModel.recompress(quality: mappedQuality)
                        }
                        .accessibilityLabel("Re-compress at \(Int(quality)) percent")
                    }
                    // GAP 7: Clear resets the results list back to the empty drop-prompt state (wires
                    // the existing clearInput()). Shown whenever a finished batch exists; hidden while
                    // compressing (Cancel owns that state).
                    if !viewModel.isCompressing {
                        Button("Clear") {
                            viewModel.clearInput()
                        }
                        .accessibilityLabel("Clear results")
                    }
                }

                // Results table container — matches HashView fileHashSection idiom
                VStack(spacing: 0) {
                    ForEach(Array(viewModel.rows.enumerated()), id: \.element.id) { index, row in
                        if index > 0 {
                            Divider()
                        }
                        rowView(for: row)
                    }
                }
                .padding(10)
                .background(.quaternary.opacity(0.3))
                .cornerRadius(8)
            }
        }
    }

    // MARK: - Results Row (D-09)

    @ViewBuilder
    private func rowView(for row: CompressRow) -> some View {
        HStack(spacing: 8) {
            // (1) Thumbnail — 40×40pt, cornerRadius 4, fill-clipped
            // NSImage loaded lazily in the View (never the Transformer — per 05-UI-SPEC)
            thumbnailView(for: row.sourceURL)
                .accessibilityHidden(true)  // decorative; row label conveys the file

            // (2) Name + format tag
            VStack(alignment: .leading, spacing: 2) {
                Text(row.sourceURL.lastPathComponent)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(row.format.displayTag)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.secondary)
            }

            Spacer()

            // (3)+(4) State-driven trailing content
            trailingContent(for: row)
        }
        .frame(minHeight: 56)
        // Combined a11y element per row (INFRA-15)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(rowAccessibilityLabel(for: row))
    }

    /// WR-02: NSImage(contentsOf:) is synchronous main-thread disk I/O, re-run on every row
    /// re-render. Cache per-URL so a batch reads each source image once, not per state change.
    /// ponytail: NSCache (auto-evicting, thread-safe) over a hand-rolled dictionary.
    private static let thumbnailCache = NSCache<NSURL, NSImage>()

    private func thumbnail(for url: URL) -> NSImage? {
        if let cached = Self.thumbnailCache.object(forKey: url as NSURL) { return cached }
        guard let image = NSImage(contentsOf: url) else { return nil }
        Self.thumbnailCache.setObject(image, forKey: url as NSURL)
        return image
    }

    @ViewBuilder
    private func thumbnailView(for url: URL) -> some View {
        if let nsImage = thumbnail(for: url) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        } else {
            // Placeholder while loading or if unreadable
            RoundedRectangle(cornerRadius: 4)
                .fill(.quaternary)
                .frame(width: 40, height: 40)
        }
    }

    @ViewBuilder
    private func trailingContent(for row: CompressRow) -> some View {
        switch row.state {
        case .pending:
            Text("—")
                .font(.system(size: 13))
                .foregroundStyle(Color.secondary)

        case .compressing:
            ProgressView()
                .scaleEffect(0.6)
                .accessibilityLabel("Compressing \(row.sourceURL.lastPathComponent)\u{2026}")

        case .done(let img):
            HStack(spacing: 4) {
                // "{orig} → {new}" monospaced Body 13pt secondary
                Text(sizeDeltaText(original: img.originalBytes, compressed: img.compressedBytes))
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(Color.secondary)

                // "% saved" Caption 11pt semibold — green when saved, secondary when grew
                Text(percentSavedText(img.percentSaved))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(img.percentSaved > 0 ? Color.green : Color.secondary)
            }

        case .failed(let reason):
            WarningBannerView(message: reason, severity: .warning)
        }
    }

    // MARK: - Formatting Helpers

    private func sizeDeltaText(original: Int, compressed: Int) -> String {
        let fmt = ByteCountFormatter()
        fmt.countStyle = .file
        fmt.allowedUnits = [.useKB, .useMB, .useGB]
        return "\(fmt.string(fromByteCount: Int64(original))) \u{2192} \(fmt.string(fromByteCount: Int64(compressed)))"
    }

    private func percentSavedText(_ percentSaved: Double) -> String {
        let n = Int(abs(percentSaved).rounded())
        if percentSaved > 0 {
            return "\u{2212}\(n)%"  // "−42%" (Unicode minus sign per UI-SPEC)
        } else if percentSaved < 0 {
            return "+\(n)%"
        } else {
            return "0%"
        }
    }

    private func rowAccessibilityLabel(for row: CompressRow) -> String {
        let filename = row.sourceURL.lastPathComponent
        let format = row.format.displayTag
        switch row.state {
        case .pending:
            return "\(filename), \(format), pending"
        case .compressing:
            return "Compressing \(filename)\u{2026}"
        case .done(let img):
            let n = Int(abs(img.percentSaved).rounded())
            let fmt = ByteCountFormatter()
            fmt.countStyle = .file
            let newSize = fmt.string(fromByteCount: Int64(img.compressedBytes))
            return "\(filename): saved \(n) percent, \(newSize)"
        case .failed(let reason):
            return "\(filename): \(reason)"
        }
    }

    // MARK: - File Picker (optional secondary affordance)

    private func chooseImages() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.png, .jpeg, .heic, .tiff]
        panel.message = "Choose images to compress"
        panel.prompt = "Compress"

        if panel.runModal() == .OK, !panel.urls.isEmpty {
            viewModel.compress(urls: panel.urls, quality: quality / 100.0)
        }
    }
}
