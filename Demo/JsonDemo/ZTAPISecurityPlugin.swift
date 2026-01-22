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

    /// Validate server certificate (synchronous method for URLSessionDelegate callback)
    public func validate(
        serverTrust: SecTrust,
        domain: String?
    ) -> Bool {
        switch mode {
        case .certificate(let certificates):
            return validateCertificate(serverTrust: serverTrust, pinnedCertificates: certificates)
        case .publicKey(let publicKeys):
            return validatePublicKey(serverTrust: serverTrust, pinnedPublicKeys: publicKeys)
        case .disabled:
            return true
        }
    }

    // MARK: - Certificate Validation

    private func validateCertificate(
        serverTrust: SecTrust,
        pinnedCertificates: [Data]
    ) -> Bool {
        guard let serverCertificate = SecTrustGetCertificateAtIndex(serverTrust, 0) else {
            return false
        }

        let serverCertificateData = SecCertificateCopyData(serverCertificate) as Data

        for pinnedCertificate in pinnedCertificates {
            if serverCertificateData == pinnedCertificate {
                return true
            }
        }

        return false
    }

    // MARK: - Public Key Validation

    private func validatePublicKey(
        serverTrust: SecTrust,
        pinnedPublicKeys: [Data]
    ) -> Bool {
        for index in 0..<SecTrustGetCertificateCount(serverTrust) {
            guard let certificate = SecTrustGetCertificateAtIndex(serverTrust, index) else {
                continue
            }

            guard let publicKey = publicKey(for: certificate) else {
                continue
            }

            for pinnedKey in pinnedPublicKeys {
                if publicKey == pinnedKey {
                    return true
                }
            }
        }

        return false
    }

    private func publicKey(for certificate: SecCertificate) -> Data? {
        var publicKey: SecKey?
        let policy = SecPolicyCreateBasicX509()
        var trust: SecTrust?
        let status = SecTrustCreateWithCertificates(certificate, policy, &trust)

        guard status == errSecSuccess,
              let trust = trust,
              SecTrustEvaluateWithError(trust, nil) else {
            return nil
        }

        publicKey = SecTrustCopyPublicKey(trust)

        guard let publicKey = publicKey else {
            return nil
        }

        var error: Unmanaged<CFError>?
        guard let publicKeyData = SecKeyCopyExternalRepresentation(publicKey, &error) as Data? else {
            return nil
        }

        return publicKeyData
    }
}

// MARK: - Certificate Loader

/// Certificate loading utility
public enum ZTCertificateLoader {

    /// Load certificates from Bundle
    /// - Parameters:
    ///   - name: Certificate file name (without extension)
    ///   - bundle: Bundle, defaults to .main
    /// - Returns: Array of certificate data
    public static func load(
        from name: String,
        bundle: Bundle = .main
    ) -> [Data] {
        var certificates: [Data] = []

        // Try loading .cer format
        if let url = bundle.url(forResource: name, withExtension: "cer"),
           let data = try? Data(contentsOf: url) {
            certificates.append(data)
        }

        // Try loading .der format
        if let url = bundle.url(forResource: name, withExtension: "der"),
           let data = try? Data(contentsOf: url) {
            certificates.append(data)
        }

        return certificates
    }

    /// Extract public keys from certificate data
    /// - Parameter certificates: Array of certificate data
    /// - Returns: Array of public key data
    public static func publicKeys(from certificates: [Data]) -> [Data] {
        var publicKeys: [Data] = []

        for certificateData in certificates {
            guard let certificate = SecCertificateCreateWithData(nil, certificateData as CFData) else {
                continue
            }

            var publicKey: SecKey?
            let policy = SecPolicyCreateBasicX509()
            var trust: SecTrust?
            let status = SecTrustCreateWithCertificates(certificate, policy, &trust)

            guard status == errSecSuccess,
                  let trust = trust,
                  SecTrustEvaluateWithError(trust, nil) else {
                continue
            }

            publicKey = SecTrustCopyPublicKey(trust)

            if let publicKey = publicKey {
                var error: Unmanaged<CFError>?
                if let publicKeyData = SecKeyCopyExternalRepresentation(publicKey, &error) as Data? {
                    publicKeys.append(publicKeyData)
                }
            }
        }

        return publicKeys
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
            guard let serverTrust = challenge.protectionSpace.serverTrust else {
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
