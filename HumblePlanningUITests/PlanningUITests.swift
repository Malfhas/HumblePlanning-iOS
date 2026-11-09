import XCTest

/// The planning against the seeded company, like PlanningTest, FrenchTest and ColdStartTest of the Android app:
/// the four views and moving between days, weeks and months, the filters, the team grid, French, and what a
/// restart keeps.
///
/// Signs in as Emma Collins, site manager (every task right), who works on Monday and Tuesday ("Switchboard
/// replacement" with Liam, "Lighting retrofit" with Olivia) and on Thursday ("Fire alarm testing", "Client
/// meeting"). The Wednesday is a public holiday, "Armistice Day".
final class PlanningUITests: XCTestCase {
    private let emma = TestAccount.seeded("emma")

    override func setUpWithError() throws {
        try TestServer.require()
        continueAfterFailure = false
    }

    @MainActor
    func testDayWeekMonthAndMoving() throws {
        let ui = Driver(test: self, shots: TestServer.shots)
        let app = ui.app
        let days = PlanningDays()
        ui.launch(as: emma, "-planning_view", "Day")
        ui.expectSignedIn()

        // Day: today first, then the Monday of the seed with my two cards
        ui.expectVisible(ui.heading(days.long(days.today)))
        ui.tapDay(days.long(days.monday))
        ui.expectVisible(ui.heading(days.long(days.monday)))
        _ = ui.visibleCard("Switchboard replacement")
        _ = ui.visibleCard("Lighting retrofit")
        ui.shot("day")

        // A swipe goes to the next day, the strip to the holiday
        ui.heading(days.long(days.monday)).swipeLeft()
        ui.expectVisible(ui.heading(days.long(days.day(1))))
        ui.tapDay(days.long(days.holiday))
        ui.expectVisible(ui.heading(days.long(days.holiday)))
        ui.expectVisible(app.staticTexts[PlanningDays.spokenHolidayLabel].firstMatch)
        ui.shot("day-holiday")

        // A new task starts on the day shown, for me
        app.buttons["New task"].tap()
        let save = app.buttons["form.save"]
        ui.expect(save, timeout: 15)
        XCTAssertEqual(app.buttons["form.date.start"].value as? String, days.medium(days.holiday))
        XCTAssertTrue(app.buttons["form.people"].label.contains("Emma Collins"), app.buttons["form.people"].label)
        app.buttons["form.cancel"].tap()
        ui.expectGone(save)

        // Today comes back
        app.buttons["Today"].tap()
        ui.expectVisible(ui.heading(days.long(days.today)))

        // Week: its title, my cards (the project first), the holiday under its day; the next week and back
        ui.show("Week")
        ui.expectVisible(app.staticTexts[days.weekOf(days.monday)])
        _ = ui.visibleCard("Harbour View Offices")
        XCTAssertTrue(ui.any(containing: PlanningDays.holidayLabel).waitForExistence(timeout: 5), "The holiday under its Wednesday")
        ui.shot("week")
        app.staticTexts[days.weekOf(days.monday)].swipeLeft()
        ui.expectVisible(app.staticTexts[days.weekOf(days.day(7))])
        app.buttons["Today"].tap()
        ui.expectVisible(app.staticTexts[days.weekOf(days.monday)])

        // Month: a tapped day shows under the month, with its cards; the holiday too
        ui.show("Month")
        ui.tapDay(days.long(days.day(3)))
        ui.expectVisible(ui.heading(days.long(days.day(3))))
        ui.expect(ui.card("Fire alarm testing"))
        ui.expect(ui.card("Client meeting"))
        ui.shot("month-thursday")
        // The holiday cell is only tinted: VoiceOver says the holiday after the date
        let holidayCell = app.buttons[days.long(days.holiday)].firstMatch
        ui.tapDay(days.long(days.holiday))
        let spoken = holidayCell.value as? String ?? ""
        XCTAssertTrue(spoken.contains(PlanningDays.holidayLabel), "The holiday cell says: \(spoken)")
        ui.expect(ui.heading(days.long(days.holiday)))
        ui.expect(app.staticTexts[PlanningDays.spokenHolidayLabel].firstMatch)
        ui.expectGone(ui.cardIfAny("Fire alarm testing"))

        // The next month by a swipe, then back to today
        let chooseDate = app.buttons["Choose a date"]
        XCTAssertEqual(chooseDate.value as? String, days.month(days.today))
        holidayCell.swipeLeft()
        let nextMonth = days.month(Calendar.current.date(byAdding: .month, value: 1, to: days.today)!)
        ui.expect(app.buttons.matching(NSPredicate(format: "label == 'Choose a date' AND value == %@", nextMonth)).firstMatch)
        ui.shot("month-next")
        app.buttons["Today"].tap()
        ui.expect(app.buttons.matching(NSPredicate(format: "label == 'Choose a date' AND value == %@", days.month(days.today))).firstMatch)
        ui.expectVisible(ui.heading(days.long(days.today)))
    }

