//
//  KeyboardViewController.swift
//  JustScribeKeyboard
//
//  Created by Antoni Silvestrovic on 22/10/2026.
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

import KeyboardCore
import SwiftUI

final class KeyboardViewController: KeyboardInputViewController {

    private lazy var dictation = DictationClient(
        bridge: DictationBridge(),
        hasFullAccess: { [weak self] in self?.hasFullAccess ?? false },
        openURL: { [weak self] url in self?.openUrl(url) },
        textBeforeCursor: { [weak self] in self?.textDocumentProxy.documentContextBeforeInput },
        insert: { [weak self] text in self?.textDocumentProxy.insertText(text) }
    )

    override func viewDidLoad() {
        super.viewDidLoad()
        setup(for: .justScribe)
        services.autocompleteService = TextCheckerAutocompleteService(locale: state.keyboardContext.locale)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        dictation.activate()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        dictation.deactivate()
    }

    override func viewWillSetupKeyboardView() {
        let dictation = dictation
        setupKeyboardView { controller in
            JustScribeKeyboardView(
                state: controller.state,
                services: controller.services,
                dictation: dictation
            )
        }
    }
}

extension KeyboardApp {

    static var justScribe: KeyboardApp {
        .init(
            name: "JustScribe",
            appGroupId: AppGroup.id,
            locales: [.english]
        )
    }
}
