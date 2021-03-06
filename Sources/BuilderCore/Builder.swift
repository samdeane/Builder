// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Created by Sam Deane, 02/03/2018.
// All code (c) 2018 - present day, Elegant Chaos Limited.
// For licensing terms, see http://elegantchaos.com/license/liberal/.
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

import Foundation
import Logger

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

public class Builder {
    let command: String
    let configuration: String
    let platform: String
    let output: Logger
    let verbose: Logger
    let arguments: [String]
    let settings = SettingsManager()
    var environment: [String:String] = ProcessInfo.processInfo.environment
    var indent = ""
    var level = 0
    lazy var swiftPath = findSwift()
    lazy var xcrunPath = findXCRun()
    lazy var gitPath = findGit()
    lazy var buildPath = findBuildPath()
    
    public init(command: String = "build", configuration: String = "debug", platform: String = Platform.currentPlatform(), output: Logger, verbose: Logger, arguments: [String]) {
        self.command = command
        self.configuration = configuration
        self.platform = platform
        self.output = output
        self.verbose = verbose
        self.arguments = arguments

        self.loadSettingsMappings()
        self.populateEnvironment()
    }

    /**
        Load settings mappings for tools.
    */

    func loadSettingsMappings() {
        settings.addMapper(SwiftSettingsMapper())
        settings.addMapper(XCConfigSettingsMapper())
    }

    /**
        Fill in some envionment values.
    */

    func populateEnvironment() {
        self.environment["BUILDER_COMMAND"] = command
        self.environment["BUILDER_CONFIGURATION"] = configuration

        #if !os(Linux)
        self.environment["BUILDER_SDK_PLATFORM_PATH"] = try? xcrun("--show-sdk-platform-path")
        self.environment["BUILDER_SDK_PLATFORM_VERSION"] = try? xcrun("--show-sdk-platform-version")
        self.environment["BUILDER_SDK_VERSION"] = try? xcrun("--show-sdk-version")
        self.environment["BUILDER_SDK_PATH"] = try? xcrun("--show-sdk-path")
        #endif

        if let version = try? swift("--version") {
            if let pattern = try? NSRegularExpression(pattern: "Apple Swift version ([\\d.]+).*swiftlang-([\\d.]+).*clang-([\\d.]+).*Target: (.*)", options: .dotMatchesLineSeparators) {
                let matches = pattern.matches(in: version, options: [], range: NSRange(location: 0, length: version.count))
                for match in matches {
                    let swiftVersion = version[Range(match.range(at: 1), in:version)!]
                    let langVersion = version[Range(match.range(at: 2), in:version)!]
                    let clangVersion = version[Range(match.range(at: 3), in:version)!]
                    let targetVersion = version[Range(match.range(at: 4), in:version)!]
                    self.environment["BUILDER_SWIFT_VERSION"] = String(swiftVersion)
                    self.environment["BUILDER_SWIFT_LANGUAGE_VERSION"] = String(langVersion)
                    self.environment["BUILDER_CLANG_VERSION"] = String(clangVersion)
                    self.environment["BUILDER_TARGET_VERSION"] = String(targetVersion)
                }
            }
        }

        if let commit = try? git("rev-parse", arguments: ["HEAD"]) {
            self.environment["BUILDER_GIT_COMMIT"] = commit

            if let tags = try? git("describe", arguments: ["--all"]) {
                self.environment["BUILDER_GIT_TAGS"] = tags
                // let versions: [SemanticVersion] = tags.matches(for: "tags/(\\d+)\\.(\\d+)\\.(\\d+)").map { (match: [String]) in
                //     SemanticVersion(major: match[1], minor: match[2], patch: match[3])!
                // }
                // if let version = versions.sorted(by: <).first {
                //     self.environment["BUILDER_VERSION"] = version.text
                // } else {
                // }
            }

            if let version = try? git("describe", arguments: ["--tags"]) {
                self.environment["BUILDER_VERSION"] = version
            }

            if let commits = try? git("log", arguments: ["--oneline"]) {
                let lines = commits.split(separator: "\n")
                self.environment["BUILDER_BUILD"] = String(lines.count)
            }
        }


    }

    func findBuildPath() -> String {
        return ".build/\(configuration)"
    }
    
    func linkablePlistPath(for product: String) -> String {
        return "\(buildPath)/\(product)_info.plist"
    }
    
    /**
     Return the path to the swift binary.
     */

    func findSwift() -> String {
        let path : String
        do {
            path = try run("/usr/bin/which", arguments:["swift"]).trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        } catch {
            path = "/usr/bin/swift"
        }

        return path
    }

    /**
     Return the path to the xcrun binary.
     */

    func findXCRun() -> String {
        let path : String
        do {
            path = try run("/usr/bin/which", arguments:["xcrun"]).trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        } catch {
            path = "/usr/bin/xcrun"
        }

        return path
    }


        /**
         Return the path to the git binary.
         */

        func findGit() -> String {
            let path : String
            do {
                path = try run("/usr/bin/which", arguments:["git"]).trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            } catch {
                path = "/usr/bin/git"
            }

            return path
        }

    /**
     Invoke a command and some optional arguments.
     Control is transferred to the launched process, and this function doesn't return.
     */

