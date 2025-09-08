import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

actor ProfilesRepository {
    private let dbService = DatabaseService.shared

    // MARK: - Profiles CRUD

    func list() async -> [Profile] {
        guard let dbConn = await dbService.connection(),
              let db = dbConn.opaquePointer else { return [] }
        var stmt: OpaquePointer?
        var profiles: [Profile] = []
        let sql = "SELECT id, title, is_default, is_enabled, shortcut, transcription_model, post_processing_enabled, post_processing_prompt, post_processing_model, icon_name, icon_color, created_at, updated_at FROM profiles ORDER BY LOWER(title) ASC;"
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let p = parseProfile(stmt) { profiles.append(p) }
            }
        }
        sqlite3_finalize(stmt)
        return profiles
    }

    func get(_ id: String) async -> Profile? {
        guard let dbConn = await dbService.connection(),
              let db = dbConn.opaquePointer else { return nil }
        var stmt: OpaquePointer?
        let sql = "SELECT id, title, is_default, is_enabled, shortcut, transcription_model, post_processing_enabled, post_processing_prompt, post_processing_model, icon_name, icon_color, created_at, updated_at FROM profiles WHERE id = ? LIMIT 1;"
        var profile: Profile?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, (id as NSString).utf8String, -1, SQLITE_TRANSIENT)
            if sqlite3_step(stmt) == SQLITE_ROW {
                profile = parseProfile(stmt)
            }
        }
        sqlite3_finalize(stmt)
        return profile
    }

    func getDefault() async -> Profile? {
        guard let dbConn = await dbService.connection(),
              let db = dbConn.opaquePointer else { return nil }
        var stmt: OpaquePointer?
        let sql = "SELECT id, title, is_default, is_enabled, shortcut, transcription_model, post_processing_enabled, post_processing_prompt, post_processing_model, icon_name, icon_color, created_at, updated_at FROM profiles WHERE is_default = 1 LIMIT 1;"
        var profile: Profile?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            if sqlite3_step(stmt) == SQLITE_ROW {
                profile = parseProfile(stmt)
            }
        }
        sqlite3_finalize(stmt)
        return profile
    }

    func create(_ data: Profile) async throws -> Profile {
        guard let dbConn = await dbService.connection(),
              let db = dbConn.opaquePointer else { return data }
        let sql = """
            INSERT INTO profiles (id, title, is_default, is_enabled, shortcut, transcription_model, post_processing_enabled, post_processing_prompt, post_processing_model, icon_name, icon_color, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            bindProfile(stmt, data)
            let rc = sqlite3_step(stmt)
            sqlite3_finalize(stmt)
            if rc == SQLITE_DONE {
                if data.isDefault { try await ensureSingleDefault(id: data.id) }
                return data
            } else {
                throw NSError(domain: "ProfilesRepository", code: Int(rc), userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(db))])
            }
        }
        sqlite3_finalize(stmt)
        return data
    }

    func update(_ id: String, patch: Profile) async throws -> Profile {
        guard let dbConn = await dbService.connection(),
              let db = dbConn.opaquePointer else { return patch }
        let sql = """
            UPDATE profiles SET title = ?, is_default = ?, is_enabled = ?, shortcut = ?, transcription_model = ?, post_processing_enabled = ?, post_processing_prompt = ?, post_processing_model = ?, icon_name = ?, icon_color = ?, updated_at = ? WHERE id = ?;
        """
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, (patch.title as NSString).utf8String, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int(stmt, 2, patch.isDefault ? 1 : 0)
            sqlite3_bind_int(stmt, 3, patch.isEnabled ? 1 : 0)
            if let sc = patch.shortcut { sqlite3_bind_text(stmt, 4, (sc as NSString).utf8String, -1, SQLITE_TRANSIENT) } else { sqlite3_bind_null(stmt, 4) }
            sqlite3_bind_text(stmt, 5, (patch.transcriptionModel as NSString).utf8String, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int(stmt, 6, patch.postProcessingEnabled ? 1 : 0)
            sqlite3_bind_text(stmt, 7, (patch.postProcessingPrompt as NSString).utf8String, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 8, (patch.postProcessingModel as NSString).utf8String, -1, SQLITE_TRANSIENT)
            if let ic = patch.iconName { sqlite3_bind_text(stmt, 9, (ic as NSString).utf8String, -1, SQLITE_TRANSIENT) } else { sqlite3_bind_null(stmt, 9) }
            if let co = patch.iconColor { sqlite3_bind_text(stmt, 10, (co as NSString).utf8String, -1, SQLITE_TRANSIENT) } else { sqlite3_bind_null(stmt, 10) }
            sqlite3_bind_double(stmt, 11, patch.updatedAt.timeIntervalSince1970)
            sqlite3_bind_text(stmt, 12, (id as NSString).utf8String, -1, SQLITE_TRANSIENT)
            let rc = sqlite3_step(stmt)
            sqlite3_finalize(stmt)
            if rc == SQLITE_DONE {
                if patch.isDefault { try await ensureSingleDefault(id: id) }
                return patch
            } else {
                throw NSError(domain: "ProfilesRepository", code: Int(rc), userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(db))])
            }
        }
        sqlite3_finalize(stmt)
        return patch
    }

    func remove(_ id: String) async throws {
        guard let dbConn = await dbService.connection(),
              let db = dbConn.opaquePointer else { return }
        var stmt: OpaquePointer?
        // Unassign apps first
        let delApps = "DELETE FROM profile_apps WHERE profile_id = ?;"
        if sqlite3_prepare_v2(db, delApps, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, (id as NSString).utf8String, -1, SQLITE_TRANSIENT)
            _ = sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)

        let sql = "DELETE FROM profiles WHERE id = ?;"
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, (id as NSString).utf8String, -1, SQLITE_TRANSIENT)
            _ = sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }

    func reset(with seeds: [Profile]) async throws {
        guard let dbConn = await dbService.connection(),
              let db = dbConn.opaquePointer else { return }

        func makeError(code: Int32) -> NSError {
            let message = String(cString: sqlite3_errmsg(db))
            return NSError(domain: "ProfilesRepository", code: Int(code), userInfo: [NSLocalizedDescriptionKey: message])
        }

        let beginResult = sqlite3_exec(db, "BEGIN IMMEDIATE TRANSACTION;", nil, nil, nil)
        if beginResult != SQLITE_OK {
            throw makeError(code: beginResult)
        }

        var encounteredError: NSError?
        defer {
            if encounteredError == nil {
                sqlite3_exec(db, "COMMIT;", nil, nil, nil)
            } else {
                sqlite3_exec(db, "ROLLBACK;", nil, nil, nil)
            }
        }

        let clearApps = sqlite3_exec(db, "DELETE FROM profile_apps;", nil, nil, nil)
        if clearApps != SQLITE_OK {
            encounteredError = makeError(code: clearApps)
            if let err = encounteredError { throw err }
        }

        let clearProfiles = sqlite3_exec(db, "DELETE FROM profiles;", nil, nil, nil)
        if clearProfiles != SQLITE_OK {
            encounteredError = makeError(code: clearProfiles)
            if let err = encounteredError { throw err }
        }

        guard encounteredError == nil else { return }

        let insertSQL = """
            INSERT INTO profiles (id, title, is_default, is_enabled, shortcut, transcription_model, post_processing_enabled, post_processing_prompt, post_processing_model, icon_name, icon_color, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """

        for profile in seeds {
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, insertSQL, -1, &stmt, nil) == SQLITE_OK {
                bindProfile(stmt, profile)
                let rc = sqlite3_step(stmt)
                if rc != SQLITE_DONE {
                    encounteredError = makeError(code: rc)
                }
            } else {
                encounteredError = makeError(code: sqlite3_errcode(db))
            }
            sqlite3_finalize(stmt)

            if let err = encounteredError {
                throw err
            }
        }
    }

    func setDefault(_ id: String) async throws {
        guard let dbConn = await dbService.connection(),
              let db = dbConn.opaquePointer else { return }
        _ = sqlite3_exec(db, "UPDATE profiles SET is_default = 0 WHERE is_default = 1;", nil, nil, nil)
        var stmt: OpaquePointer?
        let sql = "UPDATE profiles SET is_default = 1, is_enabled = 1, updated_at = ? WHERE id = ?;"
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_double(stmt, 1, Date().timeIntervalSince1970)
            sqlite3_bind_text(stmt, 2, (id as NSString).utf8String, -1, SQLITE_TRANSIENT)
            _ = sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }

    // MARK: - App Assignments

    func appsForProfile(_ id: String) async -> [AppAssignment] {
        guard let dbConn = await dbService.connection(),
              let db = dbConn.opaquePointer else { return [] }
        var stmt: OpaquePointer?
        var items: [AppAssignment] = []
        let sql = "SELECT app_bundle_id, app_name, profile_id, created_at FROM profile_apps WHERE profile_id = ? ORDER BY LOWER(app_name) ASC;"
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, (id as NSString).utf8String, -1, SQLITE_TRANSIENT)
            while sqlite3_step(stmt) == SQLITE_ROW {
                let bundleId = String(cString: sqlite3_column_text(stmt, 0))
                let name = String(cString: sqlite3_column_text(stmt, 1))
                let profileId = String(cString: sqlite3_column_text(stmt, 2))
                let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 3))
                items.append(AppAssignment(bundleId: bundleId, appName: name, profileId: profileId, createdAt: createdAt))
            }
        }
        sqlite3_finalize(stmt)
        return items
    }

    func assignApp(profileId: String, bundleId: String, appName: String) async throws {
        guard let dbConn = await dbService.connection(),
              let db = dbConn.opaquePointer else { return }
        var stmt: OpaquePointer?
        let sql = "INSERT INTO profile_apps (profile_id, app_bundle_id, app_name, created_at) VALUES (?, ?, ?, ?);"
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, (profileId as NSString).utf8String, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, (bundleId as NSString).utf8String, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 3, (appName as NSString).utf8String, -1, SQLITE_TRANSIENT)
            sqlite3_bind_double(stmt, 4, Date().timeIntervalSince1970)
            let rc = sqlite3_step(stmt)
            sqlite3_finalize(stmt)
            if rc != SQLITE_DONE {
                throw NSError(domain: "ProfilesRepository", code: Int(rc), userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(db))])
            }
        } else {
            sqlite3_finalize(stmt)
        }
    }

    func unassignApp(bundleId: String) async throws {
        guard let dbConn = await dbService.connection(),
              let db = dbConn.opaquePointer else { return }
        var stmt: OpaquePointer?
        let sql = "DELETE FROM profile_apps WHERE app_bundle_id = ?;"
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, (bundleId as NSString).utf8String, -1, SQLITE_TRANSIENT)
            _ = sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }

    func getProfileForApp(bundleId: String) async -> Profile? {
        guard let dbConn = await dbService.connection(),
              let db = dbConn.opaquePointer else { return nil }
        var stmt: OpaquePointer?
        let sql = """
            SELECT p.id, p.title, p.is_default, p.is_enabled, p.shortcut, p.transcription_model, p.post_processing_enabled, p.post_processing_prompt, p.post_processing_model, p.icon_name, p.icon_color, p.created_at, p.updated_at
            FROM profiles p
            JOIN profile_apps a ON a.profile_id = p.id
            WHERE a.app_bundle_id = ?
            LIMIT 1;
        """
        var profile: Profile?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, (bundleId as NSString).utf8String, -1, SQLITE_TRANSIENT)
            if sqlite3_step(stmt) == SQLITE_ROW {
                profile = parseProfile(stmt)
            }
        }
        sqlite3_finalize(stmt)
        return profile
    }

    // MARK: - Helpers

    private func parseProfile(_ stmt: OpaquePointer?) -> Profile? {
        guard let s = stmt else { return nil }
        let id = String(cString: sqlite3_column_text(s, 0))
        let title = String(cString: sqlite3_column_text(s, 1))
        let isDefault = sqlite3_column_int(s, 2) == 1
        let isEnabled = sqlite3_column_int(s, 3) == 1
        let shortcut: String? = {
            if sqlite3_column_type(s, 4) == SQLITE_NULL { return nil }
            return String(cString: sqlite3_column_text(s, 4))
        }()
        let model = String(cString: sqlite3_column_text(s, 5))
        let postEnabled = sqlite3_column_int(s, 6) == 1
        let prompt = String(cString: sqlite3_column_text(s, 7))
        let postProcessingModel: String = {
            if sqlite3_column_type(s, 8) == SQLITE_NULL {
                return PostProcessingModelOption.defaultOptionValue
            }
            return String(cString: sqlite3_column_text(s, 8))
        }()
        let iconName: String? = {
            if sqlite3_column_type(s, 9) == SQLITE_NULL { return nil }
            return String(cString: sqlite3_column_text(s, 9))
        }()
        let iconColor: String? = {
            if sqlite3_column_type(s, 10) == SQLITE_NULL { return nil }
            return String(cString: sqlite3_column_text(s, 10))
        }()
        let created = Date(timeIntervalSince1970: sqlite3_column_double(s, 11))
        let updated = Date(timeIntervalSince1970: sqlite3_column_double(s, 12))
        return Profile(id: id, title: title, isDefault: isDefault, isEnabled: isEnabled, shortcut: shortcut, transcriptionModel: model, postProcessingEnabled: postEnabled, postProcessingPrompt: prompt, postProcessingModel: postProcessingModel, iconName: iconName, iconColor: iconColor, createdAt: created, updatedAt: updated)
    }

    private func bindProfile(_ stmt: OpaquePointer?, _ p: Profile) {
        guard let s = stmt else { return }
        sqlite3_bind_text(s, 1, (p.id as NSString).utf8String, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(s, 2, (p.title as NSString).utf8String, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(s, 3, p.isDefault ? 1 : 0)
        sqlite3_bind_int(s, 4, p.isEnabled ? 1 : 0)
        if let sc = p.shortcut { sqlite3_bind_text(s, 5, (sc as NSString).utf8String, -1, SQLITE_TRANSIENT) } else { sqlite3_bind_null(s, 5) }
        sqlite3_bind_text(s, 6, (p.transcriptionModel as NSString).utf8String, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(s, 7, p.postProcessingEnabled ? 1 : 0)
        sqlite3_bind_text(s, 8, (p.postProcessingPrompt as NSString).utf8String, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(s, 9, (p.postProcessingModel as NSString).utf8String, -1, SQLITE_TRANSIENT)
        if let ic = p.iconName { sqlite3_bind_text(s, 10, (ic as NSString).utf8String, -1, SQLITE_TRANSIENT) } else { sqlite3_bind_null(s, 10) }
        if let co = p.iconColor { sqlite3_bind_text(s, 11, (co as NSString).utf8String, -1, SQLITE_TRANSIENT) } else { sqlite3_bind_null(s, 11) }
        sqlite3_bind_double(s, 12, p.createdAt.timeIntervalSince1970)
        sqlite3_bind_double(s, 13, p.updatedAt.timeIntervalSince1970)
    }

    private func ensureSingleDefault(id: String) async throws {
        // Enforce single default by resetting others; the partial unique index also guards this
        try await setDefault(id)
    }
}
