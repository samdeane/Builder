// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Created by Sam Deane, 02/03/2018.
// All code (c) 2018 - present day, Elegant Chaos Limited.
// For licensing terms, see http://elegantchaos.com/license/liberal/.
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

import Foundation
import os

/**
 Builder.

 The basic algorithm is:

 - build and run the "Configuration" dependency, capturing the output
 - parse this output from JSON into a configuration structure
 - iterate through the targets in configuration.prebuild, building and executing each one
 - iterate through the products in configuration.products
 - iterate through the targets in configuration.postbuild, building and executing each one

 Building is done with `swift build`, and running with `swift run`.

 */

class Builder {

    /**
     Invoke a command and some optional arguments.
     On success, returns the captured output from stdout.
     On failure, throws an error.
     */

    func run(_ command : String, arguments: [String] = [], environment : [String:String]? = nil) throws -> String {
        let pipe = Pipe()
        let handle = pipe.fileHandleForReading
        let errPipe = Pipe()
        let errHandle = errPipe.fileHandleForReading
        
        let process = Process()
        process.launchPath = command
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = errPipe
        process.environment = environment
        process.launch()
        let data = handle.readDataToEndOfFile()
        let errData = errHandle.readDataToEndOfFile()

        process.waitUntilExit()
        let capturedOutput = String(data:data, encoding:String.Encoding.utf8)
        let status = process.terminationStatus
        if status != 0 {
            output.log("\(command) failed \(status)")
            let errorOutput = String(data:errData, encoding:String.Encoding.utf8)
            throw Failure.failed(output: capturedOutput, error: errorOutput)
        }

        if capturedOutput != nil {
            verbose.log("\(command) \(arguments)> \(capturedOutput!)")
        }

        return capturedOutput ?? ""
    }

    /**
     Invoke `swift` with a command and some optional arguments.
     On success, returns the captured output from stdout.
     On failure, throws an error.
     */

    func swift(_ command : String, arguments: [String] = [], environment : [String:String]? = nil) throws -> String {

        #if os(macOS)
        let swift = "/usr/bin/swift" // should be discovered from the environment
        #else
        let swift = "/home/sam/Downloads/swift/usr/bin/swift"
        #endif

        verbose.log("running swift \(command)")
        return try run(swift, arguments: [command] + arguments, environment: environment)
    }

    /**
     Parse some json into a Configuration structure.
     */

    func parse(configuration json : String) throws -> Configuration {
        guard let data = json.data(using: String.Encoding.utf8) else {
            throw Failure.decodingFailed
        }

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(Configuration.self, from: data)

        return decoded
    }

    /**
     Return the environment to pass to any tools we launch.
     */
    func environment() -> [String:String] {
        // inherit our environment
        var env = ProcessInfo.processInfo.environment

        // TODO: flesh this out
        env["BUILDER_COMMAND"] = "build"
        env["BUILDER_CONFIGURATION"] = "debug" // TODO: read from the command line

        return env
    }
    
    /**
     Perform the build.
     */

    func build(configurationTarget : String) throws {
        var environment = self.environment()
        
        // try to build the Configure target
        output.log("Configuring.")
        environment["BUILDER_STAGE"] = "configure"
        let _ = try swift("build", arguments: ["--product", configurationTarget], environment: environment)

        // if we built it, run it, and parse its output as a JSON configuration
        // (we don't use `swift run` here as we don't want to capture any of its output)
        let binPath = try swift("build", arguments: ["--product", configurationTarget, "--show-bin-path"])
        let configurePath = URL(fileURLWithPath:binPath.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)).appendingPathComponent(configurationTarget).path
        let json = try run(configurePath, environment: environment)
        let configuration = try parse(configuration: json)

        environment["BUILDER_PRODUCTS"] = configuration.products.joined(separator: ",")

        // run any prebuild tools
        output.log("\nPrebuild:")
        environment["BUILDER_STAGE"] = "prebuild"
        for tool in configuration.prebuild {
            let toolOutput = try swift("run", arguments: [tool], environment: environment)
            output.log("- run \(tool): \(toolOutput)")
        }

        // process the configuration to do the actual build
        output.log("\nBuild:")
        environment["BUILDER_STAGE"] = "build"
        let settings = configuration.compilerSettings()
        for product in configuration.products {
            output.log("- building \(product).")
            let _ = try swift("build", arguments: ["--product", product] + settings, environment: environment)
        }

        // run any postbuild tools
        output.log("\nPostbuild:")
        environment["BUILDER_STAGE"] = "postbuild"
        for tool in configuration.postbuild {
            let toolOutput = try swift("run", arguments: [tool], environment: environment)
            output.log("- run \(tool): \(toolOutput)")
        }

        output.log("\nDone.\n\n")
    }

}
