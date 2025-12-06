import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

enum HistoryError: Error, LocalizedError {
  case fts5NotAvailable(String)

  var errorDescription: String? {
    switch self {
    case .fts5NotAvailable(let message):
      return "FTS5 search failed: \(message)"
    }
  }
}

/// Repository for managing transcription history operations
/// Uses the centralized DatabaseService for all database access
@MainActor
class HistoryRepository {
  static let shared = HistoryRepository()

  private init() {}

  // MARK: - Public API

  func saveTranscription(_ transcription: TranscriptionHistory) async -> Bool {
    let insertSQL = """
          INSERT INTO transcription_history
          (id, timestamp, transcribed_text, duration, audio_file_reference, language_detected,
           model_used, word_count, application_context, upload_time, groq_processing_time,
           total_transcription_time, confidence, did_fail, error_message, error_category,
           pure_upload_time, download_time, total_network_time)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
      """

    var statement: OpaquePointer?
    var success = false

    guard let conn = await DatabaseService.shared.connection(),
      let db = conn.opaquePointer
    else {
      print("HistoryRepository: Failed to get database connection")
      return false
    }

    if sqlite3_prepare_v2(db, insertSQL, -1, &statement, nil) == SQLITE_OK {
      sqlite3_bind_text(
        statement, 1, (transcription.id.uuidString as NSString).utf8String, -1, SQLITE_TRANSIENT)
      sqlite3_bind_double(statement, 2, transcription.timestamp.timeIntervalSince1970)
      sqlite3_bind_text(
        statement, 3, (transcription.transcribedText as NSString).utf8String, -1, SQLITE_TRANSIENT)
      sqlite3_bind_double(statement, 4, transcription.duration)

      if let audioRef = transcription.audioFileReference {
        sqlite3_bind_text(statement, 5, (audioRef as NSString).utf8String, -1, SQLITE_TRANSIENT)
      } else {
        sqlite3_bind_null(statement, 5)
      }

      if let language = transcription.languageDetected {
        sqlite3_bind_text(statement, 6, (language as NSString).utf8String, -1, SQLITE_TRANSIENT)
      } else {
        sqlite3_bind_null(statement, 6)
      }

      sqlite3_bind_text(
        statement, 7, (transcription.modelUsed as NSString).utf8String, -1, SQLITE_TRANSIENT)
      sqlite3_bind_int(statement, 8, Int32(transcription.wordCount))

      if let appContext = transcription.applicationContext {
        sqlite3_bind_text(statement, 9, (appContext as NSString).utf8String, -1, SQLITE_TRANSIENT)
      } else {
        sqlite3_bind_null(statement, 9)
      }

      sqlite3_bind_double(statement, 10, transcription.uploadTime)
      sqlite3_bind_double(statement, 11, transcription.groqProcessingTime)
      sqlite3_bind_double(statement, 12, transcription.totalTranscriptionTime)

      if let confidence = transcription.confidence {
        sqlite3_bind_double(statement, 13, confidence)
      } else {
        sqlite3_bind_null(statement, 13)
      }

      sqlite3_bind_int(statement, 14, transcription.didFail ? 1 : 0)

      if let errorMessage = transcription.errorMessage {
        sqlite3_bind_text(
          statement, 15, (errorMessage as NSString).utf8String, -1, SQLITE_TRANSIENT)
      } else {
        sqlite3_bind_null(statement, 15)
      }

      if let errorCategory = transcription.errorCategory {
        sqlite3_bind_text(
          statement, 16, (errorCategory as NSString).utf8String, -1, SQLITE_TRANSIENT)
      } else {
        sqlite3_bind_null(statement, 16)
      }

      sqlite3_bind_double(statement, 17, transcription.pureUploadTime)
      sqlite3_bind_double(statement, 18, transcription.downloadTime)
      sqlite3_bind_double(statement, 19, transcription.totalNetworkTime)

      if sqlite3_step(statement) == SQLITE_DONE {
        print("Transcription saved successfully")
        success = true
      } else {
        print("Could not save transcription")
      }
    }

    sqlite3_finalize(statement)
    return success
  }

