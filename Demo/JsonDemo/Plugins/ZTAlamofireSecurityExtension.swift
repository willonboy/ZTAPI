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
import CryptoKit

// MARK: - Alamofire SSL Pinning Extension

private final class ZTWildcardServerTrustManager: ServerTrustManager, @unchecked Sendable {
    override func serverTrustEvaluator(forHost host: String) throws -> (any ServerTrustEvaluating)? {
        if let evaluator = evaluators[host] {
            return evaluator
        }
        if let wildcardEvaluator = evaluators["*"] {
            return wildcardEvaluator
        }
        if allHostsMustBeEvaluated {
            throw AFError.serverTrustEvaluationFailed(reason: .noRequiredEvaluator(host: host))
        }
        return nil
    }
}

private final class ZTPublicKeyHashesTrustEvaluator: ServerTrustEvaluating {
    private let pinnedKeyHashes: Set<Data>
    private let performDefaultValidation: Bool
    private let validateHost: Bool

    init(
        pinnedKeyHashes: [Data],
        performDefaultValidation: Bool = true,
        validateHost: Bool = true
    ) {
        self.pinnedKeyHashes = Set(pinnedKeyHashes)
        self.performDefaultValidation = performDefaultValidation
        self.validateHost = validateHost
    }

    func evaluate(_ trust: SecTrust, forHost host: String) throws {
        guard !pinnedKeyHashes.isEmpty else {
            throw AFError.serverTrustEvaluationFailed(reason: .noPublicKeysFound)
        }

        if performDefaultValidation {
            try trust.af.performDefaultValidation(forHost: host)
        }

        if validateHost {
            try trust.af.performValidation(forHost: host)
        }

        let serverKeyHashes: [Data] = trust.af.publicKeys.compactMap { key in
            var error: Unmanaged<CFError>?
            guard let keyData = SecKeyCopyExternalRepresentation(key, &error) as Data? else {
                return nil
            }
            return Data(SHA256.hash(data: keyData))
        }

        guard serverKeyHashes.contains(where: { pinnedKeyHashes.contains($0) }) else {
            let pinningError = NSError(
                domain: "ZTAPI.SSLPinning",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Public key hash pinning failed for host: \(host)"]
            )
            throw AFError.serverTrustEvaluationFailed(
                reason: .customEvaluationFailed(error: pinningError)
            )
        }
    }
}

extension ZTAlamofireProvider {

    public static func pinning(mode: ZTSSLPinningMode) -> ZTAlamofireProvider {

        let evaluator: any ServerTrustEvaluating

        switch mode {
        case .certificate(let certs):
            let secCerts = certs.compactMap {
                SecCertificateCreateWithData(nil, $0 as CFData)
            }
            evaluator = PinnedCertificatesTrustEvaluator(
                certificates: secCerts,
                acceptSelfSignedCertificates: false,
                performDefaultValidation: true,
                validateHost: true
            )

        case .publicKey(let keyHashes):
            evaluator = ZTPublicKeyHashesTrustEvaluator(pinnedKeyHashes: keyHashes)

        case .disabled:
            evaluator = DisabledTrustEvaluator()
        }

        let manager = ZTWildcardServerTrustManager(evaluators: ["*": evaluator])
        let session = Session(serverTrustManager: manager)
        return ZTAlamofireProvider(session: session)
    }
}

// MARK: - Convenience Initializers

extension ZTAlamofireProvider {
    public static func certificatePinning(
        from certificateName: String,
        bundle: Bundle = .main
    ) -> ZTAlamofireProvider {
        let certificates = ZTCertificateLoader.loadCertificates(named: certificateName, bundle: bundle)
        precondition(!certificates.isEmpty, "No certificates found for pinning")

        return pinning(mode: .certificate(certificates))
    }

    #if DEBUG
    public static func insecureProvider() -> ZTAlamofireProvider {
        return pinning(mode: .disabled)
    }
    #endif
}
