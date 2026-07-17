//
//  PermissionManager.swift
//  LearnWords
//
//  Created by Paul Buktab on 3/31/26.
//  Copyright © 2026 Paul. All rights reserved.
//

// TODO: use it
import Foundation
import Speech
import AVFoundation

/// Centralized permission manager for speech-related features.
/// Compatible with iOS 12+.
final class PermissionManager {

    static let shared = PermissionManager()
    private init() {}

    // MARK: - Status (cheap, synchronous reads)

    var isSpeechRecognitionAuthorized: Bool {
        SFSpeechRecognizer.authorizationStatus() == .authorized
    }

    var isMicrophoneAuthorized: Bool {
        if #available(iOS 17.0, *) {
            AVAudioApplication.shared.recordPermission == .granted
        } else {
            AVAudioSession.sharedInstance().recordPermission == .granted
        }
    }

    // MARK: - Individual Requests

    func requestSpeechRecognitionPermission(completion: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                completion(status == .authorized)
            }
        }
    }

    func requestMicrophonePermission(completion: @escaping (Bool) -> Void) {
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            DispatchQueue.main.async {
                completion(granted)
            }
        }
    }

    // MARK: - Smart Conditional Requests

    /// Requests speech recognition only if undetermined; resolves immediately otherwise.
    private func requestSpeechIfNeeded(completion: @escaping (Bool) -> Void) {
        if isSpeechRecognitionAuthorized {
            completion(true)
        } else {
            requestSpeechRecognitionPermission(completion: completion)
        }
    }

    /// Requests microphone only if not authorized resolves immediately otherwise.
    private func requestMicrophoneIfNeeded(completion: @escaping (Bool) -> Void) {
        if isMicrophoneAuthorized {
            completion(true)
        } else {
            requestMicrophonePermission(completion: completion)
        }
    }

    // MARK: - Combined Entry Point

    typealias AlertHandler = (_ title: String, _ message: String) -> Void

    /// Ensures all required speech permissions are granted.
    /// Requests only what's undetermined; shows alert guidance for denied cases.
    /// Calls `completion` on the main queue.
    func ensurePermissions(
        onDenied: AlertHandler? = nil,
        completion: @escaping (_ granted: Bool) -> Void
    ) {
        // Fast path: everything already authorized
        if isSpeechRecognitionAuthorized && isMicrophoneAuthorized {
            completion(true)
            return
        }

        requestSpeechIfNeeded { [weak self] speechGranted in
            guard let self else { return }

            guard speechGranted else {
                onDenied?(
                    NSLocalizedString("Speech Recognition Required", comment: "PermissionManager - `onDenied`"),
                    NSLocalizedString("Please enable Speech Recognition in Settings to use voice features.", comment: "PermissionManager - `onDenied`")
                )
                completion(false)
                return
            }

            self.requestMicrophoneIfNeeded { micGranted in
                guard micGranted else {
                    onDenied?(
                        NSLocalizedString("Microphone Access Required", comment: "PermissionManager - `onDenied`"),
                        NSLocalizedString("Please enable Microphone access in Settings to use voice features.", comment: "PermissionManager - `onDenied`")
                    )
                    completion(false)
                    return
                }
                completion(true)
            }
        }
    }
}


/*
/// Centralized permission manager for speech-related features
@available(iOS 13.0, *)
@MainActor
class PermissionManager: ObservableObject {
    static let shared = PermissionManager()
    
    @Published private(set) var speechRecognitionStatus: SFSpeechRecognizerAuthorizationStatus = .notDetermined
    @Published private(set) var microphoneStatus: AVAudioSession.RecordPermission = .undetermined
    
    private init() {
        updateStatus()
    }
    
    // MARK: - Status Checks
    
    func updateStatus() {
        speechRecognitionStatus = SFSpeechRecognizer.authorizationStatus()
        microphoneStatus = AVAudioSession.sharedInstance().recordPermission
    }
    
    var isSpeechRecognitionAuthorized: Bool {
        speechRecognitionStatus == .authorized
    }
    
    var isMicrophoneAuthorized: Bool {
        microphoneStatus == .granted
    }
    
    // MARK: - Permission Requests
    
    /// Request speech recognition authorization
    func requestSpeechRecognitionPermission() async -> Bool {
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                Task { @MainActor in
                    self.speechRecognitionStatus = status
                    continuation.resume(returning: status == .authorized)
                }
            }
        }
    }
    
    /// Request microphone permission
    func requestMicrophonePermission() async -> Bool {
        return await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                Task { @MainActor in
                    self.microphoneStatus = granted ? .granted : .denied
                    continuation.resume(returning: granted)
                }
            }
        }
    }
    
    /// Request all necessary permissions for speech features
    func requestAllSpeechPermissions() async -> (speechRecognition: Bool, microphone: Bool) {
        async let speechResult = requestSpeechRecognitionPermission()
        async let micResult = requestMicrophonePermission()
        
        return await (speechRecognition: speechResult, microphone: micResult)
    }
    
    // MARK: - User Guidance
    
    /// Check if permissions are granted, and optionally present guidance
    func ensurePermissions(
        showAlert: ((String, String) -> Void)? = nil
    ) async -> Bool {
        updateStatus()
        
        // If already authorized, return immediately
        if isSpeechRecognitionAuthorized && isMicrophoneAuthorized {
            return true
        }
        
        // Request permissions
        let results = await requestAllSpeechPermissions()
        
        // Handle failures
        if !results.speechRecognition {
            showAlert?(
                "Speech Recognition Required",
                "Please enable Speech Recognition in Settings to use voice features."
            )
            return false
        }
        
        if !results.microphone {
            showAlert?(
                "Microphone Access Required",
                "Please enable Microphone access in Settings to use voice features."
            )
            return false
        }
        
        return true
    }
}
*/
