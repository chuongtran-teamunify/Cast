//
//  UIControl+RxTests.swift
//  RxTests
//
//  Created by Ash Furrow on 2015-07-04.
//
//

import UIKit
import RxSwift
import RxCocoa
import XCTest

class UIControlRxTests : RxTest {
    func testSubscribeEnabledToTrue() {
        let subject = UIControl()
        let enabledSequence = Variable<Bool>(false)
        let disposable = enabledSequence.subscribeEnabledOf(subject)

        enabledSequence.sendNext(true)
        XCTAssert(subject.enabled == true, "Expected enabled set to true")
    }

    func testSubscribeEnabledToFalse() {
        let subject = UIControl()
        let enabledSequence = Variable<Bool>(true)
        let disposable = enabledSequence.subscribeEnabledOf(subject)

        enabledSequence.sendNext(false)
        XCTAssert(subject.enabled == false, "Expected enabled set to false")
    }
}
