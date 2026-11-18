public enum BuiltInPresets {
    public static var groups: [[AssistantDefinition]] {
        []
    }

    public static var all: [AssistantDefinition] {
        groups.flatMap { $0 }
    }
}
