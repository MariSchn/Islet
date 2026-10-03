import Testing
@testable import DownloadsPlugin

struct DownloadNameTests {
    @Test(arguments: [
        ("report.pdf.download", "report.pdf"),
        ("report.pdf.crdownload", "report.pdf"),
        ("report.pdf.part", "report.pdf"),
        ("Archive.tar.gz.CRDOWNLOAD", "Archive.tar.gz"),
        ("Unconfirmed 123456.crdownload", "Unconfirmed 123456"),
    ])
    func stripsTheUnfinishedExtension(fileName: String, finalName: String) {
        #expect(DownloadName.finalName(forUnfinished: fileName) == finalName)
    }

    @Test(arguments: ["report.pdf", "notes.txt", "partial", ".part", "download"])
    func ignoresFinishedFiles(fileName: String) {
        #expect(DownloadName.finalName(forUnfinished: fileName) == nil)
    }
}
