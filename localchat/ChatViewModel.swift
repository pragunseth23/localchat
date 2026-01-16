//
//  ChatViewModel.swift
//  localchat
//
//  Created by Pragun Seth on 1/16/26.
//

import Foundation
import LeapSDK
import Combine

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var isLoading = false
    @Published var isDownloading = false
    @Published var isInitializing = false
    @Published var conversation: Conversation?
    @Published var messages: [ChatMessage] = []
    @Published var currentResponse: String = ""
    @Published var downloadProgress: Double = 0.0
    @Published var downloadSpeed: String = ""
    @Published var errorMessage: String?
    @Published var isGenerating: Bool = false
    
    private var modelRunner: ModelRunner?
    private var downloadCompleted = false
    private var generationTask: Task<Void, Never>? {
        didSet {
            isGenerating = generationTask != nil
        }
    }
    
    func loadModel() async {
        isLoading = true
        isDownloading = false
        isInitializing = false
        errorMessage = nil
        downloadProgress = 0.0
        downloadSpeed = ""
        downloadCompleted = false
        
        defer {
            isLoading = false
            isDownloading = false
            isInitializing = false
        }
        
        do {
            // LEAP will download the model if needed or reuse a cached copy.
            let modelRunner = try await Leap.load(
                model: "LFM2-1.2B",
                quantization: "Q5_K_M",
                downloadProgressHandler: { [weak self] progress, speed in
                    Task { @MainActor [weak self] in
                        guard let self = self else { return }
                        self.isDownloading = true
                        self.downloadProgress = progress
                        // Convert bytes per second to human-readable format
                        let speedMB = Double(speed) / (1024 * 1024)
                        self.downloadSpeed = String(format: "%.2f MB/s", speedMB)
                        
                        // When download reaches 100%, mark it as complete and switch to initializing
                        if progress >= 1.0 && !self.downloadCompleted {
                            self.downloadCompleted = true
                            self.isDownloading = false
                            self.isInitializing = true
                            self.downloadSpeed = "" // Clear speed when initializing
                        }
                    }
                }
            )
            
            // If we reach here and download was completed, we're in initialization phase
            // (model loading into memory, etc.)
            if downloadCompleted {
                isInitializing = true
            }
            
            // Create conversation (this is part of initialization)
            conversation = modelRunner.createConversation(systemPrompt: "You are a helpful travel assistant.")
            self.modelRunner = modelRunner
            
            // Initialize with system message if needed
            if let conversation = conversation {
                messages = conversation.history
            }
            
            // Clear loading states - model is ready!
            isInitializing = false
            isDownloading = false
            
        } catch {
            errorMessage = "Failed to load model: \(error.localizedDescription)"
            print("Failed to load model: \(error)")
            isDownloading = false
            isInitializing = false
        }
    }
    
    func send(_ text: String) {
        guard let conversation else { return }
        
        generationTask?.cancel()
        currentResponse = ""
        
        let userMessage = ChatMessage(role: .user, content: [.text(text)])
        messages.append(userMessage)
        
        generationTask = Task { [weak self] in
            do {
                for try await response in conversation.generateResponse(
                    message: userMessage,
                    generationOptions: GenerationOptions(temperature: 0.7)
                ) {
                    self?.handle(response)
                }
                // Task completed successfully
                await MainActor.run {
                    self?.generationTask = nil
                }
            } catch {
                await MainActor.run {
                    self?.errorMessage = "Generation failed: \(error.localizedDescription)"
                    self?.generationTask = nil
                }
                print("Generation failed: \(error)")
            }
        }
    }
    
    func stopGeneration() {
        generationTask?.cancel()
        generationTask = nil
        
        // If there's a current response, add it to messages
        if !currentResponse.isEmpty {
            let assistantMessage = ChatMessage(role: .assistant, content: [.text(currentResponse)])
            messages.append(assistantMessage)
            currentResponse = ""
        }
    }
    
    @MainActor
    private func handle(_ response: MessageResponse) {
        switch response {
        case .chunk(let delta):
            currentResponse += delta
        case .reasoningChunk(let thought):
            print("Reasoning:", thought)
            // You can display reasoning chunks in the UI if needed
        case .audioSample(let samples, let sr):
            print("Received audio samples \(samples.count) at sample rate \(sr)")
        case .functionCall(let calls):
            print("Requested calls: \(calls)")
            // Handle function calls if needed
        case .complete(let completion):
            if let stats = completion.stats {
                print("Finished with \(stats.totalTokens) tokens")
            }
            
            // Extract text from completion
            let text = completion.message.content.compactMap { part -> String? in
                if case .text(let value) = part { return value }
                return nil
            }.joined()
            
            // Add the complete message to messages array
            if !text.isEmpty {
                let assistantMessage = ChatMessage(role: .assistant, content: [.text(text)])
                messages.append(assistantMessage)
            }
            
            currentResponse = ""
            
            // Update conversation history
            if let conversation = conversation {
                messages = conversation.history
            }
        @unknown default:
            print("Unknown MessageResponse case")
        }
    }
}
