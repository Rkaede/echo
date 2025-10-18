import Foundation

/// Manager for transcription history operations
/// Uses the centralized HistoryRepository for all database operations
@MainActor
class HistoryManager: ObservableObject {
  static let shared = HistoryManager()

  @Published var recentTranscriptions: [TranscriptionHistory] = []
  @Published var allTranscriptions: [TranscriptionHistory] = []
  @Published var totalCount: Int = 0
  @Published var searchError: String? = nil

  private let repository = HistoryRepository.shared

  private init() {
    Task {
      await loadInitialData()
    }
  }

  private func loadInitialData() async {
    let all = await repository.getAllTranscriptions()
    let recent = Array(all.prefix(10))
    let count = await repository.getTotalCount()

    self.allTranscriptions = all
    self.recentTranscriptions = recent
    self.totalCount = count
  }

  // Public method to force-refresh published state from the database
  func refresh() {
    print("HistoryManager: Refresh requested - reloading transcriptions and counts")
    self.loadAllTranscriptions()
    self.loadRecentTranscriptions()
    self.updateTotalCount()
  }

  private func loadAllTranscriptions() {
    Task {
      let all = await repository.getAllTranscriptions()
      self.allTranscriptions = all
    }
  }

  private func loadRecentTranscriptions() {
    Task {
      let all = await repository.getAllTranscriptions(limit: 10)
      self.recentTranscriptions = all
    }
  }

  private func updateTotalCount() {
    Task {
      let count = await repository.getTotalCount()
      self.totalCount = count
    }
  }

  func saveTranscription(_ transcription: TranscriptionHistory) {
    Task {
      let success = await repository.saveTranscription(transcription)
      if success {
        await refreshData()
      }
    }
  }

  func searchWithSnippets(query: String, limit: Int = 100) async -> [(TranscriptionHistory, String)]
  {
    let result = await repository.searchWithSnippets(query: query, limit: limit)

    switch result {
    case .success:
      self.searchError = nil
    case .failure(let error):
      self.searchError = error.errorDescription
    }

    switch result {
    case .success(let results):
      return results
    case .failure:
      return []
    }
  }

  func deleteTranscription(id: UUID) {
    Task {
      // First get the transcription to check for audio file
      let transcription = allTranscriptions.first { $0.id == id }

      let success = await repository.deleteTranscription(id: id)
      if success {
        // Delete associated audio file if it exists
        if let audioRef = transcription?.audioFileReference, !audioRef.isEmpty {
          AudioStorageManager.shared.deleteAudioFile(at: audioRef)
        }

        await refreshData()
      }
    }
  }

  func deleteAllTranscriptions() {
    Task {
      let success = await repository.deleteAllTranscriptions()
      if success {
        // Delete all associated audio files
        AudioStorageManager.shared.deleteAllAudioFiles()

        self.allTranscriptions = []
        self.recentTranscriptions = []
        self.totalCount = 0
      }
    }
  }

  private func refreshData() async {
    let all = await repository.getAllTranscriptions()
    let recent = Array(all.prefix(10))
    let count = await repository.getTotalCount()

    self.allTranscriptions = all
    self.recentTranscriptions = recent
    self.totalCount = count
  }
}
