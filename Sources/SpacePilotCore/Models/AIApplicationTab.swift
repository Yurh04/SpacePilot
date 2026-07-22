public enum AIApplicationTab: String, CaseIterable, Identifiable, Sendable {
    case overview
    case dataStorage
    case plugins
    case skills

    public var id: Self { self }

}
