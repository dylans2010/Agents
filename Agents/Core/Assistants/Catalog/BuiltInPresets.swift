public enum BuiltInPresets {
    public static var groups: [[AssistantDefinition]] {
        [
            RepositoryIntelligencePresets.all,
        ]
    }

    public static var all: [AssistantDefinition] {
        groups.flatMap { $0 }
    }
}
