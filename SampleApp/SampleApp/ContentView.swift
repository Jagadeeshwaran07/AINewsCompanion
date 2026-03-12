import SwiftUI
import SwiftData
import NewsCompanionKit
import SummaryToAudio

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var playbackController = SummaryPlaybackController()
    @State private var selectedTTSProvider: TTSProvider = Self.savedTTSProvider()
    @State private var selectedSarvamLanguage: SpeechLanguage = .english
    @State private var selectedElevenLabsLanguage: ElevenLabsLanguage = .english
    @State private var showLanguageSelection = false
    @ObservedObject private var speaker = SummaryToAudio.shared

    static func resolveAPIKey() -> String? {
        if let value = Bundle.main.object(forInfoDictionaryKey: "GROQ_API_KEY") as? String {
            let trimmed = value.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty, !trimmed.hasPrefix("YOUR_") { return trimmed }
        }
        return nil
    }

    private var effectiveSarvamAPIKey: String? {
        if let value = Bundle.main.object(forInfoDictionaryKey: "SARVAM_API_KEY") as? String {
            let trimmed = value.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty, !trimmed.hasPrefix("YOUR_") { return trimmed }
        }
        return nil
    }

    private var effectiveElevenLabsAPIKey: String? {
        if let value = Bundle.main.object(forInfoDictionaryKey: "ELEVENLABS_API_KEY") as? String {
            let trimmed = value.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty, !trimmed.hasPrefix("YOUR_") { return trimmed }
        }
        return nil
    }

    private static func libreTranslateURL() -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "LIBRETRANSLATE_URL") as? String else { return nil }
        let t = value.trimmingCharacters(in: .whitespaces)
        return t.isEmpty || t.hasPrefix("YOUR_") ? nil : t
    }

    private static func libreTranslateAPIKey() -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "LIBRETRANSLATE_API_KEY") as? String else { return nil }
        let t = value.trimmingCharacters(in: .whitespaces)
        return t.isEmpty || t.hasPrefix("YOUR_") ? nil : t
    }

    private static func savedTTSProvider() -> TTSProvider {
        guard let raw = UserDefaults.standard.string(forKey: "SummaryToAudioSelectedProvider"),
              let provider = TTSProvider(rawValue: raw) else { return .elevenLabs }
        return provider
    }

    private func saveTTSProvider(_ provider: TTSProvider) {
        UserDefaults.standard.set(provider.rawValue, forKey: "SummaryToAudioSelectedProvider")
        selectedTTSProvider = provider
        speaker.stop()
        speaker.clearReplayCache()
        speaker.configure(provider: provider, sarvamLanguage: selectedSarvamLanguage, elevenLabsLanguage: selectedElevenLabsLanguage)
    }

    private var effectiveTTSLanguage: EffectiveTTSLanguage {
        selectedTTSProvider == .sarvam
            ? .sarvam(selectedSarvamLanguage)
            : .elevenLabs(selectedElevenLabsLanguage)
    }

    private func setElevenLabsTranslatorIfNeeded() {
        guard let config = companionConfig else {
            SummaryToAudio.shared.setElevenLabsTranslator(nil)
            return
        }
        SummaryToAudio.shared.setElevenLabsTranslator { [config] text, languageCode in
            let name = ElevenLabsLanguage.allCases.first { $0.languageCode == languageCode }?.displayName ?? languageCode
            return try await NewsCompanionKit.translate(text: text, targetLanguageCode: languageCode, targetLanguageName: name, config: config)
        }
    }

    private var companionConfig: NewsCompanionKit.Config? {
        guard let key = Self.resolveAPIKey() else { return nil }
        var config = NewsCompanionKit.Config(apiKey: key)
        if CompanionDebug.isEnabled { config.debugLog = { CompanionDebug.log($0) } }
        return config
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("News Companion")
                .font(.title2)
                .fontWeight(.semibold)
                .padding(.top, 12)

            if Self.resolveAPIKey() == nil {
                Text("Groq API key missing. Check ApiKeys.xcconfig.")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
            }

            TabView {
                App1ListView(config: companionConfig, articles: skyArticleList)
                    .tabItem { Label("App 1", systemImage: "sparkles") }
                    .tag(0)

                VStack(spacing: 0) {
                    HStack(spacing: 16) {
                        Picker("TTS", selection: Binding(get: { selectedTTSProvider }, set: { saveTTSProvider($0) })) {
                            ForEach(TTSProvider.allCases, id: \.self) { provider in
                                Text(provider.displayName).tag(provider)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 8)

                    App2ListView(
                        config: companionConfig,
                        articles: skyArticleList,
                        playbackController: playbackController,
                        effectiveTTSLanguage: effectiveTTSLanguage,
                        isTTSEnabled: selectedTTSProvider == .sarvam ? (effectiveSarvamAPIKey != nil) : (effectiveElevenLabsAPIKey != nil),
                        onLongPress: { showLanguageSelection = true }
                    )
                }
                .tabItem { Label("App 2", systemImage: "speaker.wave.2") }
                .tag(1)
            }

            HStack(spacing: 16) {
                Spacer()
                Toggle(isOn: Binding(get: { CompanionDebug.isEnabled }, set: { CompanionDebug.isEnabled = $0 })) {
                    Text("Debug").font(.caption)
                }
                .toggleStyle(.switch)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            speaker.configure(
                provider: selectedTTSProvider,
                elevenLabsKey: effectiveElevenLabsAPIKey,
                sarvamKey: effectiveSarvamAPIKey,
                sarvamLanguage: selectedSarvamLanguage,
                elevenLabsLanguage: selectedElevenLabsLanguage,
                libreTranslateBaseURL: Self.libreTranslateURL(),
                libreTranslateAPIKey: Self.libreTranslateAPIKey()
            )
            setElevenLabsTranslatorIfNeeded()
        }
        .onChange(of: selectedTTSProvider) { _, _ in setElevenLabsTranslatorIfNeeded() }
        .onChange(of: selectedElevenLabsLanguage) { _, newLang in
            setElevenLabsTranslatorIfNeeded()
            playbackController.stopPlayback()
            speaker.clearReplayCache()
            speaker.configure(provider: selectedTTSProvider, sarvamLanguage: selectedSarvamLanguage, elevenLabsLanguage: newLang)
        }
        .onChange(of: selectedSarvamLanguage) { _, newLang in
            playbackController.stopPlayback()
            speaker.clearReplayCache()
            speaker.configure(provider: selectedTTSProvider, sarvamLanguage: newLang, elevenLabsLanguage: selectedElevenLabsLanguage)
        }
        .overlay {
            if showLanguageSelection {
                LanguageSelectionOverlay(
                    selectedTTSProvider: selectedTTSProvider,
                    selectedSarvamLanguage: $selectedSarvamLanguage,
                    selectedElevenLabsLanguage: $selectedElevenLabsLanguage,
                    isPresented: $showLanguageSelection
                )
            }
        }
    }
}

struct LanguageSelectionOverlay: View {
    let selectedTTSProvider: TTSProvider
    @Binding var selectedSarvamLanguage: SpeechLanguage
    @Binding var selectedElevenLabsLanguage: ElevenLabsLanguage
    @Binding var isPresented: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture { isPresented = false }

            VStack(spacing: 16) {
                Text(selectedTTSProvider == .elevenLabs ? "Select Language (ElevenLabs)" : "Select Language (Sarvam AI)")
                    .font(.headline)

                if selectedTTSProvider == .sarvam {
                    sarvamChips
                } else {
                    elevenLabsChips
                }
            }
            .frame(maxHeight: 400)
            .padding(24)
            .background(Color(.secondarySystemBackground))
            .cornerRadius(20)
            .shadow(radius: 20)
        }
    }

    private var sarvamChips: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                sarvamChip(.english)
                sarvamChip(.hindi)
                sarvamChip(.tamil)
            }
            HStack(spacing: 10) {
                sarvamChip(.telugu)
                sarvamChip(.malayalam)
                sarvamChip(.gujarati)
            }
        }
    }

    private func sarvamChip(_ lang: SpeechLanguage) -> some View {
        Button {
            selectedSarvamLanguage = lang
            isPresented = false
        } label: {
            Text(lang.displayName)
                .font(.subheadline)
                .fontWeight(.medium)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(selectedSarvamLanguage == lang ? Color.blue : Color.white)
                .foregroundStyle(selectedSarvamLanguage == lang ? .white : .primary)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.blue.opacity(0.3), lineWidth: selectedSarvamLanguage == lang ? 0 : 1)
                )
                .clipShape(Capsule())
        }
    }

    private var elevenLabsChips: some View {
        ScrollView(.vertical, showsIndicators: true) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], spacing: 8) {
                ForEach(ElevenLabsLanguage.allCases, id: \.self) { lang in
                    elevenLabsChip(lang)
                }
            }
            .padding(.vertical, 4)
        }
        .frame(maxHeight: 320)
    }

    private func elevenLabsChip(_ lang: ElevenLabsLanguage) -> some View {
        Button {
            selectedElevenLabsLanguage = lang
            isPresented = false
        } label: {
            Text("\(lang.displayName) (\(lang.languageCode))")
                .font(.subheadline)
                .fontWeight(.medium)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(selectedElevenLabsLanguage == lang ? Color.blue : Color.white)
                .foregroundStyle(selectedElevenLabsLanguage == lang ? .white : .primary)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.blue.opacity(0.3), lineWidth: selectedElevenLabsLanguage == lang ? 0 : 1)
                )
                .clipShape(Capsule())
        }
    }
}
