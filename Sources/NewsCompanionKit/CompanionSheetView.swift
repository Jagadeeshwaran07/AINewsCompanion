import SwiftUI

/// Presents the AI companion UI for an article: skeleton → one-liner, bullets, why it matters, topic chips.
public struct CompanionSheetView: View {

    public enum LoadingState {
        case loading
        case loaded(CompanionResult)
        case failed(String)
    }

    private let url: URL
    private let config: NewsCompanionKit.Config
    /// When provided, used instead of calling the API directly (e.g. cache-first fetch). If nil, uses `NewsCompanionKit.generate(url:config:)`.
    private let generateCompanion: ((URL) async throws -> CompanionResult)?
    private let onDismiss: (() -> Void)?
    private let onTopicTap: ((TopicChip) -> Void)?
    private let onTelemetry: ((TelemetryEvent) -> Void)?
    /// Called when a companion result has been successfully loaded (from cache or API). Use to persist the result so audio can play without re-opening the sheet.
    private let onCompanionLoaded: ((CompanionResult) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var viewState: LoadingState = .loading
    @State private var startTime: Date?

    public init(
        url: URL,
        config: NewsCompanionKit.Config,
        generateCompanion: ((URL) async throws -> CompanionResult)? = nil,
        onDismiss: (() -> Void)? = nil,
        onTopicTap: ((TopicChip) -> Void)? = nil,
        onTelemetry: ((TelemetryEvent) -> Void)? = nil,
        onCompanionLoaded: ((CompanionResult) -> Void)? = nil
    ) {
        self.url = url
        self.config = config
        self.generateCompanion = generateCompanion
        self.onDismiss = onDismiss
        self.onTopicTap = onTopicTap
        self.onTelemetry = onTelemetry
        self.onCompanionLoaded = onCompanionLoaded
    }

    public var body: some View {
        Group {
            if #available(iOS 16.0, *) {
                NavigationStack { sheetContent }
            } else {
                NavigationView { sheetContent }
                #if os(iOS)
                .navigationViewStyle(.stack)
                #endif
            }
        }
        .task { await load() }
    }

    @ViewBuilder
    private var sheetContent: some View {
        Group {
            switch viewState {
            case .loading:
                SkeletonLoadingView()
            case .loaded(let result):
                CompanionContentView(result: result, onTopicTap: onTopicTap, onTelemetry: onTelemetry)
            case .failed(let message):
                FallbackView(message: message)
            }
        }
        .navigationTitle("AI Companion")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done", action: dismissSheet)
            }
        }
    }

    private func dismissSheet() {
        dismiss()
        onDismiss?()
    }

    private func failureMessage(for error: Error) -> String {
        if (error as NSError).domain == NSURLErrorDomain {
            switch (error as NSError).code {
            case NSURLErrorNotConnectedToInternet:
                return "No internet connection. Check your network and try again."
            case NSURLErrorTimedOut:
                return "Request timed out. Try again."
            default:
                return "Network error: \(error.localizedDescription)"
            }
        }
        if let clientError = error as? AIClientError {
            switch clientError {
            case .apiError(let msg):
<<<<<<< Updated upstream
                let isAuthLike = msg.lowercased().contains("api key") || msg.lowercased().contains("invalid") || msg.contains("403") || msg.lowercased().contains("access denied") || msg.lowercased().contains("authentication")
                if isAuthLike, config.provider == .awsBedrock {
                    return "AWS Bedrock requires IAM credentials (SigV4), not an API key. Use a proxy that accepts an API key and forwards to Bedrock. See README."
                }
                if isAuthLike {
                    return "Invalid or missing API key. Set your \(config.provider.displayName) key in ApiKeys.xcconfig and try again."
=======
                if msg.lowercased().contains("api key") || msg.lowercased().contains("invalid") || msg.contains("403") {
                    return "Invalid or missing API key. Set your Groq key in ApiKeys.xcconfig and try again."
>>>>>>> Stashed changes
                }
                return "API error: \(msg)"
            case .invalidResponse:
                return "Invalid response from the AI service. Try again."
            }
        }
        if error is NewsCompanionKitError {
            return "Could not extract article content from this URL. The page may be paywalled or blocked."
        }
        if let conv = error as? ConversationEngineError {
            switch conv {
            case .aiFailed(let underlying):
                return failureMessage(for: underlying)
            case .invalidJSON:
                return "The AI could not format a summary. Try again or use another article."
            }
        }
        return "Unable to generate summary: \(error.localizedDescription)"
    }

    @MainActor
    private func load() async {
        startTime = Date()
        onTelemetry?(.aiIconClicks)
        do {
            let result: CompanionResult
            if let fetch = generateCompanion {
                result = try await fetch(url)
            } else {
                result = try await NewsCompanionKit.generate(url: url, config: config)
            }
            if let start = startTime {
                onTelemetry?(.timeToSummary(seconds: Date().timeIntervalSince(start)))
            }
            onTelemetry?(.summaryCompletionRate(success: true))
            viewState = .loaded(result)
            onCompanionLoaded?(result)
        } catch {
            onTelemetry?(.summaryCompletionRate(success: false))
            viewState = .failed(failureMessage(for: error))
        }
    }
}

