// Test-only, shared by the NWEndpoint.Host and NWEndpoint.Port differential. Built against Apple's Network and against this
// tree's Network; the two outputs must be identical. Zones are en0 (see ipv6/report.swift for why not lo0).
import Foundation
import Network

let endpointHostStrings = [
    "example.com", "1.2.3.4", "::1", "fe80::1%en0", "fe80::1%bogus", "1.2.3", "", "a b", "EXAMPLE", "%en0",
    "example.com%en0", "1.2.3.4%en0", "0x1.2.3.4", "1.2.3.4%", "::1%", "localhost", "a.b.c.d", "-x", "x-", "1.2.3.4.5",
    "host_name", "ex ample", "2001:db8::1", "::ffff:1.2.3.4", "1.2.3.4a", "example.com.", "1..2", "[::1]", "fe80::1%14",
    "\u{e9}.example", "exa\u{0}mple", "example.com%bogus", "999.1.1.1", "1:2:3:4:5:6:7:8:9", "a:b"
]

func endpointHostDescribe(_ host: NWEndpoint.Host) -> String {
    let interface = host.interface.map { "\($0.name)/\($0.index)" } ?? "nil"
    var kind = "?"
    switch host {
    case .name(let name, _):
        kind = "name(\(name.debugDescription))"
    case .ipv4(let address):
        kind = "ipv4(\(address.debugDescription))"
    case .ipv6(let address):
        kind = "ipv6(\(address.debugDescription))"
    @unknown default:
        kind = "unknown"
    }
    return "\(kind) debug=\(host.debugDescription) iface=\(interface)"
}

func endpointReport() {
    for text in endpointHostStrings {
        print("host\t\(text.debugDescription)\t\(endpointHostDescribe(NWEndpoint.Host(text)))")
    }
    let literal: NWEndpoint.Host = "example.com"
    print("literal\t\(endpointHostDescribe(literal))")
    print("stringLiteral\t\(endpointHostDescribe(NWEndpoint.Host(stringLiteral: "1.2.3.4")))")
    print("nameConstructor\t\(endpointHostDescribe(NWEndpoint.Host.name("example.com", nil)))")
    print("nameInterface\t\(endpointHostDescribe(NWEndpoint.Host.name("example.com", IPv4Address("1.2.3.4%en0")?.interface)))")
    print("ipv4Constructor\t\(endpointHostDescribe(NWEndpoint.Host.ipv4(IPv4Address("1.2.3.4")!)))")
    print("ipv6Constructor\t\(endpointHostDescribe(NWEndpoint.Host.ipv6(IPv6Address("::1")!)))")
    let hostPairs = [("1.2.3.4", "1.2.3.4"), ("example.com", "example.com"), ("example.com", "EXAMPLE.COM"),
                     ("1.2.3.4", "0x1.2.3.4"), ("1.2.3.4%en0", "1.2.3.4"), ("::1", "0:0:0:0:0:0:0:1")]
    for (left, right) in hostPairs {
        let a = NWEndpoint.Host(left), b = NWEndpoint.Host(right)
        print("hostEqual\t\(left) \(right)\t\(a == b)\thash=\(a.hashValue == b.hashValue)")
    }
    let portStrings = ["80", "0", "65535", "65536", "-1", "+1", "08", "0x50", "", " 80", "80 ", "http", "00080", "99999999999999999999",
                       "1_000", "\u{0663}", "65535 ", "0080"]
    for text in portStrings {
        let port = NWEndpoint.Port(text)
        print("port\t\(text.debugDescription)\t\(port.map { "\($0.rawValue) \($0.debugDescription)" } ?? "nil")")
    }
    for raw in [0, 1, 22, 65535] as [UInt16] {
        let port = NWEndpoint.Port(rawValue: raw)
        print("portRaw\t\(raw)\t\(port.map { "\($0.rawValue) \($0.debugDescription)" } ?? "nil")")
    }
    let named: [(String, NWEndpoint.Port)] = [("any", .any), ("ssh", .ssh), ("smtp", .smtp), ("http", .http), ("pop", .pop),
                                              ("imap", .imap), ("https", .https), ("imaps", .imaps), ("socks", .socks)]
    for (name, port) in named {
        print("named\t\(name)\t\(port.rawValue) \(port.debugDescription)")
    }
    let integer: NWEndpoint.Port = 443
    print("integerLiteral\t\(integer.rawValue)")
    let portPairs = [(80, 80), (80, 443)]
    for (left, right) in portPairs {
        let a = NWEndpoint.Port(rawValue: UInt16(left))!, b = NWEndpoint.Port(rawValue: UInt16(right))!
        print("portEqual\t\(left) \(right)\t\(a == b)\thash=\(a.hashValue == b.hashValue)")
    }
}

let endpointMoreHosts = ["::1.2.3.4", "::0.0.0.2", "::ffff:0:0", "::ffff:0.0.0.5%en0", "1.2.3.4%en0%en0", "example.com%en0%x",
                         "%bogus", "fe80::1%en0x", "example.com%%en0", "example..com", "-", ".", "a.", "1.2.3.4.", "ab..cd"]
let endpointMorePorts = ["\t80", "\n80", "\u{0B}80", "\r80", " \t 80", "-0", "+0", "+-1", "--1", "+ 1", "https", "imaps", "socks",
                         "domain", "ftp", "ssh", "smtp", "pop3", "unknownsvc", "1 ", "80a", "0x", "+", "-", "65535.0"]
func endpointMoreReport() {
    for text in endpointMoreHosts {
        print("host\t\(text.debugDescription)\t\(endpointHostDescribe(NWEndpoint.Host(text)))")
    }
    for text in endpointMorePorts {
        let port = NWEndpoint.Port(text)
        print("port\t\(text.debugDescription)\t\(port.map { "\($0.rawValue) \($0.debugDescription)" } ?? "nil")")
    }
}

let endpointLastHosts = ["example.com%14", "%14", "example.com%0", "example.com%999999", "example.com%01", "example.com%en0%14"]
let endpointLastPorts = [" http", "http ", "\thttp", "\u{0C}80", " +80", "+\t80", "00000000000000000000080", "HTTP", "Https", "ssh\n"]
func endpointLastReport() {
    for text in endpointLastHosts {
        print("host\t\(text.debugDescription)\t\(endpointHostDescribe(NWEndpoint.Host(text)))")
    }
    for text in endpointLastPorts {
        let port = NWEndpoint.Port(text)
        print("port\t\(text.debugDescription)\t\(port.map { "\($0.rawValue) \($0.debugDescription)" } ?? "nil")")
    }
}
