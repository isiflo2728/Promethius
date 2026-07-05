import Foundation
import SwiftData

/// Metadata about an on-device model file (e.g. a `.gguf` Llama weight or a
/// Whisper model). The weights themselves live in the Mac app's Resources and
/// are NOT synced — only this lightweight descriptor is, so the iPhone can
/// show which models the Mac has available.
@Model
public final class LocalModel {
    public var id: UUID = UUID()
    public var displayName: String = ""
    /// Filename on the Mac, e.g. "llama-3-8b-instruct.Q4_K_M.gguf".
    public var fileName: String = ""
    public var kindRaw: String = ModelKind.llm.rawValue
    public var sizeBytes: Int64 = 0
    public var isDownloaded: Bool = false

    public var kind: ModelKind {
        get { ModelKind(rawValue: kindRaw) ?? .llm }
        set { kindRaw = newValue.rawValue }
    }

    public init(displayName: String, fileName: String, kind: ModelKind, sizeBytes: Int64 = 0, isDownloaded: Bool = false) {
        self.id = UUID()
        self.displayName = displayName
        self.fileName = fileName
        self.kindRaw = kind.rawValue
        self.sizeBytes = sizeBytes
        self.isDownloaded = isDownloaded
    }
}

public enum ModelKind: String, Codable, CaseIterable, Sendable {
    case llm
    case transcription
    case embedding
}