// MARK: - Skeleton

private struct SkeletonLoadingView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.gray.opacity(0.25))
                .frame(height: 20)
                .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(0..<4, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.25))
                    .frame(height: 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.gray.opacity(0.25))
                .frame(height: 40)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Loaded content

private let topicSummaryScrollId = "topicSummary"

private struct CompanionContentView: View {
    let result: CompanionResult
    let onTopicTap: ((TopicChip) -> Void)?
    let onTelemetry: ((TelemetryEvent) -> Void)?

    @State private var selectedTopicIndex: Int?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(result.summary.oneLiner)
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)

                    if !result.summary.bullets.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(result.summary.bullets.enumerated()), id: \.offset) { _, bullet in
                                HStack(alignment: .top, spacing: 8) {
                                    Text("•")
                                        .font(.body)
                                    Text(bullet)
                                        .font(.subheadline)
                                }
                            }
                        }
                    }

                    if !result.summary.whyItMatters.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Why it matters")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(.secondary)
                            Text(result.summary.whyItMatters)
                                .font(.subheadline)
                        }
                    }

                    if !result.topics.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Explore")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(.secondary)
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], spacing: 8) {
                                ForEach(Array(result.topics.enumerated()), id: \.offset) { index, topic in
                                    let isSelected = selectedTopicIndex == index
                                    Button {
                                        if selectedTopicIndex == index {
                                            selectedTopicIndex = nil
                                        } else {
                                            selectedTopicIndex = index
                                            onTopicTap?(topic)
                                            onTelemetry?(.topicChipTaps)
                                        }
                                    } label: {
                                        Text(topic.title)
                                            .font(.caption)
                                            .lineLimit(2)
                                            .multilineTextAlignment(.center)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 8)
                                            .frame(maxWidth: .infinity, alignment: .center)
                                            .background(isSelected ? Color.accentColor.opacity(0.35) : Color.accentColor.opacity(0.15))
                                            .overlay(
                                                Capsule()
                                                    .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 2)
                                            )
                                            .clipShape(Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            if let idx = selectedTopicIndex, idx < result.topics.count {
                                let topic = result.topics[idx]
                                let summaryText = topic.summary.flatMap { s in s.isEmpty ? nil : s }
                                    ?? topic.prompt
                                if !summaryText.isEmpty {
                                    Text(summaryText)
                                        .font(.subheadline)
                                        .lineLimit(nil)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.top, 8)
                                        .padding(.horizontal, 4)
                                        .padding(.bottom, 16)
                                        .id(topicSummaryScrollId)
                                }
                            }
                        }
                    }
                }
                .padding()
                .padding(.bottom, 48)
            }
            .scrollDismissesKeyboard(.automatic)
            .onChange(of: selectedTopicIndex) { newValue in
                if newValue != nil {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            proxy.scrollTo(topicSummaryScrollId, anchor: .center)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Fallback

private struct FallbackView: View {
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Telemetry

public enum TelemetryEvent {
    case aiIconClicks
    case timeToSummary(seconds: TimeInterval)
    case summaryCompletionRate(success: Bool)
    case topicChipTaps
}
