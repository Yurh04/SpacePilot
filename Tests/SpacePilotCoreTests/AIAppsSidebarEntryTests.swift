import XCTest
@testable import SpacePilotCore

final class AIAppsSidebarEntryTests: XCTestCase {
    private func deep(
        _ name: String,
        id: UUID = UUID(),
        url: URL? = nil
    ) -> AIAppsSidebar.DeepApplication {
        AIAppsSidebar.DeepApplication(
            id: id,
            displayName: name,
            subtitle: "Deep",
            revealURL: url
        )
    }

    private func registry(
        _ id: String,
        name: String,
        url: URL? = nil
    ) -> AIApplicationJoin.RegistryOnlyApplication {
        AIApplicationJoin.RegistryOnlyApplication(
            id: id,
            displayName: name,
            bundleIdentifier: nil,
            applicationURL: url,
            detectedVersion: nil,
            coverageFailures: []
        )
    }

    func testEntriesPlaceDeepFirstThenRegistryPreservingOrder() {
        let d1 = deep("Claude")
        let d2 = deep("Cursor")
        let r1 = registry("r:1", name: "Ollama")
        let r2 = registry("r:2", name: "Windsurf")

        let entries = AIAppsSidebar.entries(
            deepApplications: [d1, d2],
            registryOnlyApplications: [r1, r2]
        )

        XCTAssertEqual(entries.map(\.displayName), ["Claude", "Cursor", "Ollama", "Windsurf"])
        XCTAssertEqual(entries.map(\.isDiscovered), [false, false, true, true])
    }

    func testEntryKindAndStableIDsAreDistinctPerKind() {
        let uuid = UUID()
        let entries = AIAppsSidebar.entries(
            deepApplications: [deep("Claude", id: uuid)],
            registryOnlyApplications: [registry("r:1", name: "Ollama")]
        )

        XCTAssertEqual(entries[0].id, "deep:\(uuid.uuidString)")
        XCTAssertEqual(entries[0].kind, .deep(deepID: uuid))
        XCTAssertEqual(entries[1].id, "registry:r:1")
        XCTAssertEqual(entries[1].kind, .registry(registryID: "r:1"))
    }

    func testRevealURLMapsForBothDeepAndRegistryRows() {
        let deepURL = URL(fileURLWithPath: "/Applications/Claude.app")
        let registryURL = URL(fileURLWithPath: "/Applications/Ollama.app")
        let entries = AIAppsSidebar.entries(
            deepApplications: [deep("Claude", url: deepURL)],
            registryOnlyApplications: [registry("r:1", name: "Ollama", url: registryURL)]
        )

        // Simulate NSTableView.clickedRow for the first, middle-adjacent and last rows.
        XCTAssertEqual(entries[0].revealURL, deepURL)
        XCTAssertEqual(entries[1].revealURL, registryURL)
    }

    func testRegistryRowWithoutURLYieldsNilRevealURL() {
        let entries = AIAppsSidebar.entries(
            deepApplications: [],
            registryOnlyApplications: [registry("r:1", name: "Ollama", url: nil)]
        )

        XCTAssertNil(entries[0].revealURL)
    }

    func testClickedRowMappingHitsFirstMiddleAndLastEntries() {
        let urls = (0..<5).map { URL(fileURLWithPath: "/Applications/App\($0).app") }
        let deeps = urls.prefix(3).enumerated().map { deep("Deep\($0.offset)", url: $0.element) }
        let registries = urls.suffix(2).enumerated().map {
            registry("r:\($0.offset)", name: "Reg\($0.offset)", url: $0.element)
        }

        let entries = AIAppsSidebar.entries(
            deepApplications: Array(deeps),
            registryOnlyApplications: Array(registries)
        )

        XCTAssertEqual(entries.count, 5)
        XCTAssertEqual(entries[0].revealURL, urls[0])   // first (deep)
        XCTAssertEqual(entries[2].revealURL, urls[2])   // last deep
        XCTAssertEqual(entries[3].revealURL, urls[3])   // first registry
        XCTAssertEqual(entries[4].revealURL, urls[4])   // last (registry)
    }

    // MARK: - resolvedSelection

    func testResolvedSelectionPreservesCurrentValidSelection() {
        let d1 = deep("Claude")
        let d2 = deep("Cursor")
        let entries = AIAppsSidebar.entries(
            deepApplications: [d1, d2],
            registryOnlyApplications: []
        )

        let resolved = AIAppsSidebar.resolvedSelection(
            entries: entries,
            currentSelectionID: entries[1].id,
            preferredDeepID: d1.id
        )

        // A currently-valid selection wins over the preferred deep restore.
        XCTAssertEqual(resolved, entries[1].id)
    }

    func testResolvedSelectionRestoresPreferredDeepWhenCurrentInvalid() {
        let d1 = deep("Claude")
        let d2 = deep("Cursor")
        let entries = AIAppsSidebar.entries(
            deepApplications: [d1, d2],
            registryOnlyApplications: []
        )

        let resolved = AIAppsSidebar.resolvedSelection(
            entries: entries,
            currentSelectionID: "deep:\(UUID().uuidString)",
            preferredDeepID: d2.id
        )

        XCTAssertEqual(resolved, "deep:\(d2.id.uuidString)")
    }

    func testResolvedSelectionFallsBackToFirstWhenBothInvalid() {
        let d1 = deep("Claude")
        let r1 = registry("r:1", name: "Ollama")
        let entries = AIAppsSidebar.entries(
            deepApplications: [d1],
            registryOnlyApplications: [r1]
        )

        let resolved = AIAppsSidebar.resolvedSelection(
            entries: entries,
            currentSelectionID: nil,
            preferredDeepID: UUID()
        )

        XCTAssertEqual(resolved, entries[0].id)
    }

    func testResolvedSelectionReturnsNilWhenEmpty() {
        let resolved = AIAppsSidebar.resolvedSelection(
            entries: [],
            currentSelectionID: "deep:anything",
            preferredDeepID: UUID()
        )

        XCTAssertNil(resolved)
    }
}
