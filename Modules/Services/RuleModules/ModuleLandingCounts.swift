/// Counts for the existing official and imported JSON module destinations.
struct ModuleLandingCounts: Equatable {
    let official: Int
    let imported: Int
    init(appOfficial: Int, installedOfficial: Int, installedImported: Int, unreadableImported: Int) {
        official = appOfficial + installedOfficial
        imported = installedImported + unreadableImported
    }
}
