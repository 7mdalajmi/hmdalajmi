//
//  FolderMoods.swift
//  Laqta — Shared
//
//  Fifty-six cover moods. Each one is a nine-colour mesh built from three
//  anchors — a deep, a mid and a glow — so the whole set fits in a table
//  instead of five hundred hand-typed hex values.
//
//  What holds them together is the glow. Laqta's original five all highlight
//  warm: Tide's is a dulled teal, Olive's is gold, Dusk's is outright salmon.
//  Every mood here was built the same way, each glow pulled a share of the way
//  toward the same gold and capped so nothing out-saturates it. That is why
//  fifty-six moods read as one family rather than a colour wheel.
//
//  The five Laqta shipped with keep their own hand-set mesh, so folders made
//  before this still look exactly as they did.
//

import SwiftUI

// MARK: - Families

nonisolated enum FolderToneFamily: String, CaseIterable, Identifiable, Sendable {
    case warm
    case gold
    case green
    case blue
    case violet
    case rose
    case stone

    var id: String { rawValue }

    var title: String {
        switch self {
        case .warm: "Warm earth"
        case .gold: "Gold and sand"
        case .green: "Green"
        case .blue: "Blue and teal"
        case .violet: "Indigo and violet"
        case .rose: "Rose and wine"
        case .stone: "Stone"
        }
    }

    var tones: [FolderTone] {
        FolderTone.allCases.filter { $0.family == self }
    }
}

// MARK: - The moods

