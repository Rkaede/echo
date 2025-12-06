import Foundation
import AppKit

@MainActor
class AudioStorageManager: ObservableObject {
    static let shared = AudioStorageManager()
    
    private let defaultStorageDirectoryName = "recordings"
    
    private init() {}
    
    // MARK: - Storage Directory Management
    
    /// Returns the default audio storage directory URL
    var defaultStorageDirectory: URL {
        let appSupportPath = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let echoDirectory = appSupportPath.appendingPathComponent("Echo")
        return echoDirectory.appendingPathComponent(defaultStorageDirectoryName)
    }
    
    /// Returns the currently configured storage directory
    /// - Note: For security-scoped bookmark URLs, caller must manage access with withSecurityScopedStorageAccess()
    func getCurrentStorageDirectory() -> URL {
        let settingsManager = SettingsManager.shared

        // Try to resolve security-scoped bookmark first (does not start accessing)
        if let bookmarkURL = settingsManager.resolveAudioStorageDirectory() {
            return bookmarkURL
        }

        // Fallback to path-based access (for existing installations or non-sandboxed)
        if !settingsManager.audioStoragePath.isEmpty {
            let customURL = URL(fileURLWithPath: settingsManager.audioStoragePath)
            if FileManager.default.fileExists(atPath: customURL.path) {
                return customURL
            }
        }

        return defaultStorageDirectory
    }

    /// Executes an operation with proper security-scoped access to the storage directory
    /// - Parameter operation: The closure to execute with the storage directory URL
    /// - Returns: The result of the operation
    /// - Note: Automatically handles security-scoped resource access when using bookmark-based custom directory
    private func withSecurityScopedStorageAccess<T>(_ operation: (URL) throws -> T) rethrows -> T {
        let settingsManager = SettingsManager.shared

        // If we have a security-scoped bookmark, use it with proper access management
        if !settingsManager.audioStorageBookmark.isEmpty {
            if let result = try settingsManager.withSecurityScopedAccess(operation) {
                return result
            }
            // If bookmark access failed, fall through to default directory
        }

        // Otherwise, use the current directory (default or path-based) directly
        let directory = getCurrentStorageDirectory()
        return try operation(directory)
    }
    
    /// Creates the storage directory if it doesn't exist
    private func ensureStorageDirectoryExists() throws {
        try withSecurityScopedStorageAccess { storageDirectory in
            if !FileManager.default.fileExists(atPath: storageDirectory.path) {
                try FileManager.default.createDirectory(
                    at: storageDirectory,
                    withIntermediateDirectories: true,
                    attributes: [.posixPermissions: 0o755]
                )
                print("AudioStorageManager: Created storage directory at \(storageDirectory.path)")
            }
        }
    }
    
    // MARK: - Audio File Operations
    
    /// Saves an audio file from temporary location to permanent storage
    /// - Parameters:
    ///   - tempURL: The temporary audio file URL
    ///   - transcriptionId: The UUID of the transcription for naming
    /// - Returns: The permanent file path (relative to storage directory) or nil if failed
    func saveAudioFile(from tempURL: URL, transcriptionId: UUID) -> String? {
        do {
            try ensureStorageDirectoryExists()

            return try withSecurityScopedStorageAccess { storageDirectory in
                let timestamp = Date().timeIntervalSince1970
                let filename = "\(transcriptionId.uuidString)_\(Int(timestamp)).wav"
                let permanentURL = storageDirectory.appendingPathComponent(filename)

                // Copy file from temp to permanent location
                try FileManager.default.copyItem(at: tempURL, to: permanentURL)

                print("AudioStorageManager: Saved audio file to \(permanentURL.path)")
                return filename // Return relative path for storage in database
            }

        } catch {
            print("AudioStorageManager: Failed to save audio file: \(error)")
            return nil
        }
    }
    
    /// Retrieves the full URL for an audio file given its relative path
    /// - Parameter relativePath: The relative path stored in the database
    /// - Returns: The full URL to the audio file, or nil if file doesn't exist
    func getAudioFileURL(for relativePath: String) -> URL? {
        guard !relativePath.isEmpty else { return nil }

        return withSecurityScopedStorageAccess { storageDirectory in
            let fullURL = storageDirectory.appendingPathComponent(relativePath)

            guard FileManager.default.fileExists(atPath: fullURL.path) else {
                print("AudioStorageManager: Audio file not found at \(fullURL.path)")
                return nil as URL?
            }

            return fullURL
        }
    }
    
    /// Deletes an audio file
    /// - Parameter relativePath: The relative path of the audio file to delete
    func deleteAudioFile(at relativePath: String) {
        guard !relativePath.isEmpty else { return }

        do {
            try withSecurityScopedStorageAccess { storageDirectory in
                let fileURL = storageDirectory.appendingPathComponent(relativePath)

                if FileManager.default.fileExists(atPath: fileURL.path) {
                    try FileManager.default.removeItem(at: fileURL)
                    print("AudioStorageManager: Deleted audio file at \(fileURL.path)")
                }
            }
        } catch {
            print("AudioStorageManager: Failed to delete audio file: \(error)")
        }
    }
    
    // MARK: - Storage Information
    