    @MainActor
    func testFiltersMeEveryonePickTeamsProjectsStatuses() throws {
        let ui = Driver(test: self, shots: TestServer.shots)
        let app = ui.app
        let days = PlanningDays()
        ui.launch(as: emma, "-planning_view", "Day")
        ui.expectSignedIn()
        ui.tapDay(days.long(days.monday))

        // Me (the default): my cards only
        _ = ui.visibleCard("Switchboard replacement")
        ui.expectAbsent(ui.cardIfAny("Boiler service"), "Ethan's task under Me")
        ui.expectAbsent(ui.cardIfAny("Bathroom fit-out"), "Ava's task under Me")
        XCTAssertEqual(ui.filterBadge, "")

        // Everyone
        ui.openFilters()
        app.segmentedControls.buttons["Everyone"].tap()
        ui.applyFilters()
        _ = ui.visibleCard("Bathroom fit-out")
        _ = ui.visibleCard("Switchboard replacement")
        XCTAssertEqual(ui.filterBadge, "", "Everyone is not counted")
        ui.shot("filter-everyone")

        // Pick: the list opens with me ticked; Ethan instead of me
        ui.openFilters()
        app.segmentedControls.buttons["Pick"].tap()
        let list = app.collectionViews["picker.list"]
        ui.expect(list)
        let me = list.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Emma Collins'")).firstMatch
        ui.expect(me)
        XCTAssertTrue(me.isSelected, "I am ticked first")
        XCTAssertEqual(ui.selectedCount(in: list), 1)
        ui.pick(["Ethan Price", "Emma Collins"])
        ui.expect(ui.any(containing: "1 person"))
        ui.shot("filter-pick")
        ui.applyFilters()
        _ = ui.visibleCard("Boiler service")
        ui.expectAbsent(ui.cardIfAny("Switchboard replacement"), "my task, not Ethan's")
        XCTAssertEqual(ui.filterBadge, "1")

        // A team: Plumbing (Ava, Ethan, Mia), everyone again
        ui.openFilters()
        app.buttons["Reset"].tap()
        app.segmentedControls.buttons["Everyone"].tap()
        ui.applyFilters()
        ui.filterOnly("All teams", ["Plumbing"])
        _ = ui.visibleCard("Bathroom fit-out")
        ui.expectAbsent(ui.cardIfAny("Switchboard replacement"), "Electrical team")
        XCTAssertEqual(ui.filterBadge, "1")
        ui.shot("filter-team")

        // A project instead: Harbour View Offices
        ui.openFilters()
        ui.toggle(app.switches["All teams"])
        ui.applyFilters()
        ui.filterOnly("All projects", ["[B26-014] Harbour View Offices"])
        _ = ui.visibleCard("Switchboard replacement")
        ui.expectAbsent(ui.cardIfAny("Bathroom fit-out"), "Maple Street School")
        XCTAssertEqual(ui.filterBadge, "1")

        // A status instead: In progress (Switchboard replacement and Bathroom fit-out)
        ui.openFilters()
        ui.toggle(app.switches["All projects"])
        ui.applyFilters()
        ui.filterOnly("All statuses", ["In progress"])
        _ = ui.visibleCard("Switchboard replacement")
        _ = ui.visibleCard("Bathroom fit-out")
        ui.expectAbsent(ui.cardIfAny("Lighting retrofit"), "Planned")
        ui.shot("filter-status")

        // Reset: back to my own cards
        ui.openFilters()
        app.buttons["Reset"].tap()
        ui.applyFilters()
        _ = ui.visibleCard("Lighting retrofit")
        ui.expectAbsent(ui.cardIfAny("Bathroom fit-out"), "Me again")
        XCTAssertEqual(ui.filterBadge, "")
    }

