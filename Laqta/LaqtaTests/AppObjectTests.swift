//
//  AppObjectTests.swift
//  LaqtaTests
//
//  Views keep working when SwiftUI evaluates them without Laqta's environment
//  (the crash "No Observable object of type IntelligenceCenter found").
//

import Observation
import SwiftUI
import Testing
@testable import Laqta

@Observable
private final class Probe {
    var name = "Probe"
}

@Observable
private final class WindowProbe {}

/// Remembers which object a view was given.
private final class Seen {
    var object: AnyObject?
}

private struct ProbeView: View {
    let seen: Seen
    @AppObject(Probe.self) private var probe

    var body: some View {
        seen.object = probe
        return Text(verbatim: probe.name)
    }
}

private struct WindowProbeView: View {
    let seen: Seen
    @AppObject(WindowProbe.self, otherwise: { WindowProbe() }) private var probe

    var body: some View {
        seen.object = probe
        return Color.clear.frame(width: 4, height: 4)
    }
}

@Suite("App objects")
struct AppObjectTests {
    @Test func laqtaRegistersItsObjects() {
        // The test host is Laqta itself, so LaqtaApp registered everything at launch.
        #expect(AppObjects.registered(LibraryStore.self) != nil)
        #expect(AppObjects.registered(LibraryModel.self) != nil)
        #expect(AppObjects.registered(IntelligenceCenter.self) != nil)
        #expect(AppObjects.registered(Maintenance.self) != nil)
    }

    @Test func viewWithoutTheEnvironmentGetsTheAppsObject() {
        let probe = Probe()
        AppObjects.register(probe)
        let seen = Seen()
        #expect(ImageRenderer(content: ProbeView(seen: seen)).uiImage != nil)
        #expect(seen.object === probe)
    }

    @Test func environmentComesFirst() {
        AppObjects.register(Probe())
        let local = Probe()
        let seen = Seen()
        #expect(ImageRenderer(content: ProbeView(seen: seen).environment(local)).uiImage != nil)
        #expect(seen.object === local)
    }

    @Test func windowObjectGetsADetachedStandIn() {
        let seen = Seen()
        #expect(ImageRenderer(content: WindowProbeView(seen: seen)).uiImage != nil)
        #expect(seen.object is WindowProbe)
        #expect(AppObjects.registered(WindowProbe.self) == nil)
    }
}
