import Foundation

/// Main API for the AI-powered news companion.
public enum NewsCompanionKit {

    public struct Config: Sendable {
        public var apiKey: String
        public var model: String?
        public var articleFetcher: (any ArticleFetching)?
        public var timeout: TimeInterval
        public var maxArticleLength: Int
        public var debugLog: (@Sendable (String) -> Void)?

        public init(
            apiKey: String,
            model: String? = nil,
            articleFetcher: (any ArticleFetching)? = nil,
            timeout: TimeInterval = 60,
            maxArticleLength: Int = 12_000,
            debugLog: (@Sendable (String) -> Void)? = nil
        ) {
            self.apiKey = apiKey
            self.model = model
            self.articleFetcher = articleFetcher
            self.timeout = timeout
            self.maxArticleLength = maxArticleLength
            self.debugLog = debugLog
        }
    }

    /// Creates a GroqClient for the given config.
    static func makeAIClient(config: Config) -> any AICompleting {
        return GroqClient(
            apiKey: config.apiKey,
            model: config.model ?? "llama-3.1-8b-instant",
            timeout: config.timeout
        )
    }

    /// Translates English text to the target language using Groq. Use for TTS when the target language is not English.
    public static func translate(text: String, targetLanguageCode: String, targetLanguageName: String, config: Config) async throws -> String {
        let prompt = """
        You are a translator. Translate the following English text into \(targetLanguageName). Output only the \(targetLanguageName) translation, nothing else: no quotes, no "Translation:", no explanation.

        Text to translate:
        \(text)
        """
        let client = makeAIClient(config: config)
        let result = try await client.complete(prompt: prompt)
        var translated = result.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["Translation:", "Here is the translation:", "Here's the translation:", "\(targetLanguageName) translation:"] {
            if translated.lowercased().hasPrefix(prefix.lowercased()) {
                translated = String(translated.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }
        return translated
    }

    public static func generate(url: URL, config: Config) async throws -> CompanionResult {
        do {
            config.debugLog?("[Groq] request starting – url: \(url.absoluteString)")
            let fetcher: any ArticleFetching = config.articleFetcher ?? ArticleFetcher(config: .init(maxArticleLength: config.maxArticleLength))
            let article = try await fetcher.fetch(url: url)
            config.debugLog?("Article fetched – title: \(article.title.prefix(60))...")
            guard !article.text.trimmingCharacters(in: .whitespaces).isEmpty else {
                throw NewsCompanionKitError.emptyArticle
            }
            config.debugLog?("Calling Groq (\(config.model ?? "default model"))...")
            let aiClient = makeAIClient(config: config)
            let engine = ConversationEngine(aiClient: aiClient, maxArticleChars: config.maxArticleLength)
            let result = try await engine.generate(article: article)
            config.debugLog?("[Groq] response OK – oneLiner: \(result.summary.oneLiner.prefix(80))...")
            return result
        } catch {
            config.debugLog?("[Groq] failed – \(error.localizedDescription)")
            throw error
        }
    }

    // MARK: - App 2 (audio-only, no sheet): result fetcher with optional cache

    /// Optional cache for companion results. Implement this (e.g. with SwiftData, UserDefaults, or in-memory) and pass to `resultFetcher(config:cache:)` so App 2 avoids refetching. Pass `nil` for no caching.
    public protocol CompanionResultCaching: AnyObject {
        func cachedResult(for url: URL) async -> CompanionResult?
        func save(result: CompanionResult, for url: URL) async
    }

    /// Returns a closure that fetches a companion result for a URL: uses cache when provided and returns a cached result when available, otherwise calls `generate(url:config:)` and optionally saves.
    public static func resultFetcher(config: Config, cache: (any CompanionResultCaching)?) -> (URL) async throws -> CompanionResult {
        { url in
            if let cache = cache, let cached = await cache.cachedResult(for: url) {
                return cached
            }
            let result = try await generate(url: url, config: config)
            if let cache = cache {
                await cache.save(result: result, for: url)
            }
            return result
        }
    }
}

public enum NewsCompanionKitError: Error {
    case emptyArticle
}
