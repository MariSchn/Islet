import Foundation
import Testing
@testable import CalendarPlugin

struct MeetingLinkTests {
    @Test func findsZoomLinks() {
        #expect(meetingLink(url: nil, location: "https://us02web.zoom.us/j/123456789?pwd=abc", notes: nil)?.absoluteString == "https://us02web.zoom.us/j/123456789?pwd=abc")
        #expect(meetingLink(url: nil, location: "https://zoom.us/my/someone", notes: nil)?.absoluteString == "https://zoom.us/my/someone")
        #expect(meetingLink(url: nil, location: "https://zoom.us/signin", notes: nil) == nil)
    }

    @Test func findsGoogleMeetLinks() {
        #expect(meetingLink(url: nil, location: nil, notes: "https://meet.google.com/abc-defg-hij")?.absoluteString == "https://meet.google.com/abc-defg-hij")
        #expect(meetingLink(url: nil, location: nil, notes: "https://meet.google.com/abc-defg-hij?authuser=0")?.absoluteString == "https://meet.google.com/abc-defg-hij")
        #expect(meetingLink(url: nil, location: nil, notes: "https://meet.google.com/landing") == nil)
    }

    @Test func findsMicrosoftTeamsLinks() {
        let work = "https://teams.microsoft.com/l/meetup-join/19%3ameeting_abc%40thread.v2/0?context=%7b%22Tid%22%3a%22x%22%7d"
        #expect(meetingLink(url: nil, location: nil, notes: work)?.absoluteString == work)
        #expect(meetingLink(url: nil, location: nil, notes: "https://teams.live.com/meet/9876543210")?.absoluteString == "https://teams.live.com/meet/9876543210")
    }

    @Test func findsWebexLinks() {
        #expect(meetingLink(url: nil, location: "https://acme.webex.com/meet/jane", notes: nil)?.absoluteString == "https://acme.webex.com/meet/jane")
    }

    @Test func isCaseInsensitive() {
        #expect(meetingLink(url: nil, location: "HTTPS://Zoom.US/j/42", notes: nil)?.absoluteString == "HTTPS://Zoom.US/j/42")
    }

    @Test func findsALinkInsideNotes() {
        let notes = """
        Agenda: roadmap review.
        Join Zoom Meeting https://acme.zoom.us/j/555 from your browser
        Meeting ID: 555
        """
        #expect(meetingLink(url: nil, location: "Room 4", notes: notes)?.absoluteString == "https://acme.zoom.us/j/555")
    }

    @Test func removesTrailingPunctuation() {
        #expect(meetingLink(url: nil, location: nil, notes: "Join here: https://zoom.us/j/123.")?.absoluteString == "https://zoom.us/j/123")
        #expect(meetingLink(url: nil, location: nil, notes: "(https://zoom.us/j/123),")?.absoluteString == "https://zoom.us/j/123")
        #expect(meetingLink(url: nil, location: nil, notes: "<https://acme.webex.com/meet/jane>")?.absoluteString == "https://acme.webex.com/meet/jane")
    }

    @Test func keepsHTMLEscapedAmpersands() {
        let notes = #"<a href="https://teams.microsoft.com/l/meetup-join/19%3ameeting%40thread.v2/0?context=a&amp;tenant=b">Join</a>"#
        #expect(meetingLink(url: nil, location: nil, notes: notes)?.absoluteString == "https://teams.microsoft.com/l/meetup-join/19%3ameeting%40thread.v2/0?context=a&amp;tenant=b")
    }

    @Test func returnsNilWithoutALink() {
        #expect(meetingLink(url: nil, location: nil, notes: nil) == nil)
        #expect(meetingLink(url: URL(string: "https://example.com/agenda"), location: "Room 4", notes: "Bring snacks, see https://example.com") == nil)
    }

    @Test func searchesTheURLThenTheLocationThenTheNotes() {
        let url = URL(string: "https://meet.google.com/aaa-bbbb-ccc")
        #expect(meetingLink(url: url, location: "https://zoom.us/j/1", notes: "https://zoom.us/j/2")?.absoluteString == "https://meet.google.com/aaa-bbbb-ccc")
        #expect(meetingLink(url: URL(string: "https://example.com"), location: "https://zoom.us/j/1", notes: "https://zoom.us/j/2")?.absoluteString == "https://zoom.us/j/1")
        #expect(meetingLink(url: nil, location: "Room 4", notes: "https://zoom.us/j/2")?.absoluteString == "https://zoom.us/j/2")
    }
}
