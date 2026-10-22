//
//  MediaInspectorTests.swift
//  LaqtaTests
//
//  Size, length, recording time and place read from real video and PDF files.
//

import Foundation
import Testing
@testable import Laqta

private final class BundleToken {}

@Suite("Reading media files")
struct MediaInspectorTests {
    private func resource(_ name: String) throws -> URL {
        try #require(Bundle(for: BundleToken.self).url(forResource: name, withExtension: nil), "Missing test file \(name)")
    }

    @Test func iPhoneVideo() async throws {
        let url = try resource("walk-iphone.mov")
        #expect(MediaInspector.kind(forFileAt: url) == .video)
        let info = try #require(await MediaInspector.videoInfo(at: url))
        #expect(abs((info.duration ?? 0) - 1.2) < 0.1)
        #expect(info.pixelWidth == 180)
        #expect(info.pixelHeight == 320)
        #expect(info.hasAudio == false)
        // QuickTime creation dates keep the time zone.
        #expect(info.capturedAt == Date(timeIntervalSince1970: 1_780_384_530))
        #expect(info.captureOffsetKnown)
        #expect(info.cameraModel?.contains("iPhone 17 Pro") == true)
        #expect(abs((info.latitude ?? 0) - 48.8584) < 0.0001)
        #expect(abs((info.longitude ?? 0) - 2.2945) < 0.0001)
        #expect(!info.isScreenCapture)
    }

    /// Older cameras and QuickTime tools write the place in the user-data atom (©xyz).
    @Test func cameraVideoWithUserDataLocation() async throws {
        let url = try resource("walk-camera.mov")
        let info = try #require(await MediaInspector.videoInfo(at: url))
        #expect(abs((info.duration ?? 0) - 1.5) < 0.1)
        #expect(info.pixelWidth == 320)
        #expect(info.pixelHeight == 180)
        #expect(info.hasAudio == true)
        #expect(info.capturedAt == Date(timeIntervalSince1970: 1_773_508_800))
        #expect(abs((info.latitude ?? 0) - 29.3759) < 0.0001, "The ©xyz location is read")
        #expect(abs((info.longitude ?? 0) - 47.9774) < 0.0001)
    }

    @Test func screenRecording() async throws {
        let info = try #require(await MediaInspector.videoInfo(at: try resource("screen-recording.mp4")))
        #expect(info.isScreenCapture)
        #expect(info.latitude == nil)
        #expect(info.cameraModel == nil)
    }

    @Test func pdf() throws {
        let url = try resource("trip-plan.pdf")
        #expect(MediaInspector.kind(forFileAt: url) == .document)
        let info = try #require(MediaInspector.documentInfo(at: url))
        #expect(info.pageCount == 2)
        #expect(info.title == "Trip Plan — London")
        #expect(!info.isEncrypted)
    }

    @Test("ISO 6709 locations", arguments: [
        ("+29.3759+047.9774/", 29.3759, 47.9774),
        ("+48.8584+002.2945+035.000/", 48.8584, 2.2945),
        ("-33.8568+151.2153/", -33.8568, 151.2153)
    ])
    func locations(_ value: String, _ latitude: Double, _ longitude: Double) throws {
        let parsed = try #require(MediaInspector.parseISO6709(value))
        #expect(abs(parsed.latitude - latitude) < 0.00001)
        #expect(abs(parsed.longitude - longitude) < 0.00001)
    }

    @Test("Rejects broken locations", arguments: ["", "29.37,47.97", "+95.0000+010.0000/", "+00.0000+000.0000/"])
    func brokenLocations(_ value: String) {
        #expect(MediaInspector.parseISO6709(value) == nil)
    }

    @Test("Camera names people can read", arguments: [
        ("NIKON CORPORATION NIKON D800E", "NIKON D800E"),
        ("OLYMPUS IMAGING CORP. E-M5", "OLYMPUS E-M5"),
        ("RICOH IMAGING COMPANY, LTD. GR III", "RICOH GR III"),
        ("Leica Camera AG LEICA Q3", "Leica Q3"),
        ("Apple iPhone 17 Pro", "Apple iPhone 17 Pro"),
        ("Canon EOS R5", "Canon EOS R5"),
        ("Kodak Digital Camera", "Kodak Digital Camera"),
        ("SONY", "SONY")
    ])
    func cameraNames(_ stored: String, _ shown: String) {
        #expect(ImageTools.displayCameraName(stored) == shown)
    }
}
