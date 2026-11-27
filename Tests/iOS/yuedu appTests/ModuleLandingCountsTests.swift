import Testing
@testable import yuedu_app

struct ModuleLandingCountsTests {
    @Test func retainsOfficialAndImportedDestinationSemantics() {
        let counts = ModuleLandingCounts(appOfficial: 3, installedOfficial: 7, installedImported: 2, unreadableImported: 1)
        #expect(counts.official == 10)
        #expect(counts.imported == 3)
        #expect(ModuleLandingCounts(appOfficial: 0, installedOfficial: 0, installedImported: 0, unreadableImported: 0) == ModuleLandingCounts(appOfficial: 0, installedOfficial: 0, installedImported: 0, unreadableImported: 0))
    }
}
