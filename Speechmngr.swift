//
//  Speechmngr.swift
//  duo 2
//
//  Created by Devdhathan M D on 8/27/25.
//

import Foundation
import AVFoundation
import RiveRuntime

// MARK: – Duolingo-Style Mouth Sync Using OpenAI "onyx" TTS
class SpeechManager: ObservableObject {
    weak var mainVM: RiveViewModel?
    private var audioPlayer: AVAudioPlayer?
    private var mouthTimer: Timer?
    
    /// Nested viseme sequences, one subarray per word
    private var mouthSequencesByWord: [[Int]] = []
    private var currentWordIndex = 0
    private var currentVisemeIndexInWord = 0
    
    @Published var duration: TimeInterval = 0
    var cmuDict: [String: [String]] = [:]

    private let apiKey = "Key"
    private let voice = "echo"

    init(mainVM: RiveViewModel) {
        self.mainVM = mainVM
        loadCMUDict()
    }

    func speak(_ text: String, onStart: @escaping (TimeInterval) -> Void = { _ in }) {
        Task {
            do {
                // 1) Fetch TTS from OpenAI
                let url = URL(string: "https://api.openai.com/v1/audio/speech")!
                var req = URLRequest(url: url)
                req.httpMethod = "POST"
                req.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                req.addValue("application/json", forHTTPHeaderField: "Content-Type")
                let payload: [String: Any] = [
                    "model": "gpt-4o-mini-tts",
                    "voice": voice,
                    "input": text
                ]
                req.httpBody = try JSONSerialization.data(withJSONObject: payload)

                let (data, resp) = try await URLSession.shared.data(for: req)
                guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
                    throw URLError(.badServerResponse)
                }

                // 2) Configure audio session to use the loudspeaker
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playAndRecord,
                                        mode: .default,
                                        options: [.defaultToSpeaker])
                try session.overrideOutputAudioPort(.speaker)
                try session.setActive(true)

                // 3) Play the TTS audio
                audioPlayer = try AVAudioPlayer(data: data)
                audioPlayer?.volume = 1.0
                audioPlayer?.prepareToPlay()
                audioPlayer?.play()
                let audioDuration = audioPlayer?.duration ?? 1.0
                await MainActor.run {
                    self.duration = audioDuration
                    onStart(audioDuration)
                }

                // 4) Generate and play mouth visemes (stress‐weighted, grouped by word)
                mouthSequencesByWord = generateVisemesByWord(from: text)
                currentWordIndex = 0
                currentVisemeIndexInWord = 0
                DispatchQueue.main.async {
                    self.scheduleNextViseme()
                }
            } catch {
                print("TTS error:", error)
            }
        }
    }

    // MARK: - Stress‐Weighted, Word-Grouped Viseme Generation

    /// Generates a nested viseme sequence (`[[Int]]`), one subarray per word,
    /// using ARPABET stress markers to repeat frames.
    private func generateVisemesByWord(from reply: String) -> [[Int]] {
        let phonemeToViseme: [String: Int] = [   // ───── VOWELS (with CMUdict stress stripped) ─────
        // 0: “OW”‐shape (rounded, mid‐back)
        "OW":  0,   // “oat”
        "AO":  1,   // “ought”  (AO is often closer to “AA” but we’ll put it in 1)
        "AA":  1,   // “odd”
        "AE":  1,   // “apple”
        "AH":  1,   // “hut”
        "AW":  1,   // “cow”  (diphthong: start open, move to “OW”)
        "AY":  2,   // “hide” (diphthong: “AH”→“IY”)
        "EH":  2,   // “Ed”
        "EY":  2,   // “ate” (dipthong: “EH”→“IY”)
        "IH":  2,   // “bit”
        "IY":  2,   // “beet”
        "UW":  8,   // “two”   (rounded, high‐back)
        "UH":  8,   // “hood” (similar lip rounding as UW)
        "ER":  7,   // “hurt” (rhotic, “er” shape)
        "OY":  0,   // “toy”  (dipthong: “OW”→“IY”, but use OW‐shape as start)

        // ───── CONSONANTS ─────
        // 4: “B/P/M” (bilabial closed)
        "B":   11,   // “bat”
        "P":   11,   // “pie”
        "M":   11,   // “man”

        // 6: “CH/JH/SH/ZH” (postalveolar fricatives/affricates)
        "CH":  6,   // “cheese”
        "JH":  6,   // “judge”
        "SH":  6,   // “she”
        "ZH":  6,   // “measure”

        // 5: “F/V” (labiodental)
        "F":   5,   // “fish”
        "V":   5,   // “van”

        // 9: “D/G/K/S/Z/N/W/Y” (alveolar+velar+glides, “neutral” or slight spread)
        "D":   9,   // “dog”
        "G":   9,   // “go”
        "K":   9,   // “kite”
        "N":   9,   // “no”
        "NG":  9,   // “sing”
        "S":   9,   // “sit”
        "Z":   9,   // “zoo”
        "W":   9,   // “we”
        "Y":   9,   // “yes”

        // 10: “TH/DH” (interdental)
        "TH": 10,   // “think”
        "DH": 10,
        "T": 12,// “this”

        // 3: “L” (alveolar lateral)
        "L":   3,   // “light”

        // 7: “R” (alveolar retroflex)
        "R":   7,   // “run”

        // 2: “EH/IH/IY” already grouped above

        // 1: “AA/AE/AH/AO/AW” grouped above
    ]

        var byWord: [[Int]] = []
        let rawWords = reply
            .uppercased()
            .components(separatedBy: .whitespacesAndNewlines)

        for raw in rawWords {
            // Strip out non-letter characters: e.g. "HELLO!" → "HELLO"
            let cleaned = raw
                .components(separatedBy: CharacterSet.letters.inverted)
                .joined()
            guard !cleaned.isEmpty else { continue }

            if let phonemes = cmuDict[cleaned] {
                var seq: [Int] = []

                for p in phonemes {
                    if let lastChar = p.last,
                       let stressVal = Int(String(lastChar)),
                       (0...2).contains(stressVal) {
                        // e.g. p = "AH0", "OW1", "EH2"
                        let core = String(p.dropLast()) // e.g. "AH", "OW", "EH"
                        let visemeID = phonemeToViseme[core] ?? 4

                        // Determine repeats by stress:
                        let repeats: Int
                        switch stressVal {
                        case 0: repeats = 1
                        case 1: repeats = 2
                        case 2: repeats = 2
                        default: repeats = 1
                        }
                        for _ in 0..<repeats {
                            seq.append(visemeID)
                        }
                    } else {
                        // No stress digit → treat as unstressed
                        let core = p
                        let visemeID = phonemeToViseme[core] ?? 4
                        seq.append(visemeID)
                    }
                }

                if seq.isEmpty {
                    seq = [4] // fallback neutral if nothing mapped
                }


                byWord.append(seq)
            } else {
                // Word not found in CMUdict → single neutral viseme
                byWord.append([4])
            }
        }

        return byWord
    }

    // MARK: - Scheduling Viseme Frames

    /// Schedules the next viseme frame. Uses one-shot timers so that each
    /// frame duration can be recalculated when moving between words.
    private func scheduleNextViseme() {
        mouthTimer?.invalidate()
        guard let duration = audioPlayer?.duration,
              currentWordIndex < mouthSequencesByWord.count else {
            stop()
            return
        }

        let wordCount = mouthSequencesByWord.count
        let durationPerWord = duration / Double(wordCount)
        let currentSequence = mouthSequencesByWord[currentWordIndex]
        let framesInWord = currentSequence.count
        guard framesInWord > 0 else {
            stop()
            return
        }

        let interval = durationPerWord / Double(framesInWord)

        // Determine which viseme ID to show
        let visemeID = currentSequence[currentVisemeIndexInWord]
        mainVM?.setInput("Visme", value: Double(visemeID))

        // Schedule a non-repeating timer for the next frame
        mouthTimer = Timer.scheduledTimer(withTimeInterval: interval,
                                          repeats: false) { [weak self] _ in
            guard let self = self else { return }
            self.currentVisemeIndexInWord += 1

            if self.currentVisemeIndexInWord < framesInWord {
                // Still in the same word: schedule the next frame in this word
                self.scheduleNextViseme()
            } else {
                // Move to the next word
                self.currentWordIndex += 1
                self.currentVisemeIndexInWord = 0
                if self.currentWordIndex < self.mouthSequencesByWord.count {
                    self.scheduleNextViseme()
                } else {
                    self.stop()
                }
            }
        }

        RunLoop.main.add(mouthTimer!, forMode: .common)
    }

    func stop() {
        mouthTimer?.invalidate()
        mainVM?.setInput("Visme", value: 4.0) // neutral mouth
    }

    // MARK: - CMUdict Loading

    private func loadCMUDict() {
        if let url = Bundle.main.url(forResource: "cmudict", withExtension: "txt") {
            do {
                // Try ASCII encoding first
                let content = try String(contentsOf: url, encoding: .ascii)
                for line in content.components(separatedBy: .newlines) {
                    if line.hasPrefix(";;;") { continue }
                    let parts = line.split(separator: " ")
                    guard parts.count > 1 else { continue }
                    let word = String(parts[0])
                    let phonemes = parts.dropFirst().map(String.init)
                    cmuDict[word] = phonemes
                }
            } catch {
                // Fallback to Latin-1 if ASCII fails
                do {
                    let contentLatin1 = try String(contentsOf: url, encoding: .isoLatin1)
                    for line in contentLatin1.components(separatedBy: .newlines) {
                        if line.hasPrefix(";;;") { continue }
                        let parts = line.split(separator: " ")
                        guard parts.count > 1 else { continue }
                        let word = String(parts[0])
                        let phonemes = parts.dropFirst().map(String.init)
                        cmuDict[word] = phonemes
                    }
                } catch {
                    print("❌ Failed reading cmudict.txt:", error)
                }
            }
        } else {
            print("⚠️ cmudict.txt not found in bundle.")
        }
    }
}