  func searchWithSnippets(query: String, limit: Int = 100) async -> Result<
    [(TranscriptionHistory, String)], HistoryError
  > {
    var results: [(TranscriptionHistory, String)] = []

    guard let conn = await DatabaseService.shared.connection(),
      let db = conn.opaquePointer
    else {
      return .failure(.fts5NotAvailable("Database connection unavailable"))
    }

    // Process query to enable prefix matching
    let processedQuery = processQueryForPrefixMatching(query)

    let searchSQL = """
          SELECT th.*, snippet(transcription_fts, 0, '<b>', '</b>', '...', 32) as snippet
          FROM transcription_history th
          JOIN transcription_fts fts ON th.rowid = fts.rowid
          WHERE transcription_fts MATCH ?
          ORDER BY bm25(transcription_fts)
          LIMIT ?;
      """

    var statement: OpaquePointer?

    if sqlite3_prepare_v2(db, searchSQL, -1, &statement, nil) == SQLITE_OK {
      sqlite3_bind_text(statement, 1, (processedQuery as NSString).utf8String, -1, SQLITE_TRANSIENT)
      sqlite3_bind_int(statement, 2, Int32(limit))

      while sqlite3_step(statement) == SQLITE_ROW {
        if let transcription = parseTranscriptionFromRow(statement) {
          let snippet = String(cString: sqlite3_column_text(statement, 19))
          results.append((transcription, snippet))
        }
      }
      sqlite3_finalize(statement)
      return .success(results)
    } else {
      let errorMessage = String(cString: sqlite3_errmsg(db))
      sqlite3_finalize(statement)
      return .failure(.fts5NotAvailable(errorMessage))
    }
  }

  func getAllTranscriptions(limit: Int = 100, offset: Int = 0) async -> [TranscriptionHistory] {
    var transcriptions: [TranscriptionHistory] = []

    guard let conn = await DatabaseService.shared.connection(),
      let db = conn.opaquePointer
    else {
      print("HistoryRepository: Failed to get database connection")
      return []
    }

    let selectSQL = """
          SELECT * FROM transcription_history
          ORDER BY timestamp DESC
          LIMIT ? OFFSET ?;
      """

    var statement: OpaquePointer?

    if sqlite3_prepare_v2(db, selectSQL, -1, &statement, nil) == SQLITE_OK {
      sqlite3_bind_int(statement, 1, Int32(limit))
      sqlite3_bind_int(statement, 2, Int32(offset))

      while sqlite3_step(statement) == SQLITE_ROW {
        if let transcription = parseTranscriptionFromRow(statement) {
          transcriptions.append(transcription)
        }
      }
    } else {
      print(
        "HistoryRepository: Failed to prepare getAllTranscriptions query: \(String(cString: sqlite3_errmsg(db)))"
      )
    }

    sqlite3_finalize(statement)
    return transcriptions
  }

  func deleteTranscription(id: UUID) async -> Bool {
    guard let conn = await DatabaseService.shared.connection(),
      let db = conn.opaquePointer
    else {
      print("HistoryRepository: Failed to get database connection")
      return false
    }

    let deleteSQL = "DELETE FROM transcription_history WHERE id = ?;"
    var statement: OpaquePointer?
    var success = false

    if sqlite3_prepare_v2(db, deleteSQL, -1, &statement, nil) == SQLITE_OK {
      sqlite3_bind_text(statement, 1, (id.uuidString as NSString).utf8String, -1, SQLITE_TRANSIENT)

      if sqlite3_step(statement) == SQLITE_DONE {
        success = true
      }
    }

    sqlite3_finalize(statement)
    return success
  }

  func deleteAllTranscriptions() async -> Bool {
    guard let conn = await DatabaseService.shared.connection(),
      let db = conn.opaquePointer
    else {
      print("HistoryRepository: Failed to get database connection")
      return false
    }

    let deleteSQL = "DELETE FROM transcription_history;"
    return sqlite3_exec(db, deleteSQL, nil, nil, nil) == SQLITE_OK
  }

  func getTotalCount() async -> Int {
    guard let conn = await DatabaseService.shared.connection(),
      let db = conn.opaquePointer
    else {
      print("HistoryRepository: Failed to get database connection")
      return 0
    }

    let countSQL = "SELECT COUNT(*) FROM transcription_history;"
    var stmt: OpaquePointer?
    var count = 0

    if sqlite3_prepare_v2(db, countSQL, -1, &stmt, nil) == SQLITE_OK,
      sqlite3_step(stmt) == SQLITE_ROW
    {
      count = Int(sqlite3_column_int(stmt, 0))
    }
    sqlite3_finalize(stmt)
    return count
  }

  // MARK: - Private Helpers

  private func processQueryForPrefixMatching(_ query: String) -> String {
    let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)

