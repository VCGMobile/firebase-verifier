import Foundation
import JWT

public protocol Verifier {
    func verify(token: String, allowExpired: Bool) throws -> User
}

extension Verifier {
    public func verify(token: String) throws -> User {
        return try verify(token: token, allowExpired: false)
    }
}

public struct JWTVerifier: Verifier {
    public let projectId: String
    public let publicCertificateFetcher: PublicCertificateFetcher
    public init(projectId: String, publicCertificateFetcher: PublicCertificateFetcher = GooglePublicCertificateFetcher()) throws {
        if projectId.isEmpty {
            throw VerificationError(type: .emptyProjectId, message: nil)
        }
        self.projectId = projectId
        self.publicCertificateFetcher = publicCertificateFetcher
    }
    public func verify(token: String, allowExpired: Bool = false) throws -> User {
        let jwt = try JWT(token: token)

        assert(jwt.subject == jwt.userId)
        if !allowExpired {
            try jwt.verifyExpirationTime()
        }
        try jwt.verifyAlgorithm()
        try jwt.verifyAudience(with: projectId)
        try jwt.verifyIssuer(with: projectId)

        guard let keyIdentifier = jwt.keyIdentifier else {
            throw VerificationError(type: .notFound(key: "kid"), message: "Firebase ID token has no 'kid' claim.")
        }

        guard let subject = jwt.subject else {
            let message = "Firebase ID token has no 'sub' (subject) claim. \(verifyIdTokenDocsMessage)"
            throw VerificationError(type: .notFound(key: "sub"), message: message)
        }
        guard subject.count <= 128 else {
            let message = "Firebase ID token has 'sub' (subject) claim longer than 128 characters. \(verifyIdTokenDocsMessage)"
            throw VerificationError(type: .incorrect(key: "sub"), message: message)
        }

        let cert = try publicCertificateFetcher.fetch(with: keyIdentifier).makeBytes().base64Decoded
        let signer = try RS256(x509Cert: cert)
        try jwt.verifySignature(using: signer)

        return User(jwt: jwt)
    }
}
