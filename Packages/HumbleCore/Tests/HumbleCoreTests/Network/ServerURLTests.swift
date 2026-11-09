import Testing
@testable import HumbleCore

struct ServerURLTests {
    private func ok(_ input: String, local: Bool = false) -> String? {
        if case .ok(let url, _) = ServerURL.normalize(input, allowCleartextLocalHosts: local) { url } else { nil }
    }

    @Test func canonicalForm() {
        #expect(ok("planning.example.com") == "https://planning.example.com")
        #expect(ok("  https://Planning.Example.com/  ") == "https://planning.example.com")
        #expect(ok("https://planning.example.com/app/") == "https://planning.example.com/app")
        #expect(ok("https://planning.example.com/app?x=1#y") == "https://planning.example.com/app")
    }

    @Test func ports() {
        #expect(ok("https://planning.example.com:8443") == "https://planning.example.com:8443")
        #expect(ok("https://planning.example.com:443") == "https://planning.example.com")
    }

    @Test func empty() {
        for input in ["", "   ", "https://", "HTTPS://"] {
            #expect(ServerURL.normalize(input, allowCleartextLocalHosts: false) == .empty)
        }
    }

    @Test func releaseRefusesClearText() {
        for input in ["http://planning.example.com", "http://192.168.0.10:3000", "http://localhost:3000", "ftp://planning.example.com"] {
            #expect(ServerURL.normalize(input, allowCleartextLocalHosts: false) == .httpsRequired)
        }
    }

    @Test func debugAllowsLocalHostsOnly() {
        #expect(ok("http://localhost:3000", local: true) == "http://localhost:3000")
        #expect(ok("http://127.0.0.1:3100", local: true) == "http://127.0.0.1:3100")
        #expect(ok("http://192.168.0.10:3000", local: true) == "http://192.168.0.10:3000")
        #expect(ok("http://mac.local:3000", local: true) == "http://mac.local:3000")
        for input in ["http://planning.example.com", "http://192.168.0.10.evil.example", "http://8.8.8.8", "http://172.32.0.1"] {
            #expect(ServerURL.normalize(input, allowCleartextLocalHosts: true) == .httpsRequired)
        }
    }

    @Test func invalid() {
        for input in ["https://user:pass@planning.example.com", "https://:pass@planning.example.com",
                      "https://planning.example.com\\@evil.example", "https://planning.example.com\nhost"] {
            #expect(ServerURL.normalize(input, allowCleartextLocalHosts: false) == .invalid)
        }
    }

    @Test func hostShownIsTheOneContacted() {
        #expect(ServerURL.normalize("https://planning.example.com.evil.example/planning.example.com", allowCleartextLocalHosts: false)
            == .ok(url: "https://planning.example.com.evil.example/planning.example.com", host: "planning.example.com.evil.example"))
        #expect(ServerURL.hostOf("https://planning.example.com:8443/app") == "planning.example.com:8443")
        #expect(ServerURL.hostOf("http://evil") == nil)
    }

    @Test func ipv6KeepsItsBrackets() {
        #expect(ok("https://[::1]:8443") == "https://[::1]:8443")
    }
}

struct QRLoginTests {
    private let code = String(repeating: "a", count: 64)

    @Test func readsTheLink() {
        let login = QRLogin(link: "humbleplanning://login?url=https%3A%2F%2Fplanning.example.com&code=\(code)")
        #expect(login == QRLogin(link: "  humbleplanning://login?url=https://planning.example.com&code=\(code)\n"))
        #expect(login?.serverURL == "https://planning.example.com")
        #expect(login?.code == code)
        #expect(QRLogin(link: "humbleplanning://login?url=x&code=\(code.uppercased())") != nil)
    }

    @Test func refusesOtherLinks() {
        for link in ["https://login?url=x&code=\(code)", "otherapp://login?url=x&code=\(code)", "javascript:alert(1)",
                     "humbleplanning://logout?url=x&code=\(code)", "humbleplanning://loginx?url=x&code=\(code)",
                     "humbleplanning://login?url=x&code=\(code.dropLast())", "humbleplanning://login?url=x&code=\(code)a",
                     "humbleplanning://login?url=x&code=\(String(repeating: "g", count: 64))",
                     "humbleplanning://login?url=x", "humbleplanning://login?code=\(code)"] {
            #expect(QRLogin(link: link) == nil, "\(link)")
        }
    }
}

struct VersionTests {
    @Test func older() {
        #expect(AppInfo.isOlder("1.0.0", than: "9.0.0"))
        #expect(AppInfo.isOlder("1.9.0", than: "1.10.0"))
        #expect(AppInfo.isOlder("1.0", than: "1.0.1"))
        #expect(AppInfo.isOlder("1.0.0-beta", than: "1.0.1"))
    }

    @Test func notOlder() {
        #expect(!AppInfo.isOlder("1.0.0", than: "1.0.0"))
        #expect(!AppInfo.isOlder("1.0.0", than: "1.0"))
        #expect(!AppInfo.isOlder("2.0.0", than: "1.9.9"))
        #expect(!AppInfo.isOlder("1.0.0", than: nil))
        #expect(!AppInfo.isOlder("1.0.0", than: " "))
    }
}
