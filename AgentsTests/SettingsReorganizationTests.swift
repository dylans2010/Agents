import Foundation
import Testing
@testable import Agents

@Suite("Settings Reorganization")
struct SettingsReorganizationTests {

    @Test("Sidebar groups cover every settings tab exactly once")
    func groupsCoverAllTabsExactlyOnce() {
        let grouped = SettingsTab.groups.flatMap { $0.tabs }
        #expect(grouped.count == SettingsTab.allCases.count)
        #expect(Set(grouped) == Set(SettingsTab.allCases))
        #expect(SettingsTab.groups.count == 3)
    }

    @Test("Every settings tab has a unique title and a symbol")
    func everyTabHasTitleAndSymbol() {
        for tab in SettingsTab.allCases {
            #expect(!tab.title.isEmpty)
            #expect(!tab.symbolName.isEmpty)
        }
        #expect(Set(SettingsTab.allCases.map { $0.title }).count == SettingsTab.allCases.count)
    }

    @Test("Settings search matches tabs by keyword")
    func searchMatchesByKeyword() {
        #expect(SettingsTab.antigravity.matches(query: "gemini"))
        #expect(SettingsTab.providers.matches(query: "registry"))
        #expect(SettingsTab.assistants.matches(query: "notifications"))
        #expect(SettingsTab.voice.matches(query: "microphone"))
        #expect(SettingsTab.remote.matches(query: "pair"))
        #expect(SettingsTab.memory.matches(query: "clear"))
        #expect(SettingsTab.computerUse.matches(query: "accessibility"))
        #expect(SettingsTab.models.matches(query: "custom model"))
        #expect(SettingsTab.general.matches(query: "APPEARANCE"))
        #expect(SettingsTab.providers.matches(query: "api key"))
        #expect(!SettingsTab.models.matches(query: "gemini"))
        #expect(!SettingsTab.about.matches(query: "tokens"))
        #expect(!SettingsTab.usage.matches(query: "zzznope"))
    }

    @Test("Empty search matches every tab")
    func emptySearchMatchesAll() {
        for tab in SettingsTab.allCases {
            #expect(tab.matches(query: ""))
            #expect(tab.matches(query: "   "))
        }
    }

    @Test("Key variable resolution prefers a fixed variable")
    func keyVariableResolutionPrefersFixed() {
        let provider = DesktopProviderInfo(
            id: "antigravity",
            displayName: "Google Antigravity",
            keyChoices: [ProviderKeyChoice(envName: "OTHER_KEY", label: "Other")]
        )
        #expect(
            ProviderKeyAccountsSection.resolvedKeyVariable(
                fixed: "GEMINI_API_KEY",
                provider: provider,
                selectedChoice: ""
            ) == "GEMINI_API_KEY"
        )
    }

    @Test("Key variable resolution falls back through provider choices")
    func keyVariableResolutionFallbacks() {
        let withChoice = DesktopProviderInfo(
            id: "claude",
            displayName: "Claude",
            keyChoices: [ProviderKeyChoice(envName: "ANTHROPIC_API_KEY", label: "Anthropic")]
        )
        #expect(
            ProviderKeyAccountsSection.resolvedKeyVariable(fixed: nil, provider: withChoice, selectedChoice: "")
                == "ANTHROPIC_API_KEY"
        )
        #expect(
            ProviderKeyAccountsSection.resolvedKeyVariable(fixed: nil, provider: withChoice, selectedChoice: "CUSTOM_KEY")
                == "CUSTOM_KEY"
        )
        let inferred = DesktopProviderInfo(id: "codex", displayName: "Codex")
        #expect(
            ProviderKeyAccountsSection.resolvedKeyVariable(fixed: nil, provider: inferred, selectedChoice: "")
                == "OPENAI_API_KEY"
        )
        let unknown = DesktopProviderInfo(id: "something-new", displayName: "Something New")
        #expect(
            ProviderKeyAccountsSection.resolvedKeyVariable(fixed: nil, provider: unknown, selectedChoice: "")
                == "API_KEY"
        )
    }
}
