//
//  ViewController.swift
//  JsonDemo
//
//  Copyright (c) 2026 trojanzhang. All rights reserved.
//
//  This file is part of ZTAPI.
//
//  ZTAPI is free software: you can redistribute it and/or modify
//  it under the terms of the GNU Affero General Public License as published
//  by the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  ZTAPI is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
//  GNU Affero General Public License for more details.
//
//  You should have received a copy of the GNU Affero General Public License
//  along with ZTAPI. If not, see <https://www.gnu.org/licenses/>.
//

import UIKit

class ViewController: UIViewController {

    let vm = VM()

    override func viewDidLoad() {
        super.viewDidLoad()

        NSLog("[ViewController] viewDidLoad started")
        print("[ViewController] viewDidLoad started")

        // Add test button
        let testButton = UIButton(type: .system)
        testButton.setTitle("Run ZTAPI Tests", for: .normal)
        testButton.translatesAutoresizingMaskIntoConstraints = false
        testButton.addTarget(self, action: #selector(runTests), for: .touchUpInside)
        view.addSubview(testButton)

        NSLayoutConstraint.activate([
            testButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            testButton.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])

        NSLog("[ViewController] about to auto-run tests")
        // Auto-run tests
        runTests()
    }

    @objc func runTests() {
        NSLog("[ViewController] runTests called")
        print("[ViewController] runTests called")
        let tests = ZTAPITests()
        Task {
            NSLog("[ViewController] starting test suite")
            await tests.runAllTests()
            NSLog("[ViewController] test suite completed")
        }
    }
}


