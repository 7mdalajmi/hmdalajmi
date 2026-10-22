import Foundation

/// PASS/FAIL per step, grouped by scenario, with a summary at the end.
enum Report {
    struct Failure {
        let scenario: String
        let step: String
        let detail: String
    }

    private(set) static var scenario = ""
    private(set) static var passed = 0
    private(set) static var failures: [Failure] = []
    private(set) static var scenarioResults: [(name: String, passed: Int, failed: Int)] = []
    private static var scenarioPassed = 0
    private static var scenarioFailed = 0
    static var verbose = true

    private static var headerShown = false

    static func begin(_ name: String) {
        finishScenario()
        scenario = name
        scenarioPassed = 0
        scenarioFailed = 0
        headerShown = false
        if verbose { showHeader() }
    }

    private static func showHeader() {
        guard !headerShown else { return }
        headerShown = true
        print("\n=== \(scenario)")
    }

    static func finishScenario() {
        guard !scenario.isEmpty else { return }
        scenarioResults.append((scenario, scenarioPassed, scenarioFailed))
        scenario = ""
    }

    static func pass(_ step: String) {
        passed += 1
        scenarioPassed += 1
        if verbose { print("  PASS  \(step)") }
    }

    static func fail(_ step: String, _ detail: String) {
        failures.append(Failure(scenario: scenario, step: step, detail: detail))
        scenarioFailed += 1
        showHeader()
        print("  FAIL  \(step)\n          \(detail)")
    }

    private(set) static var notes: [String] = []

    /// A behaviour that differs from the boards by a later decision: printed, and listed again in the summary.
    static func note(_ text: String) {
        notes.append("[\(scenario)] \(text)")
        if verbose { print("  NOTE  \(text)") }
    }

    static func summary() -> Int32 {
        finishScenario()
        print("\n=== Summary")
        for r in scenarioResults {
            print("  \(r.failed == 0 ? "PASS" : "FAIL")  \(r.name)  (\(r.passed) passed, \(r.failed) failed)")
        }
        print("\n  \(passed) checks passed, \(failures.count) failed, in \(scenarioResults.count) scenarios")
        if !notes.isEmpty {
            print("\n=== Notes (decisions that differ from the boards)")
            for n in notes { print("  \(n)") }
        }
        if !failures.isEmpty {
            print("\n=== Failures")
            for f in failures { print("  [\(f.scenario)] \(f.step)\n      \(f.detail)") }
        }
        return failures.isEmpty ? 0 : 1
    }
}

/// `expect(actual, expected, "what")`: PASS when equal, FAIL with both values otherwise.
@discardableResult
func expect<T: Equatable>(_ actual: T, _ expected: T, _ step: String) -> Bool {
    if actual == expected {
        Report.pass(step)
        return true
    }
    Report.fail(step, "expected \(show(expected)), got \(show(actual))")
    return false
}

@discardableResult
func expectTrue(_ condition: Bool, _ step: String, _ detail: @autoclosure () -> String = "") -> Bool {
    if condition {
        Report.pass(step)
        return true
    }
    let d = detail()
    Report.fail(step, d.isEmpty ? "was false" : d)
    return false
}

func show<T>(_ value: T) -> String {
    let mirror = Mirror(reflecting: value)
    if mirror.displayStyle == .optional {
        guard let wrapped = mirror.children.first?.value else { return "nil" }
        return show(wrapped)
    }
    if let s = value as? String { return "«\(s)»" }
    return String(describing: value)
}

/// Several checks reported as one step: PASS when all hold, FAIL listing each one that does not.
final class Step {
    let name: String
    private(set) var problems: [String] = []

    init(_ name: String) { self.name = name }

    func eq<T: Equatable>(_ actual: T, _ expected: T, _ what: String) {
        if actual != expected { problems.append("\(what): expected \(show(expected)), got \(show(actual))") }
    }

    func ok(_ condition: Bool, _ what: @autoclosure () -> String) {
        if !condition { problems.append(what()) }
    }

    func done() {
        if problems.isEmpty { Report.pass(name) } else { Report.fail(name, problems.joined(separator: "\n          ")) }
    }
}

/// Builds and reports a step in one go.
func step(_ name: String, _ body: (Step) -> Void) {
    let s = Step(name)
    body(s)
    s.done()
}
