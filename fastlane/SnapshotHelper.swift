//
//  SnapshotHelper.swift
//  Example
//
//  Created by Felix Krause on 10/8/15.
//  Copyright © 2015 Felix Krause. All rights reserved.
//

// -----------------------------------------------------
// IMPORTANT: When modifying this file, make sure to
//            increment the version number at the very
//            bottom of the file to notify users about
//            the new SnapshotHelper.swift
// -----------------------------------------------------

import Foundation
import XCTest

var deviceLanguage = ""
var locale = ""

func setupSnapshot(_ app: XCUIApplication) {
    Snapshot.setupSnapshot(app)
}

func snapshot(_ name: String, waitForLoadingIndicator: Bool) {
    if waitForLoadingIndicator {
        Snapshot.snapshot(name)
    } else {
        Snapshot.snapshot(name, timeWaitingForIdle: 0)
    }
}

func snaptake(_ name: String, waitForLoadingIndicator: Bool, plot: ()->()) {
    if waitForLoadingIndicator {
        Snapshot.snaptake(name, plot: plot)
    } else {
        Snapshot.snaptake(name, timeWaitingForIdle: 0, plot: plot)
    }
}

/// - Parameters:
///   - name: The name of the snapshot
///   - timeout: Amount of seconds to wait until the network loading indicator disappears. Pass `0` if you don't want to wait.
func snapshot(_ name: String, timeWaitingForIdle timeout: TimeInterval = 20) {
    Snapshot.snapshot(name, timeWaitingForIdle: timeout)
}

/// - Parameters:
///   - name: The name of the snaptake
///   - timeout: Amount of seconds to wait until the network loading indicator disappears. Pass `0` if you don't want to wait.
///   - plot: Plot which should be recorded.
func snaptake(_ name: String, timeWaitingForIdle timeout: TimeInterval = 20, plot: ()->()) {
    Snapshot.snaptake(name, timeWaitingForIdle: timeout, plot: plot)
}

enum SnapshotError: Error, CustomDebugStringConvertible {
    case cannotDetectUser
    case cannotFindHomeDirectory
    case cannotFindSimulatorHomeDirectory
    case cannotAccessSimulatorHomeDirectory(String)
    case cannotRunOnPhysicalDevice

    var debugDescription: String {
        switch self {
        case .cannotDetectUser:
            return "Couldn't find Snapshot configuration files - can't detect current user "
        case .cannotFindHomeDirectory:
            return "Couldn't find Snapshot configuration files - can't detect `Users` dir"
        case .cannotFindSimulatorHomeDirectory:
            return "Couldn't find simulator home location. Please, check SIMULATOR_HOST_HOME env variable."
        case .cannotAccessSimulatorHomeDirectory(let simulatorHostHome):
            return "Can't prepare environment. Simulator home location is inaccessible. Does \(simulatorHostHome) exist?"
        case .cannotRunOnPhysicalDevice:
            return "Can't use Snapshot on a physical device."
        }
    }
}

@objcMembers
open class Snapshot: NSObject {
    static var app: XCUIApplication?
    static var cacheDirectory: URL?
    static var screenshotsDirectory: URL? {
        return cacheDirectory?.appendingPathComponent("screenshots", isDirectory: true)
    }

    open class func setupSnapshot(_ app: XCUIApplication) {
        
        Snapshot.app = app

        do {
            let cacheDir = try pathPrefix()
            Snapshot.cacheDirectory = cacheDir
            setLanguage(app)
            setLocale(app)
            setLaunchArguments(app)
        } catch let error {
            print(error)
        }
    }

    class func setLanguage(_ app: XCUIApplication) {
        guard let cacheDirectory = self.cacheDirectory else {
            print("CacheDirectory is not set - probably running on a physical device?")
            return
        }
        
        let path = cacheDirectory.appendingPathComponent("language.txt")

        do {
            let trimCharacterSet = CharacterSet.whitespacesAndNewlines
            deviceLanguage = try String(contentsOf: path, encoding: .utf8).trimmingCharacters(in: trimCharacterSet)
            app.launchArguments += ["-AppleLanguages", "(\(deviceLanguage))"]
        } catch {
            print("Couldn't detect/set language...")
        }
    }

    class func setLocale(_ app: XCUIApplication) {
        guard let cacheDirectory = self.cacheDirectory else {
            print("CacheDirectory is not set - probably running on a physical device?")
            return
        }
        
        let path = cacheDirectory.appendingPathComponent("locale.txt")

        do {
            let trimCharacterSet = CharacterSet.whitespacesAndNewlines
            locale = try String(contentsOf: path, encoding: .utf8).trimmingCharacters(in: trimCharacterSet)
        } catch {
            print("Couldn't detect/set locale...")
        }
        if locale.isEmpty {
            locale = Locale(identifier: deviceLanguage).identifier
        }
        app.launchArguments += ["-AppleLocale", "\"\(locale)\""]
    }

