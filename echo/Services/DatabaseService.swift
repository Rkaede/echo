import Foundation
import SQLite3

// Sendable wrapper for database operations
struct DatabaseConnection: @unchecked Sendable {
    private let pointer: OpaquePointer?
    
    init?(_ pointer: OpaquePointer?) {
        self.pointer = pointer
    }
    
    var opaquePointer: OpaquePointer? {
        return pointer
    }
}

actor DatabaseService {
    static let shared = DatabaseService()

    private var db: OpaquePointer?
    private var dbPath: String = ""

    private init() {
        Task {
            await initialize()
        }
    }

    deinit {
        if db != nil {
            sqlite3_close(db)
        }
    }

    // MARK: - Public API

    nonisolated func connection() async -> DatabaseConnection? {
        await ensureInitialized()
        return await getConnection()
    }
    
    private func getConnection() async -> DatabaseConnection? {
        return DatabaseConnection(db)
    }
    
    private func ensureInitialized() async {
        if await getConnection() == nil {
            await initialize()
        }
    }

    /// Returns the database file path, ensuring initialization has occurred.
    func databasePath() async -> String {
        if db == nil && dbPath.isEmpty {
            await initialize()
        }
        return dbPath
    }

    func inTransaction<T>(_ block: (OpaquePointer) throws -> T) rethrows -> T? {
        guard let db = db else { return nil }
        sqlite3_exec(db, "BEGIN IMMEDIATE TRANSACTION;", nil, nil, nil)
        do {
            let result = try block(db)
            sqlite3_exec(db, "COMMIT;", nil, nil, nil)
            return result
        } catch {
            sqlite3_exec(db, "ROLLBACK;", nil, nil, nil)
            return nil
        }
    }

    // MARK: - Initialization & Migrations

    private func initialize() async {
        setupPathsAndMigrateIfNeeded()
        openDatabase()
        runMigrations()
    }

    private func setupPathsAndMigrateIfNeeded() {
        let appSupportPath = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let echoDirectory = appSupportPath.appendingPathComponent("Echo")

        // Ensure directory exists
        do {
            try FileManager.default.createDirectory(at: echoDirectory, withIntermediateDirectories: true, attributes: nil)
        } catch {
            print("DatabaseService: Failed to create Application Support directory: \(error)")
        }

        let unified = echoDirectory.appendingPathComponent("echo.sqlite")
        let legacy = echoDirectory.appendingPathComponent("echo_history.sqlite")

        // If unified DB doesn't exist but legacy does, move it
        if !FileManager.default.fileExists(atPath: unified.path),
           FileManager.default.fileExists(atPath: legacy.path) {
            do {
                try FileManager.default.moveItem(at: legacy, to: unified)
                print("DatabaseService: Migrated legacy database to echo.sqlite")
            } catch {
                print("DatabaseService: Failed to migrate legacy DB: \(error)")
            }
        }

        dbPath = unified.path
    }

    private func openDatabase() {
        if sqlite3_open(dbPath, &db) == SQLITE_OK {
            print("DatabaseService: Opened database at \(dbPath)")
        } else {
            print("DatabaseService: Unable to open database: \(String(cString: sqlite3_errmsg(db)))")
        }
    }

    private func currentUserVersion() -> Int32 {
        guard let db = db else { return 0 }
        var stmt: OpaquePointer?
        var version: Int32 = 0
        if sqlite3_prepare_v2(db, "PRAGMA user_version;", -1, &stmt, nil) == SQLITE_OK {
            if sqlite3_step(stmt) == SQLITE_ROW {
                version = sqlite3_column_int(stmt, 0)
            }
        }
        sqlite3_finalize(stmt)
        return version
    }

    private func setUserVersion(_ version: Int32) {
        guard let db = db else { return }
        let sql = "PRAGMA user_version = \(version);"
        sqlite3_exec(db, sql, nil, nil, nil)
    }

    private func runMigrations() {
        guard let db = db else { return }
        var version = currentUserVersion()

        if version < 1 {
            // v1: Create profiles table and indices
            let createProfilesSQL = """
            CREATE TABLE IF NOT EXISTS profiles (
              id TEXT PRIMARY KEY,
              title TEXT NOT NULL,
              is_default INTEGER NOT NULL CHECK (is_default IN (0,1)),
              is_enabled INTEGER NOT NULL CHECK (is_enabled IN (0,1)) DEFAULT 1,
              shortcut TEXT,
              transcription_model TEXT NOT NULL,
              post_processing_enabled INTEGER NOT NULL CHECK (post_processing_enabled IN (0,1)),
              post_processing_prompt TEXT NOT NULL,
              post_processing_model TEXT NOT NULL,
              icon_name TEXT,
              icon_color TEXT,
              created_at REAL NOT NULL,
              updated_at REAL NOT NULL
            );
            """
            _ = sqlite3_exec(db, createProfilesSQL, nil, nil, nil)

            let idxTitle = "CREATE UNIQUE INDEX IF NOT EXISTS idx_profiles_title_ci ON profiles(LOWER(title));"
            _ = sqlite3_exec(db, idxTitle, nil, nil, nil)

            let idxShortcut = "CREATE UNIQUE INDEX IF NOT EXISTS idx_profiles_shortcut ON profiles(shortcut) WHERE shortcut IS NOT NULL;"
            _ = sqlite3_exec(db, idxShortcut, nil, nil, nil)

            let idxDefault = "CREATE UNIQUE INDEX IF NOT EXISTS idx_profiles_one_default ON profiles(is_default) WHERE is_default = 1;"
            _ = sqlite3_exec(db, idxDefault, nil, nil, nil)

            version = 1
            setUserVersion(version)
            print("DatabaseService: Migrated to schema v1 (profiles)")
        }

        if version < 2 {
            // v2: Create profile_apps table and indices
            let createAppsSQL = """
            CREATE TABLE IF NOT EXISTS profile_apps (
              profile_id TEXT NOT NULL,
              app_bundle_id TEXT NOT NULL,
              app_name TEXT NOT NULL,
              created_at REAL NOT NULL,
              PRIMARY KEY (profile_id, app_bundle_id)
            );
            """
            _ = sqlite3_exec(db, createAppsSQL, nil, nil, nil)

            let idxBundleUnique = "CREATE UNIQUE INDEX IF NOT EXISTS idx_profile_apps_bundle_unique ON profile_apps(app_bundle_id);"
            _ = sqlite3_exec(db, idxBundleUnique, nil, nil, nil)

            let idxProfile = "CREATE INDEX IF NOT EXISTS idx_profile_apps_profile ON profile_apps(profile_id);"
            _ = sqlite3_exec(db, idxProfile, nil, nil, nil)

            version = 2
            setUserVersion(version)
            print("DatabaseService: Migrated to schema v2 (profile_apps)")
        }

        if version < 3 {
            var columnExists = false
            var infoStmt: OpaquePointer?
            if sqlite3_prepare_v2(db, "PRAGMA table_info(profiles);", -1, &infoStmt, nil) == SQLITE_OK {
                while sqlite3_step(infoStmt) == SQLITE_ROW {
                    if let namePtr = sqlite3_column_text(infoStmt, 1) {
                        let name = String(cString: namePtr)
                        if name == "post_processing_model" {
                            columnExists = true
                            break
                        }
                    }
                }
            }
            sqlite3_finalize(infoStmt)

            if !columnExists {
                let addColumnSQL = "ALTER TABLE profiles ADD COLUMN post_processing_model TEXT;"
                _ = sqlite3_exec(db, addColumnSQL, nil, nil, nil)
            }

            let defaultModel = PostProcessingModelOption.defaultOptionValue.replacingOccurrences(of: "'", with: "''")
            let updateSQL = "UPDATE profiles SET post_processing_model = COALESCE(post_processing_model, '\(defaultModel)');"
            _ = sqlite3_exec(db, updateSQL, nil, nil, nil)

            version = 3
            setUserVersion(version)
            print("DatabaseService: Migrated to schema v3 (post-processing model)")
        }

        if version < 4 {
            var columnExists = false
            var infoStmt: OpaquePointer?
            if sqlite3_prepare_v2(db, "PRAGMA table_info(profiles);", -1, &infoStmt, nil) == SQLITE_OK {
                while sqlite3_step(infoStmt) == SQLITE_ROW {
                    if let namePtr = sqlite3_column_text(infoStmt, 1) {
                        let name = String(cString: namePtr)
                        if name == "is_enabled" {
                            columnExists = true
                            break
                        }
                    }
                }
            }
            sqlite3_finalize(infoStmt)

            if !columnExists {
                let addColumnSQL = "ALTER TABLE profiles ADD COLUMN is_enabled INTEGER NOT NULL DEFAULT 1;"
                _ = sqlite3_exec(db, addColumnSQL, nil, nil, nil)
            }

            let normalizeSQL = "UPDATE profiles SET is_enabled = COALESCE(is_enabled, 1);"
            _ = sqlite3_exec(db, normalizeSQL, nil, nil, nil)

            version = 4
            setUserVersion(version)
            print("DatabaseService: Migrated to schema v4 (profile enable flag)")
        }

        if version < 5 {
            // v5: Add error tracking columns to transcription_history table
            var didFailExists = false
            var errorMessageExists = false
            var errorCategoryExists = false

            var infoStmt: OpaquePointer?
            if sqlite3_prepare_v2(db, "PRAGMA table_info(transcription_history);", -1, &infoStmt, nil) == SQLITE_OK {
                while sqlite3_step(infoStmt) == SQLITE_ROW {
                    if let namePtr = sqlite3_column_text(infoStmt, 1) {
                        let name = String(cString: namePtr)
                        if name == "did_fail" {
                            didFailExists = true
                        } else if name == "error_message" {
                            errorMessageExists = true
                        } else if name == "error_category" {
                            errorCategoryExists = true
                        }
                    }
                }
            }
            sqlite3_finalize(infoStmt)

            if !didFailExists {
                let addColumnSQL = "ALTER TABLE transcription_history ADD COLUMN did_fail INTEGER NOT NULL DEFAULT 0;"
                _ = sqlite3_exec(db, addColumnSQL, nil, nil, nil)
            }

            if !errorMessageExists {
                let addColumnSQL = "ALTER TABLE transcription_history ADD COLUMN error_message TEXT;"
                _ = sqlite3_exec(db, addColumnSQL, nil, nil, nil)
            }

            if !errorCategoryExists {
                let addColumnSQL = "ALTER TABLE transcription_history ADD COLUMN error_category TEXT;"
                _ = sqlite3_exec(db, addColumnSQL, nil, nil, nil)
            }

            version = 5
            setUserVersion(version)
            print("DatabaseService: Migrated to schema v5 (error tracking)")
        }

        if version < 6 {
            // v6: Create transcription_history table and FTS5 support
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
                confidence REAL,
                did_fail INTEGER NOT NULL DEFAULT 0,
                error_message TEXT,
                error_category TEXT
            );
            """
            _ = sqlite3_exec(db, createTableSQL, nil, nil, nil)

            let createIndexSQL = "CREATE INDEX IF NOT EXISTS idx_timestamp ON transcription_history(timestamp DESC);"
            _ = sqlite3_exec(db, createIndexSQL, nil, nil, nil)

            let createTextIndexSQL = "CREATE INDEX IF NOT EXISTS idx_text ON transcription_history(transcribed_text);"
            _ = sqlite3_exec(db, createTextIndexSQL, nil, nil, nil)

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
                print("DatabaseService: FTS5 table created successfully")
            } else {
                print("DatabaseService: FTS5 table could not be created: \(String(cString: sqlite3_errmsg(db)))")
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
                print("DatabaseService: FTS5 triggers created successfully")
            } else {
                print("DatabaseService: FTS5 triggers could not be created: \(String(cString: sqlite3_errmsg(db)))")
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
                        print("DatabaseService: FTS5 table populated with existing data")
                    } else {
                        print("DatabaseService: Failed to populate FTS5 table: \(String(cString: sqlite3_errmsg(db)))")
                    }
                }
            }
            sqlite3_finalize(stmt)

            version = 6
            setUserVersion(version)
            print("DatabaseService: Migrated to schema v6 (transcription history)")
        }
    }
}