    /// Calculates the total storage space used by audio files
    /// - Returns: Total size in bytes
    func calculateStorageUsage() -> Int64 {
        do {
            return try withSecurityScopedStorageAccess { storageDirectory in
                let contents = try FileManager.default.contentsOfDirectory(
                    at: storageDirectory,
                    includingPropertiesForKeys: [.fileSizeKey],
                    options: []
                )

                let audioFiles = contents.filter { $0.pathExtension.lowercased() == "wav" }

                var totalSize: Int64 = 0
                for fileURL in audioFiles {
                    let resourceValues = try fileURL.resourceValues(forKeys: [.fileSizeKey])
                    totalSize += Int64(resourceValues.fileSize ?? 0)
                }

                return totalSize
            }
        } catch {
            print("AudioStorageManager: Failed to calculate storage usage: \(error)")
            return 0
        }
    }
    
    /// Returns a formatted string of the storage usage
    var formattedStorageUsage: String {
        let bytes = calculateStorageUsage()
        
        if bytes == 0 {
            return "0 MB"
        }
        
        let mbBytes = Double(bytes) / (1024 * 1024)
        
        if mbBytes < 1 {
            return String(format: "%.1f KB", Double(bytes) / 1024)
        } else if mbBytes < 1024 {
            return String(format: "%.1f MB", mbBytes)
        } else {
            return String(format: "%.2f GB", mbBytes / 1024)
        }
    }
    
    /// Returns the number of audio files in storage
    func getAudioFileCount() -> Int {
        do {
            return try withSecurityScopedStorageAccess { storageDirectory in
                let contents = try FileManager.default.contentsOfDirectory(
                    at: storageDirectory,
                    includingPropertiesForKeys: nil,
                    options: []
                )

                return contents.filter { $0.pathExtension.lowercased() == "wav" }.count
            }
        } catch {
            print("AudioStorageManager: Failed to count audio files: \(error)")
            return 0
        }
    }
    
    // MARK: - Maintenance
    
    /// Removes audio files that don't have corresponding history entries
    /// - Parameter validPaths: Set of relative paths that should be kept
    func cleanupOrphanedAudioFiles(validPaths: Set<String>) {
        do {
            try withSecurityScopedStorageAccess { storageDirectory in
                let contents = try FileManager.default.contentsOfDirectory(
                    at: storageDirectory,
                    includingPropertiesForKeys: nil,
                    options: []
                )

                let audioFiles = contents.filter { $0.pathExtension.lowercased() == "wav" }
                var removedCount = 0

                for fileURL in audioFiles {
                    let filename = fileURL.lastPathComponent

                    if !validPaths.contains(filename) {
                        do {
                            try FileManager.default.removeItem(at: fileURL)
                            removedCount += 1
                            print("AudioStorageManager: Removed orphaned audio file: \(filename)")
                        } catch {
                            print("AudioStorageManager: Failed to remove orphaned file \(filename): \(error)")
                        }
                    }
                }

                if removedCount > 0 {
                    print("AudioStorageManager: Cleaned up \(removedCount) orphaned audio files")
                }
            }
        } catch {
            print("AudioStorageManager: Failed to cleanup orphaned files: \(error)")
        }
    }
    
    /// Deletes all audio files in the storage directory
    func deleteAllAudioFiles() {
        do {
            try withSecurityScopedStorageAccess { storageDirectory in
                let contents = try FileManager.default.contentsOfDirectory(
                    at: storageDirectory,
                    includingPropertiesForKeys: nil,
                    options: []
                )

                let audioFiles = contents.filter { $0.pathExtension.lowercased() == "wav" }
                var deletedCount = 0

                for fileURL in audioFiles {
                    do {
                        try FileManager.default.removeItem(at: fileURL)
                        deletedCount += 1
                    } catch {
                        print("AudioStorageManager: Failed to delete \(fileURL.lastPathComponent): \(error)")
                    }
                }

                print("AudioStorageManager: Deleted \(deletedCount) audio files")
            }
        } catch {
            print("AudioStorageManager: Failed to delete all audio files: \(error)")
        }
    }
    
    // MARK: - Directory Operations
    
    /// Opens the audio storage directory in Finder
    func openStorageDirectory() {
        do {
            try ensureStorageDirectoryExists()

            _ = withSecurityScopedStorageAccess { storageDirectory in
                NSWorkspace.shared.open(storageDirectory)
            }
        } catch {
            print("AudioStorageManager: Failed to open storage directory: \(error)")
        }
    }
    
    /// Validates if a directory path is writable and returns an error if not
    /// - Parameter path: The directory path to validate
    /// - Returns: nil if valid, error message if invalid
    func validateStoragePath(_ path: String) -> String? {
        guard !path.isEmpty else {
            return nil // Empty path is valid (uses default)
        }
        
        let url = URL(fileURLWithPath: path)
        
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        
        if !exists {
            return "Directory does not exist"
        }
        
        if !isDirectory.boolValue {
            return "Path is not a directory"
        }
        
        if !FileManager.default.isWritableFile(atPath: url.path) {
            return "Directory is not writable"
        }
        
        return nil
    }
    
    /// Sets a custom storage directory with proper security-scoped bookmark persistence
    /// - Parameter url: The directory URL selected by the user
    /// - Returns: Validation error message if directory is invalid, nil if successful
    func setCustomStorageDirectory(_ url: URL) -> String? {
        // First validate the directory
        if let error = validateStoragePath(url.path) {
            return error
        }
        
        // Set the directory with security-scoped bookmark
        SettingsManager.shared.setAudioStorageDirectory(url)
        
        print("AudioStorageManager: Set custom storage directory to \(url.path)")
        return nil
    }
}