import Foundation

/// Points as they are typed and shown: Western digits only, and a real minus sign.
nonisolated enum Digits {
    /// Keeps the digits of `text` (Arabic-Indic and Eastern Arabic ones become Western), at most `limit` of them.
    static func clean(_ text: String, limit: Int = 3) -> String {
        var out = ""
        for scalar in text.unicodeScalars {
            let v = scalar.value
            let digit: UInt32?
            switch v {
            case 0x30...0x39: digit = v - 0x30
            case 0x0660...0x0669: digit = v - 0x0660
            case 0x06F0...0x06F9: digit = v - 0x06F0
            default: digit = nil
            }
            guard let digit, let western = Unicode.Scalar(0x30 + digit) else { continue }
            out.unicodeScalars.append(western)
            if out.count == limit { break }
        }
        return out
    }

    /// What a صكة field keeps as the player types: `clean`, and no 0 in front of another digit, so a hand edited
    /// from 0 reads 1 (not 01) after one digit and only two real digits move on to «لهم». A lone 0 stays.
    static func field(_ text: String, limit: Int = 3) -> String {
        let digits = clean(text, limit: .max)
        let trimmed = digits.drop { $0 == "0" }
        if trimmed.isEmpty { return digits.isEmpty ? "" : "0" }
        return String(trimmed.prefix(limit))
    }

    /// The number typed in a field; an empty field counts as 0.
    static func value(_ text: String) -> Int {
        Int(clean(text)) ?? 0
    }

    /// −60 with U+2212, as on the boards. Interpolating an Int never localises its digits.
    static func signed(_ n: Int) -> String {
        n < 0 ? "\u{2212}\(-n)" : "\(n)"
    }

    /// The الفرق line of آخر جولة: «+501» for what a player has over the first, «0» for the first himself.
    static func gap(_ n: Int) -> String {
        n > 0 ? "+\(n)" : signed(n)
    }

    /// Wraps a number that may carry a sign so it keeps its order inside a right-to-left line.
    static func isolated(_ text: String) -> String {
        "\u{2066}" + text + "\u{2069}"
    }
}

/// Arabic counted phrases, with the dual and the plural ranges the boards use.
nonisolated enum ArabicCount {
    /// «بعد لعبة وحدة» … «بعد 11 لعبة» (صكة).
    static func hands(_ n: Int) -> String {
        switch n {
        case 1: return "بعد لعبة وحدة"
        case 2: return "بعد لعبتين"
        case 3...10: return "بعد \(n) لعبات"
        default: return "بعد \(n) لعبة"
        }
    }

    /// «بعد جولة وحدة» … «بعد 11 جولة» (الهند).
    static func rounds(_ n: Int) -> String {
        switch n {
        case 1: return "بعد جولة وحدة"
        case 2: return "بعد جولتين"
        case 3...10: return "بعد \(n) جولات"
        default: return "بعد \(n) جولة"
        }
    }

    /// «نزول واحد» «نزولين» «3 نزولات» «11 نزول».
    static func downs(_ n: Int) -> String {
        switch n {
        case 1: return "نزول واحد"
        case 2: return "نزولين"
        case 3...10: return "\(n) نزولات"
        default: return "\(n) نزول"
        }
    }
}
