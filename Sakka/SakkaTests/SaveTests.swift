import Foundation
import Testing
#if canImport(SakkaRules)
@testable import SakkaRules
#else
@testable import Sakka
#endif

/// A save as JSON objects, to damage it the way a bad write or a newer build could.
private func object(_ data: Data) -> [String: Any] {
    (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
}

private func data(_ object: [String: Any]) -> Data {
    (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
}

private let typed: [String: EntryCell] = {
    var e = HandRules.emptyEntry(boardPlayers)
    e["p1"] = EntryCell(kind: .hand)
    e["p2"] = EntryCell(kind: .cards, digits: "35")
    e["p3"] = .notDown
    return e
}()

@Suite("الحفظ")
struct SaveTests {
    @Test("A saved الهند reads back as it was, with the round being typed")
    func handRoundTrip() throws {
        let save = HandSave(players: boardPlayers, rounds: Array(boardRounds.prefix(3)), entry: typed, uid: 103, started: true)
        let back = try #require(HandSave.read(try JSONEncoder().encode(save)))
        #expect(back == save)
        #expect(!back.mended)
    }

    @Test("A round the app can't read is dropped, not the whole game")
    func handUnknownKind() throws {
        let save = HandSave(players: boardPlayers, rounds: Array(boardRounds.prefix(3)), entry: typed, uid: 103, started: true)
        var json = object(try JSONEncoder().encode(save))
        var rounds = json["rounds"] as? [[String: Any]] ?? []
        var cells = rounds[1]["cells"] as? [String: Any] ?? [:]
        cells["p3"] = ["kind": "hand1", "cards": 0]
        rounds[1]["cells"] = cells
        json["rounds"] = rounds
        let back = try #require(HandSave.read(data(json)))
        #expect(back.players == boardPlayers)
        #expect(back.rounds.map(\.id) == [1, 3])
        #expect(back.entry == typed)
        #expect(back.mended)
    }

    @Test("Missing values take their defaults, and the id counter passes every id in use")
    func handDefaults() throws {
        let players = [HandPlayer(id: "p1", name: "حمد"), HandPlayer(id: "p101", name: "فهد")]
        let save = HandSave(players: players, rounds: [], entry: HandRules.emptyEntry(players), uid: 100, started: true)
        var json = object(try JSONEncoder().encode(save))
        json["started"] = nil
        json["entry"] = nil
        let back = try #require(HandSave.read(data(json)))
        #expect(back.started)
        #expect(back.entry == HandRules.emptyEntry(players))
        #expect(back.uid == 101)
        #expect(back.mended)
    }

    @Test("Bad fields in the round being typed are emptied; bad players or counts can't be played")
    func handRepairs() throws {
        var entry = typed
        entry["p4"] = EntryCell(kind: .cards, digits: "0x9")
        let save = HandSave(players: boardPlayers + [HandPlayer(id: "p1", name: "مكرر")], rounds: [], entry: entry, uid: 100, started: true)
        let back = try #require(HandSave.read(try JSONEncoder().encode(save)))
        #expect(back.players == boardPlayers)
        #expect(back.entry["p4"] == .empty)
        let seven = (1...7).map { HandPlayer(id: "p\($0)", name: "") }
        let tooMany = HandSave(players: seven, rounds: [], entry: [:], uid: 100, started: true)
        #expect(HandSave.read(try JSONEncoder().encode(tooMany)) == nil)
        #expect(HandSave.read(Data("not json".utf8)) == nil)
    }

    @Test("A صكة keeps its good hands and its «فوق المية» through a damaged save")
    func baloot() throws {
        let hands = [BalootHand(id: 1, us: 60, them: 10), BalootHand(id: 1, us: 20, them: 0),
                     BalootHand(id: 3, us: 1000, them: 0), BalootHand(id: 4, us: 0, them: 0)]
        let save = BalootSave(hands: hands, said: [.us])
        var json = object(try JSONEncoder().encode(save))
        json["said"] = ["us", "x"]
        let back = try #require(BalootSave.read(data(json)))
        #expect(back.hands == [BalootHand(id: 1, us: 60, them: 10), BalootHand(id: 2, us: 20, them: 0)])
        // لنا went past 100 once and came back under: still said, so it is never repeated.
        #expect(back.said == [.us])
        #expect(back.mended)
        let clean = BalootSave(hands: [BalootHand(id: 1, us: 120, them: 30)], said: [.us])
        let same = try #require(BalootSave.read(try JSONEncoder().encode(clean)))
        #expect(same == clean)
        #expect(!same.mended)
    }
}
