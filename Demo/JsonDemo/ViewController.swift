//
//  ViewController.swift
//  JsonDemo
//
//  Created by zt on 2025/3/29.
//

import UIKit
import ZTJSON
import SwiftyJSON


class ViewController: UIViewController {

    let vm = VM()

    override func viewDidLoad() {
        super.viewDidLoad()

        NSLog("[ViewController] viewDidLoad 开始")
        print("[ViewController] viewDidLoad 开始")

        // 添加运行测试按钮
        let testButton = UIButton(type: .system)
        testButton.setTitle("运行 ZTAPI 测试", for: .normal)
        testButton.translatesAutoresizingMaskIntoConstraints = false
        testButton.addTarget(self, action: #selector(runTests), for: .touchUpInside)
        view.addSubview(testButton)

        NSLayoutConstraint.activate([
            testButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            testButton.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])

        NSLog("[ViewController] 即将自动运行测试")
        // 自动运行测试
        runTests()
    }

    @objc func runTests() {
        NSLog("[ViewController] runTests 被调用")
        print("[ViewController] runTests 被调用")
        let tests = ZTAPITests()
        Task {
            NSLog("[ViewController] 开始运行测试套件")
            await tests.runAllTests()
            NSLog("[ViewController] 测试套件完成")
        }
    }
}


