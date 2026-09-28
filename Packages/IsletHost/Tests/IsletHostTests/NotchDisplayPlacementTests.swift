import Testing
import IsletCore
import IsletHost

struct NotchDisplayPlacementTests {
    let builtIn = NotchDisplay(id: "1", name: "Built-in Retina Display", hasHardwareNotch: true, isPrimary: false)
    let external = NotchDisplay(id: "2", name: "Studio Display", hasHardwareNotch: false, isPrimary: true)
    let spare = NotchDisplay(id: "3", name: "LG UltraFine", hasHardwareNotch: false, isPrimary: false)

    @Test func builtInPrefersTheNotchDisplayThenPrimaryThenFirst() {
        #expect(NotchDisplayPlacement.builtIn.displays(among: [external, builtIn]) == [builtIn])
        #expect(NotchDisplayPlacement.builtIn.displays(among: [spare, external]) == [external])
        #expect(NotchDisplayPlacement.builtIn.displays(among: [spare]) == [spare])
        #expect(NotchDisplayPlacement.builtIn.displays(among: []).isEmpty)
    }

    @Test func primaryPicksThePrimaryDisplay() {
        #expect(NotchDisplayPlacement.primary.displays(among: [builtIn, external]) == [external])
        #expect(NotchDisplayPlacement.primary.displays(among: [builtIn, spare]) == [builtIn])
    }

    @Test func allUsesEveryDisplay() {
        #expect(NotchDisplayPlacement.all.displays(among: [builtIn, external, spare]) == [builtIn, external, spare])
    }

    @Test func namedDisplayFallsBackWhileDisconnected() {
        #expect(NotchDisplayPlacement.named("LG UltraFine").displays(among: [builtIn, external, spare]) == [spare])
        #expect(NotchDisplayPlacement.named("LG UltraFine").displays(among: [builtIn, external]) == [builtIn])
    }
}
