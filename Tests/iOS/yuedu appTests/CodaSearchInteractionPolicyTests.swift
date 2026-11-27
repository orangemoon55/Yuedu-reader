import Testing
@testable import CodaCore

@Suite("Coda native search interaction source policy")
struct CodaSearchInteractionPolicyTests {
    @Test func onlyMatchingActiveProviderHasNativeActions() {
        for active in MusicProvider.allCases {
            for source in MusicProvider.allCases {
                #expect(CodaSearchInteractionPolicy.canUseNativePanel(
                    source: source, active: active, context: active,
                    fixture: false, switching: false) == (source == active))
            }
        }
    }
    @Test func transitionAndLocalFixturesAreAlwaysInert() {
        for provider in MusicProvider.allCases {
            #expect(!CodaSearchInteractionPolicy.canUseNativePanel(
                source: provider, active: provider, context: provider,
                fixture: true, switching: false))
            #expect(!CodaSearchInteractionPolicy.canUseNativePanel(
                source: provider, active: provider, context: provider,
                fixture: false, switching: true))
            let foreign = MusicProvider.allCases.first { $0 != provider }!
            #expect(!CodaSearchInteractionPolicy.canUseNativePanel(
                source: provider, active: provider, context: foreign,
                fixture: false, switching: false))
        }
    }
}