    class func setLaunchArguments(_ app: XCUIApplication) {
        guard let cacheDirectory = self.cacheDirectory else {
            print("CacheDirectory is not set - probably running on a physical device?")
            return
        }
        
        let path = cacheDirectory.appendingPathComponent("snapshot-launch_arguments.txt")
        app.launchArguments += ["-FASTLANE_SNAPSHOT", "YES", "-ui_testing"]

        do {
            let launchArguments = try String(contentsOf: path, encoding: String.Encoding.utf8)
            let regex = try NSRegularExpression(pattern: "(\\\".+?\\\"|\\S+)", options: [])
            let matches = regex.matches(in: launchArguments, options: [], range: NSRange(location: 0, length: launchArguments.count))
            let results = matches.map { result -> String in
                (launchArguments as NSString).substring(with: result.range)
            }
            app.launchArguments += results
        } catch {
            print("Couldn't detect/set launch_arguments...")
        }
    }

    open class func snapshot(_ name: String, timeWaitingForIdle timeout: TimeInterval = 20) {
        if timeout > 0 {
            waitForLoadingIndicatorToDisappear(within: timeout)
        }

        print("snapshot: \(name)") // more information about this, check out https://docs.fastlane.tools/actions/snapshot/#how-does-it-work

        sleep(1) // Waiting for the animation to be finished (kind of)

        #if os(OSX)
            XCUIApplication().typeKey(XCUIKeyboardKeySecondaryFn, modifierFlags: [])
        #else
            
            guard let app = self.app else {
                print("XCUIApplication is not set. Please call setupSnapshot(app) before snapshot().")
                return
            }
            
            let screenshot = app.windows.firstMatch.screenshot()
            guard let simulator = ProcessInfo().environment["SIMULATOR_DEVICE_NAME"], let screenshotsDir = screenshotsDirectory else { return }
            let path = screenshotsDir.appendingPathComponent("\(simulator)-\(name).png")
            do {
                try screenshot.pngRepresentation.write(to: path)
            } catch let error {
                print("Problem writing screenshot: \(name) to \(path)")
                print(error)
            }
        #endif
    }
    
    open class func snaptake(_ name: String, timeWaitingForIdle timeout: TimeInterval = 20, plot: ()->()) {
        
        guard let recordingFlagPath = snaptakeStart(name, timeWaitingForIdle: timeout) else { return }
        
        snaptakeSetTrimmingFlag()
        
        plot()
        
        snaptakeStop(recordingFlagPath)
        
    }
    
    class func snaptakeStart(_ name: String, timeWaitingForIdle timeout: TimeInterval = 20) -> URL? {
        if timeout > 0 {
            waitForLoadingIndicatorToDisappear(within: timeout)
        }
        
        print("snaptake: \(name)")
        
        sleep(1) // Waiting for the animation to be finished (kind of)
        
        #if os(OSX)
        XCUIApplication().typeKey(XCUIKeyboardKeySecondaryFn, modifierFlags: [])
        #else
        guard let simulator = ProcessInfo().environment["SIMULATOR_DEVICE_NAME"], let screenshotsDir = screenshotsDirectory, let cacheDirectory else { return nil }

        let simulatorNamePath = cacheDirectory.appendingPathComponent("simulator-name.txt")

        let simulatorTrimmed = simulator.replacingOccurrences(of: "Clone 1 of ", with: "")
        let path = "./screenshots/\(locale)/\(simulatorTrimmed)-\(name).mp4"
        let recordingFlagPath = screenshotsDir.appendingPathComponent("recordingFlag.txt")

        do {
            let localeURL = screenshotsDir.appending(component: locale)
            if !FileManager.default.fileExists(atPath: localeURL.path) {
                try FileManager.default.createDirectory(at: localeURL, withIntermediateDirectories: true)
            }

            try simulator.trimmingCharacters(in: .newlines).write(to: simulatorNamePath, atomically: false, encoding: .utf8)
            try path.trimmingCharacters(in: .newlines).write(to: recordingFlagPath, atomically: false, encoding: String.Encoding.utf8)
        } catch let error {
            print("Problem setting recording flag: \(recordingFlagPath)")
            print(error)
        }
        #endif
        return recordingFlagPath
    }
    
    class func snaptakeSetTrimmingFlag() {
        
        let start = Date()
        sleep(2)
        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(2)
        XCUIDevice.shared.orientation = .portrait
        let trimmingTime = -start.timeIntervalSinceNow - 2
        
        let hours = Int(trimmingTime)/3600
        let minutes = (Int(trimmingTime)/60)%60
        let seconds = Int(trimmingTime)%60
        let milliseconds = Int((trimmingTime - Double(Int(trimmingTime))) * 1000)
        let trimmingTimeString = String(format:"%02i:%02i:%02i.%03i", hours, minutes, seconds, milliseconds)
        
