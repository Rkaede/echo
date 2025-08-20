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

actor HistoryDatabaseActor {
    private var db: OpaquePointer?
    private let dbPath: String
    
    init() {
        // Use Application Support directory (sandbox-safe)
        let appSupportPath = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let echoDirectory = appSupportPath.appendingPathComponent("Echo")
        
        // Ensure directory exists
        do {
            try FileManager.default.createDirectory(at: echoDirectory, withIntermediateDirectories: true, attributes: nil)
        } catch {
            print("HistoryDatabaseActor: Failed to create Application Support directory: \(error)")
        }
        
        dbPath = echoDirectory.appendingPathComponent("echo_history.sqlite").path
        
        // Initialize on actor context after creation
        Task { @MainActor in
            let _ = await self.initializeDatabase()
        }
    }
    
    deinit {
        if db != nil {
            sqlite3_close(db)
        }
    }
    
    private func initializeDatabase() async {
        openDatabase()
        createTable()
    }
    
    private func openDatabase() {
        if sqlite3_open(dbPath, &db) == SQLITE_OK {
            print("HistoryDatabaseActor: Successfully opened connection to database at \(dbPath)")
            
            // Check if file exists and get its size
            let fileManager = FileManager.default
            if fileManager.fileExists(atPath: dbPath) {
                do {
                    let attributes = try fileManager.attributesOfItem(atPath: dbPath)
                    let fileSize = attributes[.size] as? Int64 ?? 0
                    print("HistoryDatabaseActor: Database file exists, size: \(fileSize) bytes")
                } catch {
                    print("HistoryDatabaseActor: Could not get database file attributes: \(error)")
                }
            } else {
                print("HistoryDatabaseActor: Warning - Database file does not exist at path")
            }
        } else {
            print("HistoryDatabaseActor: Unable to open database: \(String(cString: sqlite3_errmsg(db)))")
        }
    }
    
    private func createTable() {
        let createTableSQL = """
            CREATE TABLE IF NOT EXISTS transcription_history(
                id TEXT PRIMARY KEY,
                timestamp REAL NOT NULL,
                transcribed_text TEXT NOT NULL,
                duration REAL NOT NULL,
                audio_file_reference TEXT,
                language_detected TEXT,
                model_used TEXT NOT NULL,
                word_count INTEGER NOT NULL,
                application_context TEXT,
                upload_time REAL NOT NULL,
                groq_processing_time REAL NOT NULL,
                total_transcription_time REAL NOT NULL,
                confidence REAL
            );
        """
        
        if sqlite3_exec(db, createTableSQL, nil, nil, nil) == SQLITE_OK {
            print("History table created successfully")
        } else {
            print("History table could not be created")
        }
        
        let createIndexSQL = "CREATE INDEX IF NOT EXISTS idx_timestamp ON transcription_history(timestamp DESC);"
        sqlite3_exec(db, createIndexSQL, nil, nil, nil)
        
        let createTextIndexSQL = "CREATE INDEX IF NOT EXISTS idx_text ON transcription_history(transcribed_text);"
        sqlite3_exec(db, createTextIndexSQL, nil, nil, nil)
        
        // Create FTS5 virtual table for full-text search
        let createFTSSQL = """
            CREATE VIRTUAL TABLE IF NOT EXISTS transcription_fts USING fts5(
                transcribed_text, 
                application_context,
                content='transcription_history',
                content_rowid='rowid'
            );
        """
        
        if sqlite3_exec(db, createFTSSQL, nil, nil, nil) == SQLITE_OK {
            print("FTS5 table created successfully")
        } else {
            print("FTS5 table could not be created: \(String(cString: sqlite3_errmsg(db)))")
        }
        
        // Create triggers to keep FTS table in sync
        let createTriggers = """
            CREATE TRIGGER IF NOT EXISTS transcription_fts_insert AFTER INSERT ON transcription_history BEGIN
                INSERT INTO transcription_fts(rowid, transcribed_text, application_context) 
                VALUES (new.rowid, new.transcribed_text, new.application_context);
            END;
            
            CREATE TRIGGER IF NOT EXISTS transcription_fts_delete AFTER DELETE ON transcription_history BEGIN
                INSERT INTO transcription_fts(transcription_fts, rowid, transcribed_text, application_context) 
                VALUES('delete', old.rowid, old.transcribed_text, old.application_context);
            END;
            
            CREATE TRIGGER IF NOT EXISTS transcription_fts_update AFTER UPDATE ON transcription_history BEGIN
                INSERT INTO transcription_fts(transcription_fts, rowid, transcribed_text, application_context) 
                VALUES('delete', old.rowid, old.transcribed_text, old.application_context);
                INSERT INTO transcription_fts(rowid, transcribed_text, application_context) 
                VALUES (new.rowid, new.transcribed_text, new.application_context);
            END;
        """
        
        if sqlite3_exec(db, createTriggers, nil, nil, nil) == SQLITE_OK {
            print("FTS5 triggers created successfully")
        } else {
            print("FTS5 triggers could not be created: \(String(cString: sqlite3_errmsg(db)))")
        }
        
        // Populate FTS table with existing data if it's empty
        let checkFTSSQL = "SELECT COUNT(*) FROM transcription_fts;"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, checkFTSSQL, -1, &stmt, nil) == SQLITE_OK,
           sqlite3_step(stmt) == SQLITE_ROW {
            let ftsCount = sqlite3_column_int(stmt, 0)
            if ftsCount == 0 {
                let rebuildFTSSQL = "INSERT INTO transcription_fts(transcription_fts) VALUES('rebuild');"
                if sqlite3_exec(db, rebuildFTSSQL, nil, nil, nil) == SQLITE_OK {
                    print("FTS5 table populated with existing data")
                } else {
                    print("Failed to populate FTS5 table: \(String(cString: sqlite3_errmsg(db)))")
                }
            }
        }
        sqlite3_finalize(stmt)
    }
    
    func saveTranscription(_ transcription: TranscriptionHistory) async -> Bool {
        let insertSQL = """
            INSERT INTO transcription_history 
            (id, timestamp, transcribed_text, duration, audio_file_reference, language_detected, 
             model_used, word_count, application_context, upload_time, groq_processing_time, 
             total_transcription_time, confidence) 
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        
        var statement: OpaquePointer?
        var success = false
        
        if sqlite3_prepare_v2(db, insertSQL, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, (transcription.id.uuidString as NSString).utf8String, -1, SQLITE_TRANSIENT)
            sqlite3_bind_double(statement, 2, transcription.timestamp.timeIntervalSince1970)
            sqlite3_bind_text(statement, 3, (transcription.transcribedText as NSString).utf8String, -1, SQLITE_TRANSIENT)
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
            
            sqlite3_bind_text(statement, 7, (transcription.modelUsed as NSString).utf8String, -1, SQLITE_TRANSIENT)
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
    
    func searchWithSnippets(query: String, limit: Int = 100) async -> Result<[(TranscriptionHistory, String)], HistoryError> {
        var results: [(TranscriptionHistory, String)] = []
        
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
                    let snippet = String(cString: sqlite3_column_text(statement, 13))
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
    
    func getAllTranscriptions(limit: Int = 100, offset: Int = 0) async -> [TranscriptionHistory] {
        var transcriptions: [TranscriptionHistory] = []
        
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
            print("HistoryDatabaseActor: Failed to prepare getAllTranscriptions query: \(String(cString: sqlite3_errmsg(db)))")
        }
        
        sqlite3_finalize(statement)
        return transcriptions
    }
    
    func deleteTranscription(id: UUID) async -> Bool {
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
        let deleteSQL = "DELETE FROM transcription_history;"
        return sqlite3_exec(db, deleteSQL, nil, nil, nil) == SQLITE_OK
    }
    
    func getTotalCount() async -> Int {
        let countSQL = "SELECT COUNT(*) FROM transcription_history;"
        var stmt: OpaquePointer?
        var count = 0
        
        if sqlite3_prepare_v2(db, countSQL, -1, &stmt, nil) == SQLITE_OK,
           sqlite3_step(stmt) == SQLITE_ROW {
            count = Int(sqlite3_column_int(stmt, 0))
        }
        sqlite3_finalize(stmt)
        return count
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
            groqProcessingTime: groqProcessingTime,
            totalTranscriptionTime: totalTranscriptionTime,
            confidence: confidence,
            searchSnippet: nil
        )
    }
}

@MainActor
class HistoryManager: ObservableObject {
    static let shared = HistoryManager()
    
    @Published var recentTranscriptions: [TranscriptionHistory] = []
    @Published var allTranscriptions: [TranscriptionHistory] = []
    @Published var totalCount: Int = 0
    @Published var searchError: String? = nil
    
    private let databaseActor = HistoryDatabaseActor()
    
    private init() {
        Task {
            await loadInitialData()
        }
    }
    
    private func loadInitialData() async {
        let all = await databaseActor.getAllTranscriptions()
        let recent = Array(all.prefix(10))
        let count = await databaseActor.getTotalCount()
        
        await MainActor.run {
            self.allTranscriptions = all
            self.recentTranscriptions = recent
            self.totalCount = count
        }
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
            let all = await databaseActor.getAllTranscriptions()
            await MainActor.run {
                self.allTranscriptions = all
            }
        }
    }
    
    private func loadRecentTranscriptions() {
        Task {
            let all = await databaseActor.getAllTranscriptions(limit: 10)
            await MainActor.run {
                self.recentTranscriptions = all
            }
        }
    }
    
    private func updateTotalCount() {
        Task {
            let count = await databaseActor.getTotalCount()
            await MainActor.run {
                self.totalCount = count
            }
        }
    }
    
    func saveTranscription(_ transcription: TranscriptionHistory) {
        Task {
            let success = await databaseActor.saveTranscription(transcription)
            if success {
                await refreshData()
            }
        }
    }
    
    func searchWithSnippets(query: String, limit: Int = 100) async -> [(TranscriptionHistory, String)] {
        let result = await databaseActor.searchWithSnippets(query: query, limit: limit)
        
        await MainActor.run {
            switch result {
            case .success:
                self.searchError = nil
            case .failure(let error):
                self.searchError = error.errorDescription
            }
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
            
            let success = await databaseActor.deleteTranscription(id: id)
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
            let success = await databaseActor.deleteAllTranscriptions()
            if success {
                // Delete all associated audio files
                AudioStorageManager.shared.deleteAllAudioFiles()
                
                await MainActor.run {
                    self.allTranscriptions = []
                    self.recentTranscriptions = []
                    self.totalCount = 0
                }
            }
        }
    }
    
    private func refreshData() async {
        let all = await databaseActor.getAllTranscriptions()
        let recent = Array(all.prefix(10))
        let count = await databaseActor.getTotalCount()
        
        await MainActor.run {
            self.allTranscriptions = all
            self.recentTranscriptions = recent
            self.totalCount = count
        }
    }
}