nonisolated enum FolderTone: String, CaseIterable, Identifiable, Sendable {
    case ember
    case clay
    case terracotta
    case rust
    case cinnamon
    case henna
    case brick
    case copper
    case sand
    case dune
    case wheat
    case brass
    case honey
    case saffron
    case parchment
    case camel
    case olive
    case moss
    case fern
    case sage
    case cedar
    case pistachio
    case jade
    case basil
    case tide
    case lagoon
    case petrol
    case glacier
    case denim
    case cobalt
    case slate
    case harbour
    case dusk
    case indigo
    case iris
    case lilac
    case amethyst
    case plum
    case fig
    case orchid
    case rose
    case mauve
    case blush
    case wine
    case coral
    case garnet
    case peony
    case magenta
    case graphite
    case ink
    case ash
    case pewter
    case smoke
    case bone
    case pearl
    case char

    var id: String { rawValue }
    var title: String { Self.recipe(self).title }
    var family: FolderToneFamily { Self.recipe(self).family }

    /// 3 × 3 mesh for the cover gradient, read left-to-right, top-to-bottom.
    var meshColors: [Color] {
        Self.meshHexes(self).map { Color(hex: $0) }
    }

    /// The one colour that stands for the mood in a swatch.
    var swatch: Color { Color(hex: Self.meshHexes(self)[5]) }

    /// Grouped for the picker, so a wall of fifty-six reads as seven rows.
    static let byFamily: [(family: FolderToneFamily, tones: [FolderTone])] =
        FolderToneFamily.allCases.map { ($0, $0.tones) }

    // MARK: Building a mesh

    nonisolated struct Recipe: Sendable {
        let title: String
        let family: FolderToneFamily
        let deep: UInt32
        let mid: UInt32
        let glow: UInt32
        /// Set only on the five that shipped before this table existed.
        let mesh: [UInt32]?
    }

    static func recipe(_ tone: FolderTone) -> Recipe {
        // Every case is in the table; the fallback keeps this total.
        recipes[tone] ?? Recipe(title: tone.rawValue.capitalized, family: .stone,
                                deep: 0x141414, mid: 0x3A3A3A, glow: 0x8C8C8C, mesh: nil)
    }

    /// Every mesh, worked out once. Each cover draws its mood three times —
    /// behind the photo and twice over it — so this runs on a warm path.
    private static let meshes: [FolderTone: [UInt32]] = Dictionary(
        uniqueKeysWithValues: FolderTone.allCases.map { ($0, buildMesh($0)) }
    )

    static func meshHexes(_ tone: FolderTone) -> [UInt32] {
        meshes[tone] ?? buildMesh(tone)
    }

    /// Column one stays deep, column two carries the hue, column three lifts
    /// into the glow as it goes down — the shape Laqta's first five all share.
    private static func buildMesh(_ tone: FolderTone) -> [UInt32] {
        let recipe = recipe(tone)
        if let mesh = recipe.mesh, mesh.count == 9 { return mesh }
        let deep = recipe.deep, mid = recipe.mid, glow = recipe.glow
        return [
            deep,               blend(deep, mid, 0.85), blend(mid, glow, 0.32),
            deep,               mid,                    blend(mid, glow, 0.72),
            blend(deep, mid, 0.06), blend(deep, mid, 0.76), glow
        ]
    }

    /// Straight RGB mix. Good enough between two colours of one hue, and it
    /// keeps the table to three anchors instead of nine.
    static func blend(_ from: UInt32, _ to: UInt32, _ amount: Double) -> UInt32 {
        func channel(_ shift: UInt32) -> UInt32 {
            let a = Double((from >> shift) & 0xFF)
            let b = Double((to >> shift) & 0xFF)
            let mixed = (a + (b - a) * amount).rounded()
            return UInt32(min(max(mixed, 0), 255))
        }
        return (channel(16) << 16) | (channel(8) << 8) | channel(0)
    }

    // MARK: Compatibility

    /// Maps the v1 colour keys onto the moods.
    static func fromLegacy(_ key: String) -> FolderTone {
        switch key {
        case "blue", "indigo": .harbour
        case "teal", "mint": .tide
        case "purple": .dusk
        case "pink": .rose
        case "graphite": .graphite
        case "red": .henna
        case "orange": .ember
        case "green": .olive
        default: .sand
        }
    }

    private static let recipes: [FolderTone: Recipe] = [
        .ember: Recipe(title: "Ember", family: .warm, deep: 0x210E0A, mid: 0x5E2E1F, glow: 0xC49166, mesh: [0x3D140E, 0x85301B, 0x8A4422, 0x3F140E, 0x7E2918, 0xBB7339, 0x3F140E, 0x7A2319, 0xD89046]),
        .clay: Recipe(title: "Clay", family: .warm, deep: 0x221814, mid: 0x4F3B30, glow: 0xB09172, mesh: nil),
        .terracotta: Recipe(title: "Terracotta", family: .warm, deep: 0x280F09, mid: 0x6B311C, glow: 0xCA9764, mesh: nil),
        .rust: Recipe(title: "Rust", family: .warm, deep: 0x210C0A, mid: 0x5E281F, glow: 0xC48B66, mesh: nil),
        .cinnamon: Recipe(title: "Cinnamon", family: .warm, deep: 0x21130A, mid: 0x5E3A1F, glow: 0xC49E66, mesh: nil),
        .henna: Recipe(title: "Henna", family: .warm, deep: 0x210A0A, mid: 0x5E231F, glow: 0xC48766, mesh: nil),
        .brick: Recipe(title: "Brick", family: .warm, deep: 0x221414, mid: 0x4F3130, glow: 0xB08372, mesh: nil),
        .copper: Recipe(title: "Copper", family: .warm, deep: 0x21110A, mid: 0x5E361F, glow: 0xC49A66, mesh: nil),
        .sand: Recipe(title: "Sand", family: .gold, deep: 0x74634E, mid: 0xA48D6A, glow: 0xD3C4A5, mesh: [0x796449, 0xA98B65, 0xB29973, 0x796449, 0xA48660, 0xD4BC91, 0x7B654A, 0xA0825C, 0xE5CD9F]),
        .dune: Recipe(title: "Dune", family: .gold, deep: 0x74614E, mid: 0xA4896A, glow: 0xD3C2A5, mesh: nil),
        .wheat: Recipe(title: "Wheat", family: .gold, deep: 0x74694E, mid: 0xA4956A, glow: 0xD3C8A5, mesh: nil),
        .brass: Recipe(title: "Brass", family: .gold, deep: 0x21180A, mid: 0x5E491F, glow: 0xC4AF66, mesh: nil),
        .honey: Recipe(title: "Honey", family: .gold, deep: 0x21170A, mid: 0x5E471F, glow: 0xC4AC66, mesh: nil),
        .saffron: Recipe(title: "Saffron", family: .gold, deep: 0x21140A, mid: 0x5E3E1F, glow: 0xC4A366, mesh: nil),
        .parchment: Recipe(title: "Parchment", family: .gold, deep: 0x746B4E, mid: 0xA4986A, glow: 0xD3C9A5, mesh: nil),
        .camel: Recipe(title: "Camel", family: .gold, deep: 0x221B14, mid: 0x4F4230, glow: 0xB09C72, mesh: nil),
        .olive: Recipe(title: "Olive", family: .green, deep: 0x21210A, mid: 0x5A5E1F, glow: 0xB4BA66, mesh: [0x1E2213, 0x38441F, 0xA99246, 0x1D2313, 0x374320, 0x8F7F3D, 0x1F2313, 0x34421F, 0x525025]),
        .moss: Recipe(title: "Moss", family: .green, deep: 0x1B2214, mid: 0x3F4F30, glow: 0x91AA72, mesh: nil),
        .fern: Recipe(title: "Fern", family: .green, deep: 0x0C210A, mid: 0x215E1F, glow: 0x80BA6F, mesh: nil),
        .sage: Recipe(title: "Sage", family: .green, deep: 0x59744E, mid: 0x7AA46A, glow: 0xBCCDA5, mesh: nil),
        .cedar: Recipe(title: "Cedar", family: .green, deep: 0x1E2214, mid: 0x454F30, glow: 0x9AAA72, mesh: nil),
        .pistachio: Recipe(title: "Pistachio", family: .green, deep: 0x6D744E, mid: 0x96A46A, glow: 0xCACDA5, mesh: nil),
        .jade: Recipe(title: "Jade", family: .green, deep: 0x0A2115, mid: 0x1F5E41, glow: 0x80BA94, mesh: nil),
        .basil: Recipe(title: "Basil", family: .green, deep: 0x0A210D, mid: 0x1F5E2C, glow: 0x80BA7E, mesh: nil),
        .tide: Recipe(title: "Tide", family: .blue, deep: 0x0A1E21, mid: 0x1F515E, glow: 0x80A1A9, mesh: [0x0C222F, 0x134356, 0x5DA2A7, 0x0C2230, 0x123F57, 0x46828B, 0x0C2331, 0x113D5A, 0x1C4A57]),
        .lagoon: Recipe(title: "Lagoon", family: .blue, deep: 0x0A211D, mid: 0x1F5E55, glow: 0x80B7A9, mesh: nil),
        .petrol: Recipe(title: "Petrol", family: .blue, deep: 0x142122, mid: 0x304C4F, glow: 0x829FA0, mesh: nil),
        .glacier: Recipe(title: "Glacier", family: .blue, deep: 0x4E6A74, mid: 0x6A93A4, glow: 0xB7C2C1, mesh: nil),
        .denim: Recipe(title: "Denim", family: .blue, deep: 0x141B22, mid: 0x303E4F, glow: 0x828AA0, mesh: nil),
        .cobalt: Recipe(title: "Cobalt", family: .blue, deep: 0x0A1321, mid: 0x1F325E, glow: 0x8080A9, mesh: nil),
        .slate: Recipe(title: "Slate", family: .blue, deep: 0x141617, mid: 0x363B3F, glow: 0x868F90, mesh: nil),
        .harbour: Recipe(title: "Harbour", family: .blue, deep: 0x0A1A21, mid: 0x1F475E, glow: 0x8096A9, mesh: nil),
        .dusk: Recipe(title: "Dusk", family: .violet, deep: 0x1E0A21, mid: 0x5A1F5E, glow: 0xC477A2, mesh: [0x2B152A, 0x4D2759, 0x713C4D, 0x2A152A, 0x512755, 0xB26D64, 0x281529, 0x51274D, 0xD28570]),
        .indigo: Recipe(title: "Indigo", family: .violet, deep: 0x0A0C21, mid: 0x1F1F5E, glow: 0x8C77A9, mesh: nil),
        .iris: Recipe(title: "Iris", family: .violet, deep: 0x0F0A21, mid: 0x301F5E, glow: 0x9E77A9, mesh: nil),
        .lilac: Recipe(title: "Lilac", family: .violet, deep: 0x614E74, mid: 0x896AA4, glow: 0xC9B1C1, mesh: nil),
        .amethyst: Recipe(title: "Amethyst", family: .violet, deep: 0x190A21, mid: 0x4B1F5E, glow: 0xBB77A9, mesh: nil),
        .plum: Recipe(title: "Plum", family: .violet, deep: 0x210A1F, mid: 0x5E1F53, glow: 0xC47792, mesh: nil),
        .fig: Recipe(title: "Fig", family: .violet, deep: 0x1E1422, mid: 0x49304F, glow: 0xAD7CA0, mesh: nil),
        .orchid: Recipe(title: "Orchid", family: .violet, deep: 0x200A21, mid: 0x5E1F5E, glow: 0xC4779E, mesh: nil),
        .rose: Recipe(title: "Rose", family: .rose, deep: 0x210A13, mid: 0x5E1F32, glow: 0xC4776F, mesh: nil),
        .mauve: Recipe(title: "Mauve", family: .rose, deep: 0x22141C, mid: 0x4F3041, glow: 0xB07C84, mesh: nil),
        .blush: Recipe(title: "Blush", family: .rose, deep: 0x744E55, mid: 0xA46A74, glow: 0xD3B1A8, mesh: nil),
        .wine: Recipe(title: "Wine", family: .rose, deep: 0x210A14, mid: 0x5E1F36, glow: 0xC47773, mesh: nil),
        .coral: Recipe(title: "Coral", family: .rose, deep: 0x210A0D, mid: 0x5E1F23, glow: 0xC47E66, mesh: nil),
        .garnet: Recipe(title: "Garnet", family: .rose, deep: 0x210A11, mid: 0x5E1F2E, glow: 0xC4776A, mesh: nil),
        .peony: Recipe(title: "Peony", family: .rose, deep: 0x744E6A, mid: 0xA46A93, glow: 0xD3B1B7, mesh: nil),
        .magenta: Recipe(title: "Magenta", family: .rose, deep: 0x210A1A, mid: 0x5E1F47, glow: 0xC47785, mesh: nil),
        .graphite: Recipe(title: "Graphite", family: .stone, deep: 0x141517, mid: 0x36393F, glow: 0x868990, mesh: nil),
        .ink: Recipe(title: "Ink", family: .stone, deep: 0x0C0F18, mid: 0x20263C, glow: 0x636585, mesh: nil),
        .ash: Recipe(title: "Ash", family: .stone, deep: 0x171614, mid: 0x3F3B36, glow: 0x9B8D7B, mesh: nil),
        .pewter: Recipe(title: "Pewter", family: .stone, deep: 0x141617, mid: 0x363C3F, glow: 0x869090, mesh: nil),
        .smoke: Recipe(title: "Smoke", family: .stone, deep: 0x151417, mid: 0x39363F, glow: 0x8E8290, mesh: nil),
        .bone: Recipe(title: "Bone", family: .stone, deep: 0x74664E, mid: 0xA4916A, glow: 0xD3C5A5, mesh: nil),
        .pearl: Recipe(title: "Pearl", family: .stone, deep: 0x4E6F74, mid: 0x6A9AA4, glow: 0xB7C5C1, mesh: nil),
        .char: Recipe(title: "Char", family: .stone, deep: 0x180F0C, mid: 0x3C2720, glow: 0x8E6E5A, mesh: nil),
    ]
}