    @MainActor
    func testGridTeamsBarsScrollingAndCreateFromACell() throws {
        let server = try PlanningServer(self)
        let emmaId = try server.userId("emma")
        let ui = Driver(test: self, shots: TestServer.shots)
        let app = ui.app
        let days = PlanningDays()
        let title = testTitle("grid cell")
        server.removeAtEnd(titled: title, from: days.iso(days.monday), to: days.iso(days.day(6)))
        ui.launch(as: emma, "-planning_view", "Grid")
        ui.expectSignedIn()

        // The filter starts on Me: only my row, and everyone offered
        ui.expect(app.buttons["Show everyone"])
        ui.expect(ui.gridRow("Emma Collins"))
        XCTAssertFalse(ui.gridRow("Ava Morgan").exists, "Only my row")
        ui.shot("grid-me")
        app.buttons["Show everyone"].tap()

        // People by team, the holiday column, the bars
        for team in ["Carpentry", "Electrical", "Plumbing"] {
            ui.expect(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", team + ", ")).firstMatch)
        }
        ui.expect(ui.gridRow("Ava Morgan"))
        ui.expect(ui.gridRow("Chloe Ward"))
        ui.expect(ui.gridColumn("\(days.long(days.holiday)), \(PlanningDays.holidayLabel)"))
        ui.expect(app.otherElements["\(days.long(days.today)), Today"])
        ui.shot("grid-everyone")

        // A team folds and unfolds
        let carpentry = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Carpentry, '")).firstMatch
        carpentry.tap()
        ui.expectGone(ui.gridRow("Chloe Ward"))
        XCTAssertEqual(carpentry.value as? String, "Collapsed")
        carpentry.tap()
        ui.expect(ui.gridRow("Chloe Ward"))

        // A bar opens its task
        let bar = ui.card("Switchboard replacement, Emma Collins")
        bar.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        ui.expect(app.buttons["Edit"], timeout: 15)
        ui.expect(app.staticTexts["Switchboard replacement"].firstMatch)
        ui.back()

        // Scrolling: the later days come in from the right; Today brings the week back
        let monday = ui.gridColumn(days.long(days.monday))
        let later = ui.gridColumn(days.long(days.day(14)))
        ui.expect(later)
        let mondayX = monday.frame.minX
        let screenWidth = app.windows.firstMatch.frame.width
        XCTAssertGreaterThan(later.frame.minX, screenWidth, "Two weeks later is off screen first")
        for _ in 0..<4 where later.frame.maxX > screenWidth {
            app.otherElements["Ava Morgan"].swipeLeft()
        }
        XCTAssertLessThan(later.frame.maxX, screenWidth, "Two weeks later scrolled in")
        ui.shot("grid-scrolled")
        app.buttons["Today"].tap()
        ui.waitUntil("Today scrolls back") { abs(monday.frame.minX - mondayX) < 1 }

        // The next month and back
        app.buttons["Next month"].tap()
        let nextMonth = days.month(Calendar.current.date(byAdding: .month, value: 1, to: days.today)!)
        ui.expect(app.buttons.matching(NSPredicate(format: "label == 'Choose a date' AND value == %@", nextMonth)).firstMatch)
        app.buttons["Previous month"].tap()
        ui.expect(app.buttons.matching(NSPredicate(format: "label == 'Choose a date' AND value == %@", days.month(days.today))).firstMatch)
        app.buttons["Today"].tap()

        // An empty day of my row: the form opens on that day, for me; saved, its bar shows there
        let holiday = "\(days.long(days.holiday)), \(PlanningDays.holidayLabel)"
        ui.waitUntil("the grid back on this week") { abs(monday.frame.minX - mondayX) < 1 }
        ui.tapGrid(person: "Emma Collins", day: holiday)
        let save = app.buttons["form.save"]
        ui.expect(save, timeout: 15)
        XCTAssertEqual(app.buttons["form.date.start"].value as? String, days.medium(days.holiday))
        XCTAssertTrue(app.buttons["form.people"].label.contains("Emma Collins"), app.buttons["form.people"].label)
        ui.shot("grid-cell-form")
        app.buttons["form.project"].tap()
        let list = app.collectionViews["picker.list"]
        ui.expect(list)
        list.buttons.matching(NSPredicate(format: "label BEGINSWITH '[B26-031] Riverside Clinic'")).firstMatch.tap()
        let titleField = app.textFields["form.title"]
        titleField.tap()
        titleField.typeText(title + "\n")
        save.tap()
        ui.expectGone(save, timeout: 20)
        let created = ui.card(title)
        XCTAssertEqual(created.frame.midX, ui.gridColumn(holiday).frame.midX, accuracy: 1, "The bar is in the column of the holiday")
        ui.shot("grid-cell-saved")
        let saved = try server.tasks(from: days.iso(days.holiday), to: days.iso(days.holiday)).first { $0["title"] as? String == title }
        XCTAssertEqual(saved?["startDate"] as? String, days.iso(days.holiday))
        let people = (saved?["users"] as? [[String: Any]])?.compactMap { $0["id"] as? String }
        XCTAssertEqual(people, [emmaId])
    }

    @MainActor
    func testFrenchDatesAndLabels() throws {
        let ui = Driver(test: self, shots: TestServer.shots)
        let app = ui.app
        let days = PlanningDays(language: "fr")
        ui.launch(as: emma, language: "fr", "-planning_view", "Day")
        ui.expect(app.tabBars.buttons["Planning"], timeout: 30)

        // The planning: the day, the views, the month, the buttons
        ui.expectVisible(ui.heading(days.long(days.today)))
        for view in ["Jour", "Semaine", "Mois", "Grille"] { ui.expect(app.segmentedControls.buttons[view]) }
        ui.expect(app.buttons["Aujourd'hui"])
        ui.expect(app.buttons["Filtres"])
        XCTAssertEqual(app.buttons["Choisir une date"].value as? String, days.month(days.today))
        ui.tapDay(days.long(days.holiday))
        ui.expectVisible(ui.heading(days.long(days.holiday)))
        ui.shot("fr-day")

        // The week: its title and the weekday names
        ui.show("Semaine")
        ui.expectVisible(app.staticTexts[days.weekOf(days.monday)])
        ui.expect(app.staticTexts["Lundi"].firstMatch)
        ui.expect(app.staticTexts["Mercredi"].firstMatch)
        ui.shot("fr-week")

        // The form: its title and the date
        app.buttons["Nouvelle tâche"].tap()
        ui.expect(app.navigationBars["Nouvelle tâche"], timeout: 15)
        XCTAssertEqual(app.buttons["form.date.start"].value as? String, days.medium(days.holiday))
        ui.expect(ui.any(containing: "Projet"))
        ui.expect(app.buttons["Matin"])
        ui.shot("fr-form")
        app.buttons["form.cancel"].tap()
        ui.expectGone(app.buttons["form.save"])
    }

    @MainActor
    func testViewAndFilterKeptAfterRestart() throws {
        let ui = Driver(test: self, shots: TestServer.shots)
        let app = ui.app
        let days = PlanningDays()
        ui.launch(as: emma)
        ui.expectSignedIn()
        ui.expectVisible(ui.heading(days.long(days.today)))

        // Riverside Clinic only (my Thursday meeting), in the Week view
        ui.filterOnly("All projects", ["[B26-031] Riverside Clinic"])
        ui.show("Week")
        ui.expectVisible(app.staticTexts[days.weekOf(days.monday)])
        ui.expect(ui.card("Riverside Clinic"))
        ui.expectAbsent(ui.cardIfAny("Harbour View Offices"), "another project")
        ui.shot("before-restart")

        // Closed and opened again, without starting over: still signed in, same view and filter
        app.terminate()
        ui.launchSignedOut(keepState: true)
        ui.expectSignedIn()
        ui.waitSelected(app.segmentedControls.buttons["Week"])
        ui.expectVisible(app.staticTexts[days.weekOf(days.monday)])
        XCTAssertEqual(ui.filterBadge, "1")
        ui.expect(ui.card("Riverside Clinic"))
        ui.expectAbsent(ui.cardIfAny("Harbour View Offices"), "another project after the restart")
        ui.shot("after-restart")
    }
}
