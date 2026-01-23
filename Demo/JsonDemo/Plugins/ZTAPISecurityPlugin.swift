//
//  ZTAPISecurityPlugin.swift
//  ZTAPI
//
//  Copyright (c) 2026 trojanzhang. All rights reserved.
//
//  This file is part of ZTAPI.
//
//  ZTAPI is free software: you can redistribute it and/or modify
//  it under the terms of the GNU Affero General Public License as published
//  by the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  ZTAPI is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
//  GNU Affero General Public License for more details.
//
//  You should have received a copy of the GNU Affero General Public License
//  along with ZTAPI. If not, see <https://www.gnu.org/licenses/>.
//

import Foundation
import CryptoKit
import ZTAPICore

// MARK: - SSL Pinning Plugin

/// SSL Pinning validation mode
public enum ZTSSLPinningMode: Sendable {
    /// Certificate pinning - validate server using local certificates
    case certificate([Data])
    /// Public key pinning - validate server using local public keys
    case publicKey([Data])
    /// Disable certificate validation - for development only
    case disabled
}

/// SSL Pinning validator
public struct ZTSSLPinningValidator: Sendable {

    private let mode: ZTSSLPinningMode

    public init(mode: ZTSSLPinningMode) {
        self.mode = mode
    }

    public func validate(
        serverTrust: SecTrust,
        domain: String
    ) -> Bool {
        if case .disabled = mode {
            return true
        }
        // 必须先做系统信任链校验
        let policy = SecPolicyCreateSSL(true, domain as CFString)
        SecTrustSetPolicies(serverTrust, policy)

        guard SecTrustEvaluateWithError(serverTrust, nil) else {
            return false
        }

        // 再做 Pinning
        switch mode {
        case .certificate(let certs):
            guard !certs.isEmpty else { return false }
            return validateCertificate(
                serverTrust: serverTrust,
                pinnedCertificates: certs
            )

        case .publicKey(let keys):
            guard !keys.isEmpty else { return false }
            return validatePublicKey(
                serverTrust: serverTrust,
                pinnedKeyHashes: keys
            )

        case .disabled:
            return true
        }
    }

    // MARK: - Certificate Pinning (Chain-aware)

    private func validateCertificate(
        serverTrust: SecTrust,
        pinnedCertificates: [Data]
    ) -> Bool {

        let serverCertCount = SecTrustGetCertificateCount(serverTrust)

        for index in 0..<serverCertCount {
            guard let cert = SecTrustGetCertificateAtIndex(serverTrust, index) else {
                continue
            }
            let certData = SecCertificateCopyData(cert) as Data
            if pinnedCertificates.contains(certData) {
                return true
            }
        }
        return false
    }

    // MARK: - Public Key Pinning (SHA256)

    private func validatePublicKey(
        serverTrust: SecTrust,
        pinnedKeyHashes: [Data]
    ) -> Bool {

        let certCount = SecTrustGetCertificateCount(serverTrust)

        for index in 0..<certCount {
            guard
                let cert = SecTrustGetCertificateAtIndex(serverTrust, index),
                let key = SecCertificateCopyKey(cert),
                let hash = sha256(of: key)
            else { continue }

            if pinnedKeyHashes.contains(hash) {
                return true
            }
        }
        return false
    }

    private func sha256(of key: SecKey) -> Data? {
        var error: Unmanaged<CFError>?
        guard let keyData = SecKeyCopyExternalRepresentation(key, &error) as Data? else {
            return nil
        }
        let digest = SHA256.hash(data: keyData)
        return Data(digest)
    }
}

// MARK: - Certificate Loader

public enum ZTCertificateLoader {

    public static func loadCertificates(
        named name: String,
        bundle: Bundle = .main
    ) -> [Data] {

        var results: [Data] = []

        for ext in ["cer", "der"] {
            if let url = bundle.url(forResource: name, withExtension: ext),
               let data = try? Data(contentsOf: url) {
                results.append(data)
            }
        }
        return results
    }

    /// 提取 Public Key 的 SHA256 Hash（用于 pinning）
    public static func publicKeyHashes(
        from certificates: [Data]
    ) -> [Data] {

        var hashes: [Data] = []

        for certData in certificates {
            guard
                let cert = SecCertificateCreateWithData(nil, certData as CFData),
                let key = SecCertificateCopyKey(cert),
                let keyData = SecKeyCopyExternalRepresentation(key, nil) as Data?
            else { continue }

            let digest = SHA256.hash(data: keyData)
            hashes.append(Data(digest))
        }
        return hashes
    }
}

// MARK: - SSL Pinning URLSession Provider

/// URLSession Provider with certificate pinning support
public final class ZTSSLPinningProvider: @unchecked Sendable, ZTAPIProvider {

    private let session: URLSession
    private let delegate: SSLPinningDelegate

    /// Initialize
    /// - Parameters:
    ///   - mode: SSL Pinning mode
    ///   - configuration: URLSession configuration, defaults to .default
    public init(
        mode: ZTSSLPinningMode,
        configuration: URLSessionConfiguration = .default
    ) {
        let validator = ZTSSLPinningValidator(mode: mode)
        self.delegate = SSLPinningDelegate(validator: validator)

        let operationQueue = OperationQueue()
        operationQueue.maxConcurrentOperationCount = 1
        operationQueue.qualityOfService = .userInitiated

        self.session = URLSession(
            configuration: configuration,
            delegate: delegate,
            delegateQueue: operationQueue
        )
    }

    public func request(
        _ urlRequest: URLRequest,
        uploadProgress: ZTUploadProgressHandler? = nil
    ) async throws -> (Data, HTTPURLResponse) {

        // Upload progress callback not supported yet
        // Refer to ZTURLSessionProvider implementation for support

        let (data, response) = try await session.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ZTAPIError.invalidResponse
        }

        if httpResponse.statusCode >= 400 {
            throw ZTAPIError(
                httpResponse.statusCode,
                "HTTP Error \(httpResponse.statusCode)",
                httpResponse: httpResponse
            )
        }

        return (data, httpResponse)
    }

    // MARK: - Delegate

    private final class SSLPinningDelegate: NSObject, URLSessionDelegate {

        private let validator: ZTSSLPinningValidator

        init(validator: ZTSSLPinningValidator) {
            self.validator = validator
        }

        // MARK: - URLSessionDelegate

        func urlSession(
            _ session: URLSession,
            didReceive challenge: URLAuthenticationChallenge,
            completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
        ) {
            guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
                  let serverTrust = challenge.protectionSpace.serverTrust else {
                completionHandler(.performDefaultHandling, nil)
                return
            }

            // Synchronous certificate validation
            let isValid = validator.validate(
                serverTrust: serverTrust,
                domain: challenge.protectionSpace.host
            )

            if isValid {
                completionHandler(.useCredential, URLCredential(trust: serverTrust))
            } else {
                completionHandler(.cancelAuthenticationChallenge, nil)
            }
        }
    }
}
