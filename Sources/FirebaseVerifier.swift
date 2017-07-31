import Foundation
import JWT

private let verifyIdTokenDocsMessage = "See https://firebase.google.com/docs/auth/admin/verify-id-tokens for details on how to retrieve an ID token."
private let projectIdMatchMessage = "Make sure the ID token comes from the same Firebase project as the service account used to authenticate this SDK."

public enum VerificationErrorType {
    case
    notFound(key: String),
    incorrect(key: String),
    emptyProjectId,
    expirationTimeIsPast,
    issuedAtTimeisFuture
}

public struct VerificationError: Error {
    public let type: VerificationErrorType
    public let message: String?
}

extension VerificationError: CustomStringConvertible {
    public var description: String {
        return "type: \(type)\nmessage: \(String(describing: message))"
    }
}

public struct VerifiedResult {
    public let userId: String
    public let authTime: Date
    // TODO: provider_id, firebase
}

public struct FirebaseVerifier {
    public let projectId: String
    public init(projectId: String) throws {
        if projectId.isEmpty {
            throw VerificationError(type: .emptyProjectId, message: nil)
        }
        self.projectId = projectId
    }
    public func verify(token: String, allowExpired: Bool = false) throws -> VerifiedResult {
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
        guard subject.characters.count <= 128 else {
            let message = "Firebase ID token has 'sub' (subject) claim longer than 128 characters. \(verifyIdTokenDocsMessage)"
            throw VerificationError(type: .incorrect(key: "sub"), message: message)
        }

        let cert = try fetchPublicCertificate(with: keyIdentifier)
        let signer = try RS256(x509Cert: cert)
        try jwt.verifySignature(using: signer)

        guard let authTime = jwt.expirationTime else { throw VerificationError(type: .notFound(key: "auth_time"), message: nil) }
        return VerifiedResult(userId: subject, authTime: authTime)
    }

    private func fetchPublicCertificate(with keyIdentifier: String) throws -> Bytes {
        // TODO: Cache-Control
        let response = try String(contentsOf: URL(string: "https://www.googleapis.com/robot/v1/metadata/x509/securetoken@system.gserviceaccount.com")!)

        guard let keys = response.toJSON() as? NSDictionary, let publicKey = keys[keyIdentifier] as? String else {
            let message = "Firebase ID token has 'kid' claim which does not correspond to a known public key. Most likely the ID token is expired, so get a fresh token from your client app and try again. \(verifyIdTokenDocsMessage)"
            throw VerificationError(type: .notFound(key: "public key"), message: message)
        }

        let publicKeyLines = publicKey.characters.split(separator: "\n")
        assert(publicKeyLines.count >= 3)
        return String(publicKeyLines[1..<publicKeyLines.count - 1].joined())
            .makeBytes()
            .base64URLDecoded
    }
}

extension JWT {
    private func payloadStringValue(with key: String) -> String? {
        return payload[key]?.string
    }
    private func time(with key: String) -> Date? {
        guard let interval = payload[key]?.double else { return nil }
        return Date(timeIntervalSince1970: interval)
    }
    var issuedAtTime: Date? { return time(with: "iat") }
    var expirationTime: Date? { return time(with: "exp") }
    var authTime: Date? { return time(with: "auth_time") }
    var audience: String? { return payloadStringValue(with: "aud") }
    var issuer: String? { return payloadStringValue(with: "iss") }
    var subject: String? { return payloadStringValue(with: "sub") }
    var userId: String? { return payloadStringValue(with: "user_id") }

    func verifyAlgorithm() throws {
        let alghorithm = "RS256"
        if algorithmName == alghorithm { return }
        let message = "Firebase ID token has incorrect algorithm. Expected '\(alghorithm)' but got '\(String(describing: algorithmName))'. \(verifyIdTokenDocsMessage)"
        throw VerificationError(type: .incorrect(key: "alg"), message: message)
    }
    func verifyAudience(with projectId: String) throws {
        if audience == projectId { return }
        let message = "Firebase ID token has incorrect 'aud' (audience) claim. Expected '\(projectId)' but got '\(String(describing: audience))'. \(projectIdMatchMessage) \(verifyIdTokenDocsMessage)"
        throw VerificationError(type: .incorrect(key: "aud"), message: message)
    }
    func verifyIssuer(with projectId: String) throws {
        if issuer == "https://securetoken.google.com/\(projectId)" { return }
        let message = "Firebase ID token has incorrect 'iss' (issuer) claim. Expected https://securetoken.google.com/\(projectId) but got '\(String(describing: issuer))'. \(projectIdMatchMessage) + \(verifyIdTokenDocsMessage)"
        throw VerificationError(type: .incorrect(key: "iss"), message: message)
    }
    func verifyExpirationTime() throws {
        guard let issuedAtTime = issuedAtTime else { throw VerificationError(type: .notFound(key: "iat"), message: nil) }
        guard let expirationTime = expirationTime else { throw VerificationError(type: .notFound(key: "exp"), message: nil) }
        let now = Date()
        if now < issuedAtTime {
            throw VerificationError(type: .issuedAtTimeisFuture,
                                    message: "'exp'(\(expirationTime)) must be in the future. (now: \(now)")
        }
        if now >= expirationTime {
            throw VerificationError(type: .expirationTimeIsPast,
                                    message: "'exp'(\(expirationTime)) must be in the future. (now: \(now)")
        }
    }
}

extension String {
    func toJSON() -> Any? {
        guard let data = data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }
}
