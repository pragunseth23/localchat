//
//  ChatView.swift
//  localchat
//
//  Created by Pragun Seth on 1/16/26.
//

import SwiftUI
import LeapSDK

// Preference key to pass container width down the view hierarchy
struct ContainerWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct ChatView: View {
    @StateObject private var viewModel = ChatViewModel()
    @State private var inputText: String = ""
    @FocusState private var isInputFocused: Bool
    @State private var containerWidth: CGFloat = 0
    
    var body: some View {
        VStack(spacing: 0) {
            // Chat messages area
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if viewModel.isLoading {
                            VStack(spacing: 16) {
                                ProgressView()
                                    .scaleEffect(1.5)
                                
                                if viewModel.isDownloading && viewModel.downloadProgress > 0 {
                                    VStack(spacing: 8) {
                                        ProgressView(value: viewModel.downloadProgress)
                                            .progressViewStyle(LinearProgressViewStyle())
                                        
                                        Text("Downloading model: \(Int(viewModel.downloadProgress * 100))%")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        
                                        if !viewModel.downloadSpeed.isEmpty {
                                            Text(viewModel.downloadSpeed)
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    .padding()
                                } else if viewModel.isInitializing {
                                    VStack(spacing: 8) {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle())
                                        
                                        Text("Initializing model...")
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                        
                                        Text("This may take a moment")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .opacity(0.7)
                                    }
                                    .padding()
                                } else {
                                    Text("Loading model...")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                        } else if viewModel.conversation == nil {
                            VStack(spacing: 16) {
                                Image(systemName: "brain.head.profile")
                                    .font(.system(size: 60))
                                    .foregroundColor(.blue)
                                
                                Text("Welcome to LocalChat")
                                    .font(.title2)
                                    .fontWeight(.semibold)
                                
                                Text("Tap the button below to load the AI model")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                                
                                Button(action: {
                                    Task {
                                        await viewModel.loadModel()
                                    }
                                }) {
                                    HStack {
                                        Image(systemName: "arrow.down.circle.fill")
                                        Text("Load Model")
                                    }
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .padding()
                                    .background(Color.blue)
                                    .cornerRadius(10)
                                }
                                
                                if let errorMessage = viewModel.errorMessage {
                                    Text(errorMessage)
                                        .font(.caption)
                                        .foregroundColor(.red)
                                        .padding()
                                        .background(Color.red.opacity(0.1))
                                        .cornerRadius(8)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                        } else {
                            // Display messages
                            ForEach(Array(viewModel.messages.enumerated()), id: \.offset) { index, message in
                                MessageBubble(message: message, maxWidth: containerWidth > 0 ? containerWidth * 0.75 : nil)
                                    .id(index)
                            }
                            
                            // Display current streaming response
                            if !viewModel.currentResponse.isEmpty {
                                MessageBubble(
                                    message: ChatMessage(
                                        role: .assistant,
                                        content: [.text(viewModel.currentResponse)]
                                    ),
                                    isStreaming: true,
                                    maxWidth: containerWidth > 0 ? containerWidth * 0.75 : nil
                                )
                                .id("streaming")
                            }
                        }
                    }
                    .padding()
                    .background(
                        GeometryReader { geometry in
                            Color.clear.preference(
                                key: ContainerWidthKey.self,
                                value: geometry.size.width
                            )
                        }
                    )
                }
                .onPreferenceChange(ContainerWidthKey.self) { width in
                    containerWidth = width
                }
                .onChange(of: viewModel.messages.count) {
                    withAnimation {
                        if let lastIndex = viewModel.messages.indices.last {
                            proxy.scrollTo(lastIndex, anchor: .bottom)
                        }
                    }
                }
                .onChange(of: viewModel.currentResponse) {
                    withAnimation {
                        proxy.scrollTo("streaming", anchor: .bottom)
                    }
                }
            }
            
            Divider()
            
            // Input area
            if viewModel.conversation != nil {
                HStack(spacing: 12) {
                    TextField("Type a message...", text: $inputText, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...5)
                        .focused($isInputFocused)
                        .onSubmit {
                            sendMessage()
                        }
                        .disabled(viewModel.isGenerating)
                    
                    if viewModel.isGenerating {
                        Button(action: {
                            viewModel.stopGeneration()
                        }) {
                            Image(systemName: "stop.circle.fill")
                                .font(.title2)
                                .foregroundColor(.red)
                        }
                    } else {
                        Button(action: {
                            sendMessage()
                        }) {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.title2)
                                .foregroundColor(inputText.isEmpty ? .gray : .blue)
                        }
                        .disabled(inputText.isEmpty)
                    }
                }
                .padding()
            }
        }
        .navigationTitle("LocalChat")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private func sendMessage() {
        guard !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        let text = inputText
        inputText = ""
        isInputFocused = false
        
        viewModel.send(text)
    }
}

struct MessageBubble: View {
    let message: ChatMessage
    var isStreaming: Bool = false
    var maxWidth: CGFloat?
    
    var body: some View {
        HStack {
            if message.role == .user {
                Spacer()
            }
            
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                Text(messageText)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(message.role == .user ? Color.blue : Color.gray.opacity(0.2))
                    .foregroundColor(message.role == .user ? .white : .primary)
                    .cornerRadius(18)
                
                if isStreaming {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.gray)
                            .frame(width: 4, height: 4)
                            .opacity(0.6)
                        Circle()
                            .fill(Color.gray)
                            .frame(width: 4, height: 4)
                            .opacity(0.6)
                        Circle()
                            .fill(Color.gray)
                            .frame(width: 4, height: 4)
                            .opacity(0.6)
                    }
                    .padding(.top, 4)
                }
            }
            .frame(maxWidth: maxWidth, alignment: message.role == .user ? .trailing : .leading)
            
            if message.role == .assistant {
                Spacer()
            }
        }
    }
    
    private var messageText: String {
        message.content.compactMap { part -> String? in
            if case .text(let value) = part {
                return value
            }
            return nil
        }.joined()
    }
}

#Preview {
    NavigationView {
        ChatView()
    }
}
