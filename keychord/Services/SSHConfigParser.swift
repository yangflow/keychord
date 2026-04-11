import Foundation

struct SSHConfigLine: Equatable, Hashable, Sendable {
    var raw: String
    var kind: Kind

    enum Kind: Equatable, Hashable, Sendable {
        case blank
        case comment
        case hostHeader(aliases: [String])
        case field(key: String, value: String, indent: String)
        case include(path: String)
        case unknownDirective
    }
}

struct SSHConfigDocument: Equatable, Sendable {
    var lines: [SSHConfigLine]

    static func parse(_ text: String) -> SSHConfigDocument {
        if text.isEmpty { return SSHConfigDocument(lines: []) }
        var parsed: [SSHConfigLine] = []
        let raws = text.components(separatedBy: "\n")
        for raw in raws {
            parsed.append(SSHConfigLine(raw: raw, kind: Self.classify(raw)))
        }
        return SSHConfigDocument(lines: parsed)
    }

    func serialize() -> String {
        lines.map(\.raw).joined(separator: "\n")
    }

    // MARK: - Model extraction

    func extractHosts() -> [SSHHost] {
        var hosts: [SSHHost] = []
        var current: SSHHost?
        for line in lines {
            switch line.kind {
            case .hostHeader(let aliases):
                if let cur = current { hosts.append(cur) }
                current = SSHHost(alias: aliases.first ?? "")
            case .field(let key, let value, _):
                guard var host = current else { continue }
                Self.assign(&host, key: key, value: value)
                current = host
            case .blank, .comment, .include, .unknownDirective:
                continue
            }
        }
        if let cur = current { hosts.append(cur) }
        return hosts
    }

    // MARK: - Mutation

    /// Set (or clear) a field on a given Host block, preserving indent and line order.
    /// If the field does not exist in that block and `value != nil`, it is appended
    /// at the end of the block. If `value == nil`, the matching line is removed.
    @discardableResult
    mutating func setField(_ key: String, to value: String?, forHost alias: String) -> Bool {
        guard let range = hostBlockRange(alias: alias) else { return false }
        let lowerKey = key.lowercased()

        for i in range {
            guard case .field(let k, _, let indent) = lines[i].kind else { continue }
            if k.lowercased() == lowerKey {
                if let value {
                    let canonical = Self.canonicalKey(key)
                    let newRaw = indent + canonical + " " + value
                    lines[i] = SSHConfigLine(
                        raw: newRaw,
                        kind: .field(key: canonical, value: value, indent: indent)
                    )
                } else {
                    lines.remove(at: i)
                }
                return true
            }
        }

        guard let value else { return false }
        let indent = inferIndent(in: range) ?? "  "
        let canonical = Self.canonicalKey(key)
        let newLine = SSHConfigLine(
            raw: indent + canonical + " " + value,
            kind: .field(key: canonical, value: value, indent: indent)
        )
        lines.insert(newLine, at: range.upperBound)
        return true
    }

    private func hostBlockRange(alias: String) -> Range<Int>? {
        for i in lines.indices {
            if case .hostHeader(let aliases) = lines[i].kind, aliases.contains(alias) {
                var end = lines.count
                for j in (i + 1)..<lines.count {
                    if case .hostHeader = lines[j].kind { end = j; break }
                }
                return (i + 1)..<end
            }
        }
        return nil
    }

    /// Append a new Host block at the end of the document. The block
    /// is supplied as raw text (multi-line); a single blank line is
    /// inserted before it if the existing content does not already end
    /// with one, so blocks stay visually separated.
    mutating func appendHostBlock(_ raw: String) {
        let needsSeparator: Bool
        if lines.isEmpty {
            needsSeparator = false
        } else if let last = lines.last, case .blank = last.kind {
            needsSeparator = false
        } else {
            needsSeparator = true
        }
        if needsSeparator {
            lines.append(SSHConfigLine(raw: "", kind: .blank))
        }
        let appended = SSHConfigDocument.parse(raw)
        // Drop a trailing empty line the parser adds when the raw
        // string ends with "\n", so we don't accumulate blanks.
        var toAppend = appended.lines
        if let last = toAppend.last, case .blank = last.kind, last.raw.isEmpty {
            toAppend.removeLast()
        }
        lines.append(contentsOf: toAppend)
    }

    /// Remove an entire Host block — header line and every line that
    /// belongs to it, up to (but not including) the next Host header.
    /// Comments and blank lines surrounding other Host blocks stay
    /// untouched. Returns false if the alias is not found.
    @discardableResult
    mutating func removeHost(alias: String) -> Bool {
        for i in lines.indices {
            if case .hostHeader(let aliases) = lines[i].kind, aliases.contains(alias) {
                var end = lines.count
                for j in (i + 1)..<lines.count {
                    if case .hostHeader = lines[j].kind { end = j; break }
                }
                lines.removeSubrange(i..<end)
                return true
            }
        }
        return false
    }

    private func inferIndent(in range: Range<Int>) -> String? {
        for i in range {
            if case .field(_, _, let indent) = lines[i].kind { return indent }
        }
        return nil
    }

    // MARK: - Line classification

    private static func classify(_ raw: String) -> SSHConfigLine.Kind {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return .blank }
        if trimmed.hasPrefix("#") { return .comment }

        let indent = String(raw.prefix { $0 == " " || $0 == "\t" })
        let afterIndent = String(raw.dropFirst(indent.count))

        let separators: Set<Character> = [" ", "\t", "="]
        guard let sepIdx = afterIndent.firstIndex(where: { separators.contains($0) }) else {
            return .unknownDirective
        }

        let key = String(afterIndent[..<sepIdx])
        var rest = String(afterIndent[afterIndent.index(after: sepIdx)...])
        while let first = rest.first, separators.contains(first) { rest.removeFirst() }
        let value = rest.trimmingCharacters(in: .whitespaces)

        switch key.lowercased() {
        case "host":
            let aliases = value.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            return .hostHeader(aliases: aliases)
        case "include":
            return .include(path: value)
        default:
            return .field(key: key, value: value, indent: indent)
        }
    }

    // MARK: - Field assignment + canonicalization

    private static func assign(_ host: inout SSHHost, key: String, value: String) {
        let v = unquote(value)
        switch key.lowercased() {
        case "hostname":       host.hostName = v
        case "port":           host.port = Int(v)
        case "user":           host.user = v
        case "identityfile":   host.identityFile = v
        case "identitiesonly": host.identitiesOnly = parseYesNo(v)
        case "hostkeyalias":   host.hostKeyAlias = v
        case "proxycommand":   host.proxyCommand = v
        case "proxyjump":      host.proxyJump = v
        default:
            host.extraDirectives.append(SSHDirective(key: key, value: v))
        }
    }

    private static func parseYesNo(_ s: String) -> Bool? {
        switch s.lowercased() {
        case "yes", "true":  return true
        case "no", "false":  return false
        default:             return nil
        }
    }

    private static func unquote(_ s: String) -> String {
        guard s.count >= 2, s.first == "\"", s.last == "\"" else { return s }
        return String(s.dropFirst().dropLast())
    }

    private static func canonicalKey(_ key: String) -> String {
        let mapping: [String: String] = [
            "hostname":       "HostName",
            "port":           "Port",
            "user":           "User",
            "identityfile":   "IdentityFile",
            "identitiesonly": "IdentitiesOnly",
            "hostkeyalias":   "HostKeyAlias",
            "proxycommand":   "ProxyCommand",
            "proxyjump":      "ProxyJump"
        ]
        return mapping[key.lowercased()] ?? key
    }
}
