import Testing
import IsletCore
import IsletHost

struct NotchDisplayPlacementTests {
    let builtIn = NotchDisplay(id: "1", name: "Built-in Retina Display", isBuiltIn: true, hasHardwareNotch: true, isPrimary: false)
    let external = NotchDisplay(id: "2", name: "Studio Display", isBuiltIn: false, hasHardwareNotch: false, isPrimary: true)
    let spare = NotchDisplay(id: "3", name: "LG UltraFine", isBuiltIn: false, hasHardwareNotch: false, isPrimary: false)
    let twin = NotchDisplay(id: "4", name: "LG UltraFine", isBuiltIn: false, hasHardwareNotch: false, isPrimary: false)

    @Test func builtInPrefersTheBuiltInDisplayThenPrimaryThenFirst() {
        #expect(NotchDisplayPlacement.builtIn.displays(among: [external, builtIn]) == [builtIn])
        #expect(NotchDisplayPlacement.builtIn.displays(among: [spare, external]) == [external])
        #expect(NotchDisplayPlacement.builtIn.displays(among: [spare]) == [spare])
        #expect(NotchDisplayPlacement.builtIn.displays(among: []).isEmpty)
    }

    @Test func builtInFindsABuiltInDisplayWithoutANotch() {
        let notchless = NotchDisplay(id: "5", name: "Color LCD", isBuiltIn: true, hasHardwareNotch: false, isPrimary: false)
        #expect(NotchDisplayPlacement.builtIn.displays(among: [external, notchless]) == [notchless])
    }

    @Test func primaryPicksThePrimaryDisplay() {
        #expect(NotchDisplayPlacement.primary.displays(among: [builtIn, external]) == [external])
        #expect(NotchDisplayPlacement.primary.displays(among: [builtIn, spare]) == [builtIn])
    }

    @Test func allUsesEveryDisplay() {
        #expect(NotchDisplayPlacement.all.displays(among: [builtIn, external, spare]) == [builtIn, external, spare])
    }

    @Test func chosenDisplayFallsBackWhileDisconnected() {
        let chosen = NotchDisplayPlacement.display(id: spare.id, name: spare.name)
        #expect(chosen.displays(among: [builtIn, external, spare]) == [spare])
        #expect(chosen.displays(among: [builtIn, external]) == [builtIn])
    }

    @Test func chosenDisplayIsFoundByIdentityNotName() {
        let chosen = NotchDisplayPlacement.display(id: twin.id, name: twin.name)
        #expect(chosen.displays(among: [builtIn, spare, twin]) == [twin])
        #expect(chosen.displays(among: [builtIn, spare]) == [builtIn])
    }
}
