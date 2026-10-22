import Foundation

// The harness's entry point. Top-level code runs on the main actor, as the app's views do.
let arguments = CommandLine.arguments
if arguments.contains("--quiet") { Report.verbose = false }

if arguments.contains("--list-probes") {
    for name in probes.keys.sorted() { print(name) }
    exit(0)
}
if let i = arguments.firstIndex(of: "--probe"), i + 1 < arguments.count {
    guard let probe = probes[arguments[i + 1]] else {
        print("no probe \(arguments[i + 1])")
        exit(2)
    }
    exit(probe() ? 0 : 1)
}

runBalootScenarios()
runHandScenarios()
runBuild4Scenarios()
runBuild5Scenarios()
runBuild6Scenarios()
runBuild7Scenarios()
exit(Report.summary())
