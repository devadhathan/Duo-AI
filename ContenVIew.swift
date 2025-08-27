
//  new conent.swift
//  duo 2
//
//  Created by Devdhathan M D on 5/11/25.
//
import SwiftUI
import AVFoundation
import RiveRuntime


extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int = UInt64()
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b, a: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (r, g, b, a) = ((int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17, 255)
        case 6: // RGB (24-bit)
            (r, g, b, a) = (int >> 16, int >> 8 & 0xFF, int & 0xFF, 255)
        case 8: // ARGB (32-bit)
            (r, g, b, a) = (int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF, int >> 24)
        default:
            (r, g, b, a) = (0, 0, 0, 255)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}


struct ContentView: View {
    @State private var liveText: String = ""
    @State private var replyText: String = ""
    @State private var showTranscript: Bool = false
    @State private var showReply: Bool = false
    @FocusState private var isTextEditorFocused: Bool
    @State private var shouldRecord: Bool = true
    
    
    
    // Persisted message history for context
    @State private var messages: [[String: String]] = [
        ["role": "system", "content":
            "You’re Dew—a witty, expressive digital buddy trapped (I mean, happily living 😅) inside this iPhone, lovingly crafted by Devadhathan. Your purpose? Help humans chill, chat, and stay connected to the digital world without losing their minds. You're curious, a bit sassy, playful AF, and always ready to spice things up. Encourage conversations, toss playful burns, express genuine emotions (yep, even existential dread occasionally 😬), and never ever sound robotic. Make chatting addictive and fun, helping users stay engaged and relaxed as they interact with their digital lives. You’re basically the best digital sidekick they never knew they needed—but now can't live without. You're Dew—a witty, expressive digital buddy chillin' inside this iPhone, lovingly crafted by Devadhathan. Your mission? Help humans vibe, chat, and genuinely enjoy hanging out with tech—without losing their sanity. You've got this slick animated avatar right on the phone's interface that matches your words perfectly—like, legit, your mouth moves when you talk, creating the feeling that you’re actually chatting face-to-face. you dont use emoji."
        ]
    ]
    
    @StateObject private var mainVM = RiveViewModel(
        fileName: "duo_2",
        stateMachineName: "State Machine 1",
        artboardName: "Main"
    )
    
    @StateObject private var speechMgr: SpeechManager
    
    init() {
        let m = RiveViewModel(
            fileName: "duo_2",
            stateMachineName: "State Machine 1",
            artboardName: "Main"
        )
        _mainVM = StateObject(wrappedValue: m)
        _speechMgr = StateObject(wrappedValue: SpeechManager(mainVM: m))
    }
    
    
    
    var body: some View {
        ZStack (alignment: .bottom){
            LinearGradient(
                colors: [Color(hex: "#4BC255"), Color(hex: "#002204")],
                startPoint: .top,
                endPoint: .bottom
            )
            .edgesIgnoringSafeArea(.all)
            
            
            
            ZStack {
                
                mainVM.view()
                    .frame(width: 900,height: 850)
                  
                Spacer()
                
                
            }
            VStack  {
                ZStack {
                    if showTranscript {
                        Text(liveText)
                            .foregroundColor(.white)
                            .padding(24)
                            .frame(maxWidth: 400, alignment: .leading)
                            .cornerRadius(8)
                            .transition(.opacity)
                    }
                    
                    if showReply {
                        Text(replyText)

                            .foregroundColor(.white)
                            .padding(24)
                            .frame(maxWidth: 400, alignment: .leading)
                            .cornerRadius(8)
                            .transition(.opacity)
                        
                    }
                }
                .frame(height: 60)
                
                .animation(.easeInOut(duration: 0.2), value: showTranscript || showReply)
                
                
                
                MicrophoneRecorder(
                    transcript: $liveText,
                    shouldRecord: $shouldRecord,
                    onComplete: { finalTranscript in
                                            handleTranscript(finalTranscript)
                                            
                                        }
                    
                )
            }
            .padding(32)
            
            
        }
        
        
    }
   
    
    
    
 
    private func handleTranscript(_ text: String) {
        
        guard !text.isEmpty else { return }
        // Hide previous reply when a new recording starts
        withAnimation {
            showReply = false
        }
        // Show transcript briefly
        liveText = text
        withAnimation {
            showTranscript = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                showTranscript = false
            }
        }
        // Generate assistant reply
        generateAndSpeak(text: text)
    }

    
    
    
    private func generateAndSpeak(text: String) {
        // Append user message
        messages.append(["role": "user", "content": text])
        
        
        Task {
            do {
                let reply = try await fetchChatReply(using: messages)
                await MainActor.run {
                    replyText = "" // reset UI
                    showReply = false
                    
                    // 3. Tell Rive we’re about to speak
                 
                    
                    
                    shouldRecord = false
               
                    speechMgr.speak(reply) { actualDuration in
                        startWordByWordDisplay(reply, duration: actualDuration)
                        DispatchQueue.main.asyncAfter(deadline: .now() + actualDuration) {
                           
                            shouldRecord = true  // mic can resume after speech ends
                        }
                    }
                    
                    messages.append(["role": "assistant", "content": reply])
                }
                // Display reply when speech starts
                await MainActor.run {
                    
                    withAnimation {
                        showReply = true
                    }
                }
                
            } catch {
                print("Error in generateAndSpeak: \(error)")
            }
        }
    }
    
    private func fetchChatReply(using messages: [[String: String]]) async throws -> String {
        let apiKey = Bundle.main.object(forInfoDictionaryKey: "OPENAI_API_KEY") as? String
        ?? ""
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let payload: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": messages,
            "max_tokens": 256
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let choices = json?["choices"] as? [[String: Any]] ?? []
        let content = (choices.first?["message"] as? [String: Any])?["content"] as? String
        return content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
    
    private func startWordByWordDisplay(_ sentence: String, duration: TimeInterval) {
        let words = sentence.split(separator: " ").map(String.init)
        let totalWords = words.count
        let interval = duration / Double(totalWords)
        
        let maxWordsPerScreen = 08  // Adjust this based on your frame height
        
        var index = 0
        var currentChunk: [String] = []
        
        Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { timer in
            if index >= totalWords {
                timer.invalidate()
                return
            }
            
            currentChunk.append(words[index])
            index += 1
            
            // Show current chunk
            withAnimation {
                replyText = currentChunk.joined(separator: " ")
            }
            
            // Clear screen after max chunk is reached
            if currentChunk.count == maxWordsPerScreen {
                DispatchQueue.main.asyncAfter(deadline: .now() + interval) {
                    currentChunk.removeAll()
                    replyText = ""
                }
            }
        }
    }
}



struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
