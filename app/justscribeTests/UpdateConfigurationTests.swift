//
//  UpdateConfigurationTests.swift
//  justscribeTests
//
//  Copyright (C) 2026 Quassum MB
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <https://www.gnu.org/licenses/>.
//

import Foundation
import Testing
@testable import justscribe

struct UpdateConfigurationTests {

    // The tests run inside the app, so Bundle.main is justscribe.app.
    private var info: [String: Any] { Bundle.main.infoDictionary ?? [:] }

    @Test func feedIsTheWebsiteAppcastOverHTTPS() {
        #expect(info["SUFeedURL"] as? String == "https://justscribe.quassum.com/appcast.xml")
    }

    @Test func publicKeyIsAnEd25519Key() throws {
        let key = try #require(info["SUPublicEDKey"] as? String)
        let data = try #require(Data(base64Encoded: key))
        #expect(data.count == 32)
    }

    @Test func checksAndInstallsAutomaticallyByDefault() {
        #expect(info["SUEnableAutomaticChecks"] as? Bool == true)
        #expect(info["SUAutomaticallyUpdate"] as? Bool == true)
    }

    @Test func sandboxedInstallerServiceIsEnabled() {
        #expect(info["SUEnableInstallerLauncherService"] as? Bool == true)
    }

    @Test func updaterDoesNotStartUnderTheTestRunner() {
        #expect(UpdateService.shouldStartUpdater(environment: ["XCTestConfigurationFilePath": "/tmp/x"]) == false)
    }

    @Test func updaterDoesNotStartInPreviews() {
        #expect(UpdateService.shouldStartUpdater(environment: ["XCODE_RUNNING_FOR_PREVIEWS": "1"]) == false)
    }

    @Test func updaterStartsInANormalLaunch() {
        #expect(UpdateService.shouldStartUpdater(environment: ["HOME": "/Users/x"]) == true)
    }

    @Test func thisTestProcessWouldNotStartTheUpdater() {
        #expect(UpdateService.shouldStartUpdater(environment: ProcessInfo.processInfo.environment) == false)
    }
}
