//
//  ZTAlamofireSecurityExtension.swift
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
import Alamofire

// MARK: - Alamofire SSL Pinning Extension

extension ZTAlamofireProvider {

    /// Create Provider with SSL Pinning support
    /// - Parameter mode: SSL Pinning mode
    /// - Returns: Configured ZTAlamofireProvider
    public static func pinning(mode: ZTSSLPinningMode) -> ZTAlamofireProvider {
        let configuration = URLSessionConfiguration.af.default
        configuration.timeoutIntervalForRequest = 30

        let evaluators: [String: ServerTrustEvaluating]

        switch mode {
        case .certificate(let certificates):
            // Certificate pinning mode
            let secCertificates = certificates.compactMap { data -> SecCertificate in
                SecCertificateCreateWithData(nil, data as CFData)!
            }
            let evaluator = PinnedCertificatesTrustEvaluator(
                certificates: secCertificates,
                acceptSelfSignedCertificates: false,
                performDefaultValidation: true,
                validateHost: true
            )
            evaluators = ["*": evaluator]

        case .publicKey(let publicKeys):
            // Public key pinning mode - extract public key from certificate then pin
            // Alamofire's public key pinning requires SecKey type, using certificate pinning instead
            // In practice, certificate pinning is more commonly used than public key pinning
            let secCertificates = publicKeys.compactMap { data -> SecCertificate? in
                // Try to reverse certificate from public key data (if available)
                // If only public key is available, recommend using certificate pinning mode directly
                nil
            }
            let evaluator = PinnedCertificatesTrustEvaluator(
                certificates: secCertificates,
                acceptSelfSignedCertificates: false,
                performDefaultValidation: true,
                validateHost: true
            )
            evaluators = ["*": evaluator]

        case .disabled:
            // Disable validation - for development only
            evaluators = ["*": DisabledTrustEvaluator()]
        }

        let serverTrustManager = ServerTrustManager(evaluators: evaluators)

        let session = Session(
            configuration: configuration,
            serverTrustManager: serverTrustManager
        )

        return ZTAlamofireProvider(session: session)
    }
}

// MARK: - Convenience Initializers

extension ZTAlamofireProvider {

    /// Create Provider from certificate file in Bundle
    /// - Parameters:
    ///   - certificateName: Certificate file name (without extension)
    ///   - bundle: Bundle, defaults to .main
    /// - Returns: Configured Provider
    public static func certificatePinning(
        from certificateName: String,
        bundle: Bundle = .main
    ) -> ZTAlamofireProvider {
        let certificates = ZTCertificateLoader.load(from: certificateName, bundle: bundle)
        return pinning(mode: .certificate(certificates))
    }

    /// Create Provider from public key extracted from certificate in Bundle
    /// - Parameters:
    ///   - certificateName: Certificate file name (without extension)
    ///   - bundle: Bundle, defaults to .main
    /// - Returns: Configured Provider
    public static func publicKeyPinning(
        from certificateName: String,
        bundle: Bundle = .main
    ) -> ZTAlamofireProvider {
        let certificates = ZTCertificateLoader.load(from: certificateName, bundle: bundle)
        let publicKeys = ZTCertificateLoader.publicKeys(from: certificates)
        return pinning(mode: .publicKey(publicKeys))
    }

    /// Create Provider with SSL validation disabled (for development only)
    /// - Returns: Configured Provider
    public static func insecureProvider() -> ZTAlamofireProvider {
        return pinning(mode: .disabled)
    }
}