    // Handle empty query
    guard !trimmedQuery.isEmpty else { return "" }

    // If the query is wrapped in quotes, preserve it as an exact phrase search
    if trimmedQuery.hasPrefix("\"") && trimmedQuery.hasSuffix("\"") && trimmedQuery.count > 2 {
      // Escape any internal quotes and return as-is for phrase matching
      let innerQuery = String(trimmedQuery.dropFirst().dropLast())
      let escapedInnerQuery = innerQuery.replacingOccurrences(of: "\"", with: "\"\"")
      return "\"\(escapedInnerQuery)\""
    }

    // Split query into terms and add prefix wildcards
    let terms = trimmedQuery.components(separatedBy: .whitespacesAndNewlines)
      .filter { !$0.isEmpty }
      .map { term in
        // Escape quotes in individual terms
        let escapedTerm = term.replacingOccurrences(of: "\"", with: "\"\"")

        // Don't add wildcard if term already ends with wildcard or is very short
        if escapedTerm.hasSuffix("*") || escapedTerm.count < 2 {
          return escapedTerm
        }

        return "\(escapedTerm)*"
      }

    // Join terms with AND logic (space-separated)
    return terms.joined(separator: " ")
  }

  private func parseTranscriptionFromRow(_ statement: OpaquePointer?) -> TranscriptionHistory? {
    guard let statement = statement else { return nil }

    let idString = String(cString: sqlite3_column_text(statement, 0))
    guard let id = UUID(uuidString: idString) else { return nil }

    let timestamp = Date(timeIntervalSince1970: sqlite3_column_double(statement, 1))
    let transcribedText = String(cString: sqlite3_column_text(statement, 2))
    let duration = sqlite3_column_double(statement, 3)

    let audioFileReference: String? = {
      if sqlite3_column_type(statement, 4) == SQLITE_NULL {
        return nil
      }
      return String(cString: sqlite3_column_text(statement, 4))
    }()

    let languageDetected: String? = {
      if sqlite3_column_type(statement, 5) == SQLITE_NULL {
        return nil
      }
      return String(cString: sqlite3_column_text(statement, 5))
    }()

    let modelUsed = String(cString: sqlite3_column_text(statement, 6))
    let wordCount = Int(sqlite3_column_int(statement, 7))

    let applicationContext: String? = {
      if sqlite3_column_type(statement, 8) == SQLITE_NULL {
        return nil
      }
      return String(cString: sqlite3_column_text(statement, 8))
    }()

    let uploadTime = sqlite3_column_double(statement, 9)
    let groqProcessingTime = sqlite3_column_double(statement, 10)
    let totalTranscriptionTime = sqlite3_column_double(statement, 11)

    let confidence: Double? = {
      if sqlite3_column_type(statement, 12) == SQLITE_NULL {
        return nil
      }
      return sqlite3_column_double(statement, 12)
    }()

    let didFail: Bool = {
      if sqlite3_column_type(statement, 13) == SQLITE_NULL {
        return false
      }
      return sqlite3_column_int(statement, 13) == 1
    }()

    let errorMessage: String? = {
      if sqlite3_column_type(statement, 14) == SQLITE_NULL {
        return nil
      }
      return String(cString: sqlite3_column_text(statement, 14))
    }()

    let errorCategory: String? = {
      if sqlite3_column_type(statement, 15) == SQLITE_NULL {
        return nil
      }
      return String(cString: sqlite3_column_text(statement, 15))
    }()

    let pureUploadTime = sqlite3_column_double(statement, 16)
    let downloadTime = sqlite3_column_double(statement, 17)
    let totalNetworkTime = sqlite3_column_double(statement, 18)

    return TranscriptionHistory(
      id: id,
      timestamp: timestamp,
      transcribedText: transcribedText,
      duration: duration,
      audioFileReference: audioFileReference,
      languageDetected: languageDetected,
      modelUsed: modelUsed,
      wordCount: wordCount,
      applicationContext: applicationContext,
      uploadTime: uploadTime,
      pureUploadTime: pureUploadTime,
      downloadTime: downloadTime,
      totalNetworkTime: totalNetworkTime,
      groqProcessingTime: groqProcessingTime,
      totalTranscriptionTime: totalTranscriptionTime,
      confidence: confidence,
      searchSnippet: nil,
      didFail: didFail,
      errorMessage: errorMessage,
      errorCategory: errorCategory
    )
  }
}
