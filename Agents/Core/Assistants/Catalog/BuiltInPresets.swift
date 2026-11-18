public enum BuiltInPresets {
    public static var groups: [[AssistantDefinition]] {
        [
            RepositoryIntelligencePresets.all,
            BuildingFixingPresets.all,
            CodeMaintenancePresets.all,
            CodeReviewSecurityPresets.all,
            GitWorkflowAutomationPresets.all,
            SpecializedProductivityPresets.all,
        ]
    }

    public static var all: [AssistantDefinition] {
        groups.flatMap { $0 }
    }
}
