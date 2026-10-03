import Foundation
import Testing
@testable import AgentsPlugin

struct TerminalTargetingTests {
    private let listing = """
    /dev/ttys001 100 1700 main
    /dev/ttys002 200 1900 work
    /dev/ttys003 300 1800 my session
    /dev/ttys004 400 1000 work
    bad line
     500 2100 control
    """

    @Test func parsesListClientsOutput() {
        let clients = TmuxClient.parse(listing)
        #expect(clients.count == 4)
        #expect(clients[2] == TmuxClient(tty: "/dev/ttys003", pid: 300, activity: 1800, session: "my session"))
    }

    @Test func prefersAClientAttachedToTheSessionThenLatestActivity() {
        let clients = TmuxClient.parse(listing)
        #expect(TmuxClient.choose(from: clients, session: "work")?.tty == "/dev/ttys002")
        #expect(TmuxClient.choose(from: clients, session: "my session")?.tty == "/dev/ttys003")
        #expect(TmuxClient.choose(from: clients, session: "detached")?.tty == "/dev/ttys002")
        #expect(TmuxClient.choose(from: clients, session: nil)?.tty == "/dev/ttys002")
        #expect(TmuxClient.choose(from: [], session: "work") == nil)
    }

    @Test func pickWezTermPaneByTTY() {
        let json = Data("""
        [{"window_id":0,"tab_id":0,"pane_id":0,"tty_name":"/dev/ttys010"},{"window_id":0,"tab_id":1,"pane_id":7,"tty_name":"/dev/ttys011"}]
        """.utf8)
        #expect(WezTermPanes.paneID(in: json, tty: "/dev/ttys011") == 7)
        #expect(WezTermPanes.paneID(in: json, tty: "/dev/ttys099") == nil)
        #expect(WezTermPanes.paneID(in: Data("nope".utf8), tty: "/dev/ttys011") == nil)
    }

    @Test func wezTermTargetsPanes() {
        #expect(TerminalApp(identifier: "WezTerm")?.targeting == .wezTermPane)
    }

    @Test func processTreeFindsParents() {
        let me = ProcessInfo.processInfo.processIdentifier
        #expect(ProcessTree.parent(of: me) == getppid())
        #expect(ProcessTree.executablePath(of: me) != nil)
    }
}
