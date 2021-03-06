// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Created by Sam Deane, 02/03/2018.
// All code (c) 2018 - present day, Elegant Chaos Limited.
// For licensing terms, see http://elegantchaos.com/license/liberal/.
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

import Foundation
import Logger

/**
 Errors generated by failures at various stages of the build process.
 */

public enum Failure : Error {
    case failed(output : String?, error : String?)
    case decodingFailed
    case missingScheme(name : String)
    case unknownOption(name : String)


    /**
    A suitable exit code to return from the executable.

    This doesn't convey a great deal of meaning, but helps to indicate roughly what
    went wrong, to any script that has invoked Builder.
    */

    public var exitCode : Int32 {
        get {
            switch self {
                case .failed: return 1
                case .decodingFailed: return 2
                case .missingScheme: return 3
                case .unknownOption: return 4
            }
        }
    }

    /**
    Output a log message describing the failure, then exit.
    */

    public func logAndExit(_ channel: Channel) {
        switch self {
            case .decodingFailed:
                channel.log("Couldn't decode JSON")
            case .failed(let stdout, let stderr):
                channel.log(stdout ?? "Failure:")
                channel.log(stderr ?? "")
            case .missingScheme(let name):
                channel.log("Couldn't find scheme: \(name)")
            case .unknownOption(let name):
                channel.log("Tried to read unknown option: \(name)")
        }
        Builder.exit(code: self.exitCode)
    }
}
