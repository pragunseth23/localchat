# LocalChat

iOS chat application with on-device AI using Liquid AI's LEAP Edge SDK. Runs completely offline after initial model download.

## Features

- On-device AI inference with LFM2.5-1.2B-Instruct
- Streaming text generation
- Automatic model download and caching
- SwiftUI interface

## Requirements

- iOS 15.0+
- Xcode 15.0+ with Swift 5.9+
- Physical device recommended (3GB+ RAM)
- Internet connection for initial download

## Setup

1. Open `localchat.xcodeproj` in Xcode
2. Dependencies resolve automatically via Swift Package Manager
3. Build and run on device or simulator

## Usage

1. Launch app and tap "Load Model" (first time only)
2. Wait for download and initialization
3. Start chatting - model is cached for future use

## Model

- Model: LFM2.5-1.2B-Instruct
- Quantization: Q5_K_M
- Format: GGUF via LEAP SDK

## Architecture

SwiftUI with MVVM pattern. LEAP Edge SDK handles model inference.