    func exec(_ command : String, arguments: [String] = []) {
        let process = Process()
        process.launchPath = command
        process.arguments = arguments
        process.environment = self.environment
        process.launch()
        process.waitUntilExit()
        Builder.exit(code: process.terminationStatus)
    }


    /**
     Invoke a command and some optional arguments.
     On success, returns the captured output from stdout.
     On failure, throws an error.
     */

    func run(_ command : String, arguments: [String] = []) throws -> String {
        let pipe = Pipe()
        let handle = pipe.fileHandleForReading
        let errPipe = Pipe()
        let errHandle = errPipe.fileHandleForReading

        let process = Process()
        process.launchPath = command
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = errPipe
        process.environment = self.environment
        process.launch()
        let data = handle.readDataToEndOfFile()
        let errData = errHandle.readDataToEndOfFile()

        process.waitUntilExit()
        let capturedOutput = String(data:data, encoding:String.Encoding.utf8)
        let status = process.terminationStatus
        if status != 0 {
            verbose.log("\(command) failed \(status)")
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

    func swift(_ command : String, arguments: [String] = []) throws -> String {
        verbose.log("running swift \(command)")
        return try run(swiftPath, arguments: [command] + arguments)
    }

    /**
    Invoke `xcrun` with a command and some optional arguments.
     On success, returns the captured output from stdout.
     On failure, throws an error.
     */

    func xcrun(_ command : String, arguments: [String] = []) throws -> String {
        verbose.log("running xcrun \(command)")
        return try run(xcrunPath, arguments: [command] + arguments).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /**
    Invoke `git` with a command and some optional arguments.
     On success, returns the captured output from stdout.
     On failure, throws an error.
     */

    func git(_ command : String, arguments: [String] = []) throws -> String {
        verbose.log("running git \(command)")
        return try run(gitPath, arguments: [command] + arguments).trimmingCharacters(in: .whitespacesAndNewlines)
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
     Announce the build stage.
    */

    internal func setStage(_ stage : String, announce : Bool = true) {
        if announce {
            output.log("\(indent)\(stage).")
        }
        environment["BUILDER_STAGE"] = stage.lowercased()
    }

    /**
     Execute the phases associated with a given action.
     */

    func execute(action name: String, configuration : Configuration, settings : [String]) throws {
        guard let action = configuration.actions[name] else {
            throw Failure.missingScheme(name: name)
        }

        level += 1
        indent = level > 1 ? "- ".padding(toLength: (level - 1) * 2, withPad: " ", startingAt: 0) : ""

        verbose.log("\(indent)Action: \(name).")

        for phase in action {
            setStage(phase.name)
            let command = phase.command
            let builderAction: BuilderAction
            switch (command) {
                case "test": builderAction = TestAction(engine: self)
                case "run": builderAction = RunAction(engine: self)
                case "metadata": builderAction = MetadataAction(engine: self)
                case "metafile": builderAction = MetafileAction(engine: self)
                case "build": builderAction = BuildAction(engine: self)
                case "action": builderAction = ActionAction(engine: self)
                default: builderAction = DefaultAction(engine: self)
            }
            try builderAction.run(phase: phase, configuration: configuration, settings: settings)
        }

        level -= 1
        indent = ""
    }

    /**
     Perform the build.
     */

    public func execute(configurationTarget : String) throws {
        // try to build the Configure target
        setStage("Configuring", announce: false)
        do {
            let _ = try swift("build", arguments: ["--product", configurationTarget])
        } catch Failure.failed(let stdout, let stderr) {
            if stderr == "error: no product named \'\(configurationTarget)\'\n" {
                var arguments = Array(CommandLine.arguments[1...])
                if arguments.count == 0 {
                    arguments.append("build")
                }
                exec(swiftPath, arguments: arguments)
            } else {
                throw Failure.failed(output: stdout, error: stderr)
            }
        }

        // if we built it, run it, and parse its output as a JSON configuration
        // (we don't use `swift run` here as we don't want to capture any of its output)
        setStage("Configuring")
        let binPath = try swift("build", arguments: ["--product", configurationTarget, "--show-bin-path"])
        verbose.log("- running config")
        let configurePath = URL(fileURLWithPath:binPath.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)).appendingPathComponent(configurationTarget).path
        let json = try run(configurePath)
        verbose.log("- parsing output")
        let configuration = try parse(configuration: json)
        let configSettings = try configuration.resolve(for: command, configuration: self.configuration, platform: platform)
        let mapped = settings.mappedSettings(tool: "swift", settings: configSettings)
        environment["BUILDER_SWIFT_SETTINGS"] = mapped.joined(separator: ",")
        if let values = configSettings.values {
            for item in values {
                environment["BUILDER_SETTING:\(item.key.uppercased())"] = item.value.stringValue()
            }
        }

        // execute the action associated with the primary command we were passed (run/build/test/etc)
        try execute(action: command, configuration: configuration, settings: mapped)

        output.log("Done.\n\n")
    }

    public class func exit(code: Int) {
        exit(code: Int32(code))
    }

    public class func exit(code: Int32) {
        Logger.defaultManager.flush()
        Foundation.exit(Int32(code))
    }
}
