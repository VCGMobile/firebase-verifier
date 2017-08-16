//
//  Config+FirebaseVerifier.swift
//  Bits
//
//  Created by mono on 2017/08/03.
//

import Foundation
import Vapor

extension JWTVerifier: ConfigInitializable {
    public init(config: Config) throws {
        guard let firebase = config["firebase"] else {
            throw ConfigError.missingFile("firebase")
        }
        guard let projectId = firebase["project_id"]?.string else {
            throw ConfigError.missing(key: ["project_id"], file: "firebase", desiredType: String.self)
        }
        self = try JWTVerifier(projectId: projectId)
    }
}

extension Config {
    public func resolveFirebaseVerifier() throws -> Verifier {
        return try customResolve(
            unique: "firebase",
            file: "firebase",
            keyPath: ["verifier"],
            as: Verifier.self,
            default: JWTVerifier.init
        )
    }
}