        #if os(OSX)
        XCUIApplication().typeKey(XCUIKeyboardKeySecondaryFn, modifierFlags: [])
        #else
        guard let screenshotsDir = screenshotsDirectory else { return }
        
        let trimmingFlagPath = screenshotsDir.appendingPathComponent("trimmingFlag.txt")
        
        do {
            try trimmingTimeString.write(to: trimmingFlagPath, atomically: false, encoding: String.Encoding.utf8)
        } catch let error {
            print("Problem setting recording flag: \(trimmingFlagPath)")
            print(error)
        }
        
        #endif
    }
    
    class func snaptakeStop(_ recordingFlagPath: URL) {
        guard let screenshotsDir = cacheDirectory else { return }

        let fileManager = FileManager.default

        let simulatorNamePath = screenshotsDir.appendingPathComponent("simulator-name.txt")
        
        do {
            try fileManager.removeItem(at: recordingFlagPath)
            try fileManager.removeItem(at: simulatorNamePath)
        } catch let error {
            print("Problem removing recording flag: \(recordingFlagPath)")
            print(error)
        }
    }

    class func waitForLoadingIndicatorToDisappear(within timeout: TimeInterval) {
        #if os(tvOS)
            return
        #endif

        let networkLoadingIndicator = XCUIApplication().otherElements.deviceStatusBars.networkLoadingIndicators.element
        let networkLoadingIndicatorDisappeared = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: networkLoadingIndicator)
        _ = XCTWaiter.wait(for: [networkLoadingIndicatorDisappeared], timeout: timeout)
    }

    class func pathPrefix() throws -> URL? {
        let homeDir: URL
        // on OSX config is stored in /Users/<username>/Library
        // and on iOS/tvOS/WatchOS it's in simulator's home dir
        #if os(OSX)
            guard let user = ProcessInfo().environment["USER"] else {
                throw SnapshotError.cannotDetectUser
            }

            guard let usersDir = FileManager.default.urls(for: .userDirectory, in: .localDomainMask).first else {
                throw SnapshotError.cannotFindHomeDirectory
            }

            homeDir = usersDir.appendingPathComponent(user)
        #else
            #if arch(i386) || arch(x86_64)
                guard let simulatorHostHome = ProcessInfo().environment["SIMULATOR_HOST_HOME"] else {
                    throw SnapshotError.cannotFindSimulatorHomeDirectory
                }
                guard let homeDirUrl = URL(string: simulatorHostHome) else {
                    throw SnapshotError.cannotAccessSimulatorHomeDirectory(simulatorHostHome)
                }
                homeDir = URL(fileURLWithPath: homeDirUrl.path)
            #else
                throw SnapshotError.cannotRunOnPhysicalDevice
            #endif
        #endif
        return homeDir.appendingPathComponent("Library/Caches/tools.fastlane")
    }
}

private extension XCUIElementAttributes {
    var isNetworkLoadingIndicator: Bool {
        if hasWhiteListedIdentifier { return false }

        let hasOldLoadingIndicatorSize = frame.size == CGSize(width: 10, height: 20)
        let hasNewLoadingIndicatorSize = frame.size.width.isBetween(46, and: 47) && frame.size.height.isBetween(2, and: 3)

        return hasOldLoadingIndicatorSize || hasNewLoadingIndicatorSize
    }

    var hasWhiteListedIdentifier: Bool {
        let whiteListedIdentifiers = ["GeofenceLocationTrackingOn", "StandardLocationTrackingOn"]

        return whiteListedIdentifiers.contains(identifier)
    }

    func isStatusBar(_ deviceWidth: CGFloat) -> Bool {
        if elementType == .statusBar { return true }
        guard frame.origin == .zero else { return false }

        let oldStatusBarSize = CGSize(width: deviceWidth, height: 20)
        let newStatusBarSize = CGSize(width: deviceWidth, height: 44)

        return [oldStatusBarSize, newStatusBarSize].contains(frame.size)
    }
}

private extension XCUIElementQuery {
    var networkLoadingIndicators: XCUIElementQuery {
        let isNetworkLoadingIndicator = NSPredicate { (evaluatedObject, _) in
            guard let element = evaluatedObject as? XCUIElementAttributes else { return false }

            return element.isNetworkLoadingIndicator
        }

        return self.containing(isNetworkLoadingIndicator)
    }

    var deviceStatusBars: XCUIElementQuery {
        let deviceWidth = XCUIApplication().frame.width

        let isStatusBar = NSPredicate { (evaluatedObject, _) in
            guard let element = evaluatedObject as? XCUIElementAttributes else { return false }

            return element.isStatusBar(deviceWidth)
        }

        return self.containing(isStatusBar)
    }
}

private extension CGFloat {
    func isBetween(_ numberA: CGFloat, and numberB: CGFloat) -> Bool {
        return numberA...numberB ~= self
    }
}

// Please don't remove the lines below
// They are used to detect outdated configuration files
// SnapshotHelperVersion [1.10]
