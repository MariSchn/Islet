import Foundation

private let meetingLinkExpression = try! NSRegularExpression(
    pattern: [
        #"https://([a-z0-9-]+\.)?zoom\.us/(j|my|w)/[^\s<>"]+"#,
        #"https://meet\.google\.com/[a-z]{3}-[a-z]{4}-[a-z]{3}"#,
        #"https://teams\.microsoft\.com/l/meetup-join/[^\s<>"]+"#,
        #"https://teams\.live\.com/meet/[^\s<>"]+"#,
        #"https://([a-z0-9-]+\.)?webex\.com/(meet/|join/|wbxmjs/|[a-z0-9-]+/j\.php)[^\s<>"]*"#,
    ].joined(separator: "|"),
    options: .caseInsensitive
)

private let trailingMeetingLinkCharacters: Set<Character> = [".", ",", ")", ">"]

func meetingLink(url: URL?, location: String?, notes: String?) -> URL? {
    for text in [url?.absoluteString, location, notes].compactMap(\.self) {
        let range = NSRange(text.startIndex..., in: text)
        guard let match = meetingLinkExpression.firstMatch(in: text, range: range), let matchRange = Range(match.range, in: text) else { continue }
        var link = Substring(text[matchRange])
        while let last = link.last, trailingMeetingLinkCharacters.contains(last) {
            link.removeLast()
        }
        if let found = URL(string: String(link)) {
            return found
        }
    }
    return nil
}
