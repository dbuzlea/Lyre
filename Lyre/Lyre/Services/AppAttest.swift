//
//  AppAttest.swift
//  Lyre
//

import Foundation
import DeviceCheck
import CryptoKit
import OSLog

private let logger = Logger(subsystem: "com.pinkhatcreations.lyreapp", category: "AppAttest")

// MARK: - App Attest
//
// So the relay can tell a report from a genuine copy of Lyre on a real Apple device from
// one sent by anyone who's dug the app's key out (relay/src/attest.ts):
//
//   once per install   a key, made in the Secure Enclave, attested by Apple over a
//                      challenge from the relay, and handed to the relay to keep
//   each report        the report's bytes signed with that key (an assertion), sent
//                      in X-Lyre-Key-ID and X-Lyre-Assertion
//
// Where App Attest isn't there (the simulator), or until the key's enrolled, reports go
// unsigned, which the relay takes until REQUIRE_ATTEST is turned on.

nonisolated final class AppAttestor: @unchecked Sendable {
    static let shared = AppAttestor()

    private let keyIDKey = "AppAttestKeyID"
    private let enrolledKey = "AppAttestEnrolled"
    private let lock = NSLock()
    private var enrolling: Task<Bool, Never>?

    var isSupported: Bool { DCAppAttestService.shared.isSupported }

    private var keyID: String? {
        get { UserDefaults.standard.string(forKey: keyIDKey) }
        set { UserDefaults.standard.set(newValue, forKey: keyIDKey) }
    }

    var isEnrolled: Bool { UserDefaults.standard.bool(forKey: enrolledKey) && keyID != nil }

    /// Makes and enrols the key if that hasn't been done; true once it has. Callers
    /// asking at once share one enrolment.
    @discardableResult
    func enrol(with configuration: ProblemReporter.Configuration, session: URLSession = .shared) async -> Bool {
        guard isSupported else { return false }
        if isEnrolled { return true }
        let task = lock.withLock { () -> Task<Bool, Never> in
            if let enrolling { return enrolling }
            let task = Task { await self.performEnrolment(configuration, session: session) }
            enrolling = task
            return task
        }
        let enrolled = await task.value
        lock.withLock { enrolling = nil }
        return enrolled
    }

    private func performEnrolment(_ configuration: ProblemReporter.Configuration, session: URLSession) async -> Bool {
        do {
            let service = DCAppAttestService.shared
            let key: String
            if let existing = keyID { key = existing } else {
                key = try await service.generateKey()
                keyID = key
            }
            // A challenge from the relay, which Apple's attestation answers.
            var ask = URLRequest(url: configuration.relayURL.appendingPathComponent("v1/attest/challenge"))
            ask.timeoutInterval = 20
            let (challengeData, _) = try await session.data(for: ask)
            guard let challenge = (try JSONSerialization.jsonObject(with: challengeData) as? [String: Any])?["challenge"] as? String,
                  let challengeBytes = Data(base64Encoded: challenge) else { throw URLError(.badServerResponse) }
            let attestation = try await service.attestKey(key, clientDataHash: Data(SHA256.hash(data: challengeBytes)))

            var enrol = URLRequest(url: configuration.relayURL.appendingPathComponent("v1/attest"))
            enrol.httpMethod = "POST"
            enrol.timeoutInterval = 30
            enrol.setValue("application/json", forHTTPHeaderField: "Content-Type")
            enrol.setValue(configuration.appKey, forHTTPHeaderField: "X-Lyre-Key")
            enrol.httpBody = try JSONSerialization.data(withJSONObject: [
                "keyID": key, "attestation": attestation.base64EncodedString(), "challenge": challenge,
            ])
            let (_, response) = try await session.data(for: enrol)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 201 else {
                Diagnostics.shared.record(.app, "App Attest enrolment refused (\(status))", level: .error)
                return false
            }
            UserDefaults.standard.set(true, forKey: enrolledKey)
            Diagnostics.shared.record(.app, "App Attest key enrolled")
            return true
        } catch let error as DCError where error.code == .invalidKey {
            // Apple won't attest this key (it's been used, or the device was restored):
            // a new one next time.
            keyID = nil
            Diagnostics.shared.record(.app, "App Attest key invalid; a new one next time", level: .error)
            return false
        } catch {
            logger.notice("App Attest enrolment failed: \(error.localizedDescription)")
            Diagnostics.shared.record(.app, "App Attest enrolment failed: \((error as NSError).domain) \((error as NSError).code)",
                                      level: .error)
            return false
        }
    }

    /// The key ID and an assertion over `body`, to send with it; nil if not enrolled.
    func sign(_ body: Data) async -> (keyID: String, assertion: String)? {
        guard isSupported, isEnrolled, let key = keyID else { return nil }
        do {
            let assertion = try await DCAppAttestService.shared.generateAssertion(key, clientDataHash: Data(SHA256.hash(data: body)))
            return (key, assertion.base64EncodedString())
        } catch {
            if (error as? DCError)?.code == .invalidKey {
                UserDefaults.standard.set(false, forKey: enrolledKey)
                keyID = nil
            }
            Diagnostics.shared.record(.app, "App Attest assertion failed", level: .error)
            return nil
        }
    }
}
