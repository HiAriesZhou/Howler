import HowlerCore
import XCTest
@testable import Howler

@MainActor
final class SettingsShortcutTests: XCTestCase {
    private let custom = HotKeyCombo(keyCode: 40, modifiers: [.control, .option], keyLabel: "K")

    private func withSettings(_ body: (AppSettings, UserDefaults) throws -> Void) throws {
        let suite = "HowlerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(AppSettings(defaults: defaults, keys: MemoryKeys().access), defaults)
    }

    func testSettingsShortcutPersistsAndCanReturnToDefault() throws {
        try withSettings { settings, defaults in
            XCTAssertEqual(settings.settingsHotKey, .settings)
            XCTAssertTrue(settings.setShortcut(custom, for: .settings))
            let reopened = AppSettings(defaults: defaults, keys: MemoryKeys().access)
            XCTAssertEqual(reopened.settingsHotKey, custom)
            XCTAssertEqual(reopened.hotKey, .standard)
            XCTAssertEqual(reopened.screenshotHotKey, .screenshot)
            XCTAssertTrue(reopened.resetShortcut(for: .settings))
            XCTAssertNil(defaults.data(forKey: ShortcutAction.settings.defaultsKey))
            XCTAssertEqual(AppSettings(defaults: defaults, keys: MemoryKeys().access).settingsHotKey, .settings)
        }
    }

    func testAllConfiguredActionPairsRejectConflicts() throws {
        try withSettings { settings, defaults in
            for action in ShortcutAction.allCases {
                for other in ShortcutAction.allCases where action != other {
                    var conflict = try XCTUnwrap(settings.shortcut(for: other))
                    conflict.keyLabel = "Different keyboard label"
                    XCTAssertEqual(settings.shortcutConflict(conflict, for: action), other)
                    XCTAssertFalse(settings.setShortcut(conflict, for: action))
                    XCTAssertEqual(settings.shortcut(for: action), action.standard)
                    XCTAssertNil(defaults.data(forKey: action.defaultsKey))
                }
            }
        }
    }

    func testEveryResetPreservesCustomShortcutWhenDefaultIsTaken() throws {
        for action in ShortcutAction.allCases {
            try withSettings { settings, defaults in
                let other = try XCTUnwrap(ShortcutAction.allCases.first { $0 != action })
                XCTAssertTrue(settings.setShortcut(custom, for: action))
                XCTAssertTrue(settings.setShortcut(action.standard, for: other))
                let saved = defaults.data(forKey: action.defaultsKey)
                XCTAssertFalse(settings.resetShortcut(for: action))
                XCTAssertEqual(settings.shortcut(for: action), custom)
                XCTAssertEqual(defaults.data(forKey: action.defaultsKey), saved)
                let reopened = AppSettings(defaults: defaults, keys: MemoryKeys().access)
                XCTAssertEqual(reopened.shortcut(for: action), custom)
                XCTAssertEqual(reopened.shortcut(for: other), action.standard)
            }
        }
    }

    func testOptionCommaCanBeReassignedAfterSettingsMovesAndSurvivesRestart() throws {
        for action in [ShortcutAction.letter, .capture] {
            try withSettings { settings, defaults in
                XCTAssertTrue(settings.setShortcut(custom, for: .settings))
                XCTAssertTrue(settings.setShortcut(.settings, for: action))
                let reopened = AppSettings(defaults: defaults, keys: MemoryKeys().access)
                XCTAssertEqual(reopened.settingsHotKey, custom)
                XCTAssertEqual(reopened.shortcut(for: action), .settings)
                XCTAssertFalse(reopened.resetShortcut(for: .settings))
            }
        }
    }

    func testHistoricalLetterDefaultsMigrateOnlyOnce() throws {
        for oldDefault in [HotKeyCombo.settings, .previousStandard] {
            let suite = "HowlerTests.\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            try defaults.set(JSONEncoder().encode(oldDefault), forKey: "hotKey")
            let settings = AppSettings(defaults: defaults, keys: MemoryKeys().access)
            XCTAssertEqual(settings.hotKey, .standard)
            XCTAssertTrue(settings.setShortcut(custom, for: .settings))
            XCTAssertTrue(settings.setShortcut(oldDefault, for: .letter))
            XCTAssertEqual(AppSettings(defaults: defaults, keys: MemoryKeys().access).hotKey, oldDefault)
        }
    }

    func testInvalidSettingsShortcutFallsBackWithoutChangingOtherActions() throws {
        try withSettings { settings, defaults in
            let invalid = HotKeyCombo(keyCode: 53, modifiers: [], keyLabel: "Esc")
            XCTAssertFalse(settings.setShortcut(invalid, for: .settings))
            try defaults.set(JSONEncoder().encode(invalid), forKey: ShortcutAction.settings.defaultsKey)
            let reopened = AppSettings(defaults: defaults, keys: MemoryKeys().access)
            XCTAssertEqual(reopened.settingsHotKey, .settings)
            XCTAssertEqual(reopened.hotKey, .standard)
            XCTAssertEqual(reopened.screenshotHotKey, .screenshot)
        }
    }

    func testEmptyShortcutsPersistAndResetIsDifferentFromClearing() throws {
        try withSettings { settings, defaults in
            for action in ShortcutAction.allCases {
                XCTAssertTrue(settings.setShortcut(nil, for: action))
                XCTAssertNotNil(defaults.data(forKey: action.defaultsKey))
            }
            let reopened = AppSettings(defaults: defaults, keys: MemoryKeys().access)
            for action in ShortcutAction.allCases {
                XCTAssertNil(reopened.shortcut(for: action))
                XCTAssertTrue(reopened.resetShortcut(for: action))
                XCTAssertNil(defaults.data(forKey: action.defaultsKey))
            }
            let reset = AppSettings(defaults: defaults, keys: MemoryKeys().access)
            for action in ShortcutAction.allCases {
                XCTAssertEqual(reset.shortcut(for: action), action.standard)
            }
        }
    }

    func testClearingReleasesTheCombinationAndResetStillChecksConflicts() throws {
        for action in ShortcutAction.allCases {
            try withSettings { settings, defaults in
                let other = try XCTUnwrap(ShortcutAction.allCases.first { $0 != action })
                XCTAssertTrue(settings.setShortcut(nil, for: action))
                XCTAssertTrue(settings.setShortcut(action.standard, for: other))
                XCTAssertFalse(settings.resetShortcut(for: action))
                XCTAssertNil(settings.shortcut(for: action))
                let reopened = AppSettings(defaults: defaults, keys: MemoryKeys().access)
                XCTAssertNil(reopened.shortcut(for: action))
                XCTAssertEqual(reopened.shortcut(for: other), action.standard)
            }
        }
    }

    func testExplicitEmptyValuesSurviveFirstLaunchMigrations() throws {
        let suite = "HowlerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        for action in ShortcutAction.allCases {
            try defaults.set(JSONEncoder().encode(Optional<HotKeyCombo>.none), forKey: action.defaultsKey)
        }
        let settings = AppSettings(defaults: defaults, keys: MemoryKeys().access)
        for action in ShortcutAction.allCases { XCTAssertNil(settings.shortcut(for: action)) }
    }
}
