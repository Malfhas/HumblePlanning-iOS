import XCTest

/// The task screens driven end to end against a real server, like the instrumented tests of the Android app:
/// create (with the validation), edit a series, duplicate, attachments, and the three ways to delete.
///
/// Signs in as Emma Collins, site manager of the seeded company (see `TestServer`). Every task it creates is titled
/// "[iOS test] …" and deleted by the test itself.
final class TaskFlowUITests: XCTestCase {
    @MainActor
    func testCreateEditDuplicateAttachDelete() throws {
        try TestServer.require()
        continueAfterFailure = false
        let ui = Driver(test: self, shots: TestServer.shots)
        let app = ui.app
        let title = "[iOS test] \(Int(Date().timeIntervalSince1970) % 1_000_000)"
        let edited = title + " edited"
        let copy = title + " copy"

        // A new task: refused without a project
        ui.launch(as: .seeded("emma"), "-HPOpenForm", "create")
        let save = app.buttons["form.save"]
        ui.expect(save, timeout: 20)
        ui.shot("form-new")
        save.tap()
        ui.expect(app.staticTexts["Choose a project."])
        ui.shot("form-refused")

        // The first project, the account (by default) and someone else
        app.buttons["form.project"].tap()
        let list = app.collectionViews["picker.list"]
        ui.expect(list)
        list.buttons.element(boundBy: 0).tap()
        app.buttons["form.people"].tap()
        ui.expect(list)
        XCTAssertEqual(ui.selectedCount(in: list), 1, "The account is the default person")
        let other = ui.selectFirstUnselected(in: list)
        app.buttons["picker.done"].tap()
        XCTAssertTrue(app.buttons["form.people"].label.contains("2"), app.buttons["form.people"].label)

        // Title, the morning, every week for two weeks
        let titleField = app.textFields["form.title"]
        titleField.tap()
        titleField.typeText(title + "\n")
        app.buttons["Morning"].tap()
        let repeats = app.switches["form.repeat"]
        ui.scroll(to: repeats)
        ui.toggle(repeats)
        app.buttons["Weekly"].tap()
        let until = app.buttons["form.date.recurrenceEnd"]
        ui.scroll(to: until)
        until.tap()
        ui.pickDay(Calendar.current.date(byAdding: .day, value: 14, to: Date())!)
        ui.shot("form-filled")
        save.tap()
        ui.expectGone(save, timeout: 20)

        // The series: the account's own tasks of the coming days
        app.tabBars.buttons["Upcoming"].tap()
        ui.card(title).tap()
        ui.expect(ui.any(containing: "Every week"))
        ui.expect(app.staticTexts[other])
        ui.shot("detail-series")

        // Edit the whole series; closing first asks before dropping the change
        app.buttons["Edit"].tap()
        ui.expect(save, timeout: 15)
        ui.replaceText(of: titleField, with: edited)
        // iOS 26 shows the question in a popover from the button, where tapping outside keeps editing
        app.buttons["form.cancel"].tap()
        ui.expect(app.buttons["Discard"])
        ui.shot("form-discard")
        ui.dismissPopover()
        ui.expectGone(app.buttons["Discard"])
        XCTAssertEqual(titleField.value as? String, edited)
        let applyToAll = app.switches["form.applyToAll"]
        ui.scroll(to: applyToAll)
        ui.toggle(applyToAll)
        save.tap()
        ui.expectGone(save, timeout: 20)
        ui.expect(app.staticTexts[edited], timeout: 15)
        app.navigationBars.buttons.element(boundBy: 0).tap()

        // The next occurrence: duplicated (a single task for the same two people), then deleted alone
        ui.card(edited, index: 1).tap()
        ui.expect(ui.any(containing: "Part of a series"))
        ui.shot("detail-occurrence")
        app.buttons["detail.more"].tap()
        app.buttons["Duplicate"].tap()
        ui.expect(app.navigationBars["Copy of the task"], timeout: 15)
        ui.replaceText(of: titleField, with: copy)
        ui.shot("form-copy")
        save.tap()
        ui.expectGone(save, timeout: 20)
        ui.delete(choice: "This occurrence", shot: "delete-series")

        // Attachments on the copy: a photo of the library, opened, then deleted
        ui.card(copy).tap()
        ui.expect(app.staticTexts["No attachment"], timeout: 15)
        let addFile = app.buttons["detail.addFile"]
        ui.scroll(to: addFile)
        addFile.tap()
        ui.expect(app.buttons["Choose a photo"])
        ui.shot("add-file-menu")
        app.buttons["Choose a photo"].tap()
        let photo = app.images.matching(NSPredicate(format: "label BEGINSWITH 'Photo'")).firstMatch
        ui.expect(photo, timeout: 20)
        ui.shot("photo-picker")
        photo.tap()
        ui.expectGone(app.staticTexts["No attachment"], timeout: 30)
        let deleteFile = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Delete '")).firstMatch
        ui.expect(deleteFile, timeout: 15)
        ui.shot("detail-attachment")
        let fileName = String(deleteFile.label.dropFirst("Delete ".count))
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", fileName)).firstMatch.tap()
        // Quick Look hides its bar once the photo is shown: a tap on the photo brings it back, its first
        // button closes the preview. The bar can hide between the two, hence a few tries.
        let preview = app.otherElements["QLPreviewControllerView"]
        ui.expect(preview, timeout: 20)
        sleep(2)
        ui.shot("attachment-preview")
        let close = preview.buttons.element(boundBy: 0)
        for _ in 0..<3 where preview.exists {
            if !(close.exists && close.isHittable) { preview.tap() }
            if close.waitForExistence(timeout: 2) && close.isHittable { close.tap() }
            _ = preview.waitForNonExistence(timeout: 4)
        }
        ui.expectGone(preview, timeout: 5)
        ui.waitHittable(app.buttons["detail.more"], true, timeout: 10)
        deleteFile.tap()
        ui.expect(app.staticTexts["Delete this file?"])
        app.buttons["Delete"].tap()
        ui.expect(app.staticTexts["No attachment"], timeout: 15)

        // Several people: one leaves, then the task goes
        app.buttons["detail.more"].tap()
        app.buttons["Delete"].tap()
        ui.expect(app.buttons["Remove one person"])
        ui.shot("delete-shared")
        app.buttons["Remove one person"].tap()
        ui.expect(app.buttons[other])
        app.buttons[other].tap()
        ui.expectGone(app.staticTexts[other], timeout: 15)
        ui.delete(choice: "Delete", shot: "delete-single")

        // The rest of the series, from its first task
        ui.card(edited).tap()
        ui.expect(ui.any(containing: "Every week"))
        ui.delete(choice: "Whole series", shot: nil)
        XCTAssertFalse(ui.cardIfAny(title).waitForExistence(timeout: 5), "Every test task is deleted")
    }
}
