//
//  Micorpphone.swift
//  duo 2
//
//  Created by Devdhathan M D on 5/11/25.
//
import SwiftUI
import Speech
import AVFoundation

struct MicrophoneRecorder: View {
    @Binding var transcript: String
    @Binding var shouldRecord: Bool
    var onComplete: (String) -> Void

    @State private var isRecording = false
    @State private var didStop = false
    @State private var isPressed = false


    private let audioEngine = AVAudioEngine()
    @State private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    @State private var recognitionTask: SFSpeechRecognitionTask?
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))!

    var body: some View {
        ZStack {
               // Glowing outer circle
               Circle()
                   .fill(isRecording ? Color.red.opacity(0.7) : Color.blue.opacity(0.7))
                   .frame(width: 65, height: 65)
                   .offset(y: 8)

               // Mic button with toggleMic() on tap
               Button(action: {
                   toggleMic()
               }) {
                   Image(systemName: isRecording ? "mic.fill" : "mic")
                       .font(.largeTitle)
                       .foregroundColor(.white)
                       .padding()
                       .background(isRecording ? Color.red : Color.blue)
                       .clipShape(Circle())
                       .scaleEffect(isPressed ? 0.9 : 1.0)
                       .animation(.easeInOut(duration: 0.2), value: isPressed)
               }
               .simultaneousGesture(
                   DragGesture(minimumDistance: 0)
                       .onChanged { _ in isPressed = true }
                       .onEnded { _ in isPressed = false }
               )
           }
           .onAppear(perform: requestAuthorization)
           .onChange(of: shouldRecord) { newValue in
               if !newValue && isRecording {
                   stopRecording()  // Auto-stop if TTS is talking
               }
           }
       }

    private func requestAuthorization() {
        SFSpeechRecognizer.requestAuthorization { _ in }
    }

    private func toggleMic() {
        if isRecording {
            stopRecording()
        } else if shouldRecord {
            startRecording()
        }
    }

    private func startRecording() {
        guard shouldRecord else { return }

        didStop = false
        transcript = ""
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let req = recognitionRequest else { return }
        req.shouldReportPartialResults = true

        recognitionTask = speechRecognizer.recognitionTask(with: req) { result, error in
            if let result = result {
                transcript = result.bestTranscription.formattedString
            }
        }

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            req.append(buffer)
        }

        try? audioEngine.start()
        isRecording = true
    }

    private func stopRecording() {
        guard !didStop else { return }
        didStop = true

        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil

        isRecording = false

        let final = transcript
        transcript = ""
        onComplete(final)
    }
}

