import Foundation
import Synchronization
import Testing
@testable import GitHubPlugin

struct GhLocatorTests {
    final class Probe: Sendable {
        let executables: Mutex<Set<String>>
        let checks = Mutex<[String]>([])
        let shellCalls = Mutex(0)
        let shellPath: String?

        init(executables: Set<String>, shellPath: String? = nil) {
            self.executables = Mutex(executables)
            self.shellPath = shellPath
        }

        func locator() -> GhLocator {
            GhLocator(
                isExecutable: { path in
                    self.checks.withLock { $0.append(path) }
                    return self.executables.withLock { $0.contains(path) }
                },
                shellLookup: {
                    self.shellCalls.withLock { $0 += 1 }
                    return self.shellPath
                }
            )
        }
    }

    @Test func prefersHomebrewOnAppleSilicon() async {
        let probe = Probe(executables: ["/opt/homebrew/bin/gh", "/usr/local/bin/gh"], shellPath: "/custom/gh")
        let gh = await probe.locator().locate()
        #expect(gh?.path == "/opt/homebrew/bin/gh")
        #expect(probe.checks.withLock { $0 } == ["/opt/homebrew/bin/gh"])
        #expect(probe.shellCalls.withLock { $0 } == 0)
    }

    @Test func fallsBackToUsrLocal() async {
        let probe = Probe(executables: ["/usr/local/bin/gh"], shellPath: "/custom/gh")
        let gh = await probe.locator().locate()
        #expect(gh?.path == "/usr/local/bin/gh")
        #expect(probe.checks.withLock { $0 } == ["/opt/homebrew/bin/gh", "/usr/local/bin/gh"])
        #expect(probe.shellCalls.withLock { $0 } == 0)
    }

    @Test func asksTheLoginShellOnceAndCachesTheResult() async {
        let probe = Probe(executables: ["/custom/gh"], shellPath: "/custom/gh")
        let locator = probe.locator()
        #expect(await locator.locate()?.path == "/custom/gh")
        #expect(await locator.locate()?.path == "/custom/gh")
        #expect(probe.shellCalls.withLock { $0 } == 1)
        #expect(probe.checks.withLock { $0 } == ["/opt/homebrew/bin/gh", "/usr/local/bin/gh", "/custom/gh", "/opt/homebrew/bin/gh", "/usr/local/bin/gh", "/custom/gh"])
    }

    @Test func cachesAMissingResultToo() async {
        let probe = Probe(executables: [])
        let locator = probe.locator()
        #expect(await locator.locate() == nil)
        #expect(await locator.locate() == nil)
        #expect(probe.shellCalls.withLock { $0 } == 1)
    }

    @Test func findsAnInstallInAFixedLocationAfterTheShellFoundNothing() async {
        let probe = Probe(executables: [])
        let locator = probe.locator()
        #expect(await locator.locate() == nil)
        probe.executables.withLock { $0 = ["/opt/homebrew/bin/gh"] }
        #expect(await locator.locate()?.path == "/opt/homebrew/bin/gh")
    }

    @Test func retriesTheShellAfterTheLookupFailed() async {
        struct LookupFailed: Error {}
        let attempts = Mutex(0)
        let locator = GhLocator(
            isExecutable: { $0 == "/custom/gh" },
            shellLookup: {
                let attempt = attempts.withLock { $0 += 1; return $0 }
                if attempt == 1 { throw LookupFailed() }
                return "/custom/gh"
            }
        )
        #expect(await locator.locate() == nil)
        #expect(await locator.locate()?.path == "/custom/gh")
        #expect(await locator.locate()?.path == "/custom/gh")
        #expect(attempts.withLock { $0 } == 2)
    }

    @Test func reportsACachedPathThatWasRemovedAsMissing() async {
        let probe = Probe(executables: ["/custom/gh"], shellPath: "/custom/gh")
        let locator = probe.locator()
        #expect(await locator.locate()?.path == "/custom/gh")
        probe.executables.withLock { $0 = [] }
        #expect(await locator.locate() == nil)
        #expect(probe.shellCalls.withLock { $0 } == 1)
    }
}
