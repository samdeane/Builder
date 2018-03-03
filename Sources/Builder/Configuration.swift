// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Created by Sam Deane, 02/03/2018.
// All code (c) 2018 - present day, Elegant Chaos Limited.
// For licensing terms, see http://elegantchaos.com/license/liberal/.
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

/**
 Data structure representing a phase of the build process.
 
 The name is optional, and for information purposes only.
 The tool is either a special built-in command, or the
 name of a tool dependendency to build and run.
 The arguments are passed to the tool or built-in.
 */

struct Phase : Decodable {
    let name : String
    let tool : String
    let arguments : [String]
}

/**
 Data structure returned by the Configuration target.
 
 This structure describes the products to build, the
 settings to apply to them, and a list of executables
 to build and run before and after the build.
 
 The executables should themselves be specified as dependencies
 of the Configuration target, and will be built as part of building
 the configuration.
 
 In this way the entire toolchain is bootstrappable.
 */

struct Configuration : Decodable {
    let settings : [String:String]
    let phases : [Phase]
    
    func compilerSettings() -> [String] {
        var args : [String] = []
        settings.forEach({ (key, value) in
            args.append(contentsOf: ["-Xswiftc", "-\(key)", "-Xswiftc", "\(value)"])
        })
        return args
    }
    
}