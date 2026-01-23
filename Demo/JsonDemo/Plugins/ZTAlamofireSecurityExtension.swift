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

    public static func pinning(mode: ZTSSLPinningMode) -> ZTAlamofireProvider {

        let evaluators: [String: ServerTrustEvaluating]

        switch mode {
        case .certificate(let certs):
            let secCerts = certs.compactMap {
                SecCertificateCreateWithData(nil, $0 as CFData)
            }
            evaluators = [
                "*": PinnedCertificatesTrustEvaluator(
                    certificates: secCerts,
                    acceptSelfSignedCertificates: false,
                    performDefaultValidation: true,
                    validateHost: true
                )
            ]

        case .publicKey:
            fatalError("Alamofire does not safely support Public Key pinning. Use URLSession provider.")

        case .disabled:
            evaluators = ["*": DisabledTrustEvaluator()]
        }

        let manager = ServerTrustManager(evaluators: evaluators)
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
