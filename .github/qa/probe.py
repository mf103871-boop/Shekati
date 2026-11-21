"""Use the candidate's normal persistent store and synchronize the QA taps with the visible sheet."""
from pathlib import Path

p = Path("ShekatiUITests/EnhancementUITests.swift")
src = p.read_text()
def substitute(old, new):
    global src
    if src.count(old) != 1:
        raise ValueError(old)
    src = src.replace(old, new)

substitute('app.launchArguments = ["--ui-testing"] + (arabic ? ["--arabic"] : [])',
           'app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-language", "en", "-reminderOffsets", "()"]')
substitute('''        recordBankSettlement(in: app)
        nativeTab(.home, in: app).tap()
        let updated''', '''        recordBankSettlement(in: app)
        let paid = app.descendants(matching: .any).matching(NSPredicate(
            format: "label CONTAINS %@ AND label CONTAINS %@", "Amount paid", "125.50")).firstMatch
        XCTAssertTrue(paid.waitForExistence(timeout: 15), app.debugDescription)
        let reviewSheet = app.buttons["reviewOperation"]
        let home = nativeTab(.home, in: app)
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            !reviewSheet.exists && home.exists && home.isHittable
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 15), .completed, app.debugDescription)
        func evidence(_ name: String) {
            let ax = XCTAttachment(string: app.debugDescription)
            ax.name = name + " accessibility"; ax.lifetime = .keepAlways; add(ax)
            attachNativeScreenshot(in: app, name: name)
        }
        evidence("iOS 17.5 settled cheque")
        home.tap()
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            home.isSelected && balance.exists
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 12), .completed, app.debugDescription)
        evidence("iOS 17.5 recorded balance")
        let updated''')
substitute('''        XCTAssertTrue(cheque.label.contains("Settled"))
    }

    func testPrimarySettlement''', '''        XCTAssertTrue(cheque.label.contains("Settled"))
        XCTAssertTrue(nativeTab(.calendar, in: app).isSelected)
        evidence("iOS 17.5 calendar")
    }

    func testPrimarySettlement''')
p.write_text(src)
