import Foundation
import Testing
@testable import HumbleCore

/// `TaskFormTest` (tests 61, 62): validation, payload, and the form read from a task.
@Suite struct TaskFormTests {
    private let refs = References(config: ["AM_START": "07:30", "AM_END": "11:30", "PM_START": "13:00", "PM_END": "17:00"])

    private var valid: TaskForm {
        var form = TaskForm()
        form.projectId = "p"
        form.userIds = ["u"]
        form.statusId = "s"
        form.startDate = "2026-11-05"
        return form
    }

    private func with(_ change: (inout TaskForm) -> Void) -> TaskForm {
        var form = valid
        change(&form)
        return form
    }

    @Test func aCompleteFormIsValid() {
        #expect(valid.validationError == nil)
    }

    @Test func requiredFields() {
        #expect(with { $0.projectId = "" }.validationError == .projectRequired)
        #expect(with { $0.userIds = [] }.validationError == .usersRequired)
        #expect(with { $0.statusId = "" }.validationError == .statusRequired)
        #expect(with { $0.startDate = "" }.validationError == .startDateRequired)
    }

    @Test func endDateNotBeforeStart() {
        #expect(with { $0.endDate = "2026-11-04" }.validationError == .endDateBeforeStart)
        #expect(with { $0.endDate = "2026-11-06" }.validationError == nil)
        #expect(with { $0.endDate = "2026-11-05" }.validationError == nil)
    }

    @Test func timesEndAfterStartOnASingleDay() {
        #expect(with { $0.mode = .times }.validationError == .timesRequired)
        #expect(with { $0.mode = .times; $0.startTime = "12:00"; $0.endTime = "12:00" }.validationError == .endTimeBeforeStart)
        #expect(with { $0.mode = .times; $0.startTime = "12:00"; $0.endTime = "12:00"; $0.endDate = "2026-11-05" }.validationError
                == .endTimeBeforeStart)
        #expect(with { $0.mode = .times; $0.startTime = "9:00"; $0.endTime = "10:00" }.validationError == nil)
        #expect(with { $0.mode = .times; $0.startTime = "16:00"; $0.endTime = "08:00"; $0.endDate = "2026-11-06" }.validationError == nil)
        // Times left over from another mode are ignored
        #expect(with { $0.mode = .morning; $0.startTime = "bad" }.validationError == nil)
    }

    @Test func timesFollowTheTwentyFourHourPattern() {
        for good in ["0:00", "9:05", "09:05", "19:59", "23:59", "00:00"] { #expect(TaskForm.isTime(good), "\(good)") }
        for bad in ["", "24:00", "7:5", "12:60", "123:00", "12:000", "12-00", " 12:00", "12:00\n", "١٢:٠٠", "１２:００", "a:00"] {
            #expect(!TaskForm.isTime(bad), "\(bad)")
        }
    }

    @Test func textOfAtMost255Characters() {
        #expect(with { $0.title = String(repeating: "a", count: 255) }.validationError == nil)
        #expect(with { $0.title = String(repeating: "a", count: 256) }.validationError == .textTooLong)
        #expect(with { $0.placeText = String(repeating: "a", count: 256) }.validationError == .textTooLong)
        // Counted like the server (UTF-16): an emoji takes two
        #expect(with { $0.title = String(repeating: "😀", count: 128) }.validationError == .textTooLong)
    }

    @Test func linkIsAWebAddressOrEmpty() {
        #expect(with { $0.link = "not a link" }.validationError == .linkInvalid)
        #expect(with { $0.link = "javascript:alert(1)" }.validationError == .linkInvalid)
        #expect(with { $0.link = "https://example.com/a" }.validationError == nil)
        #expect(with { $0.link = "   " }.validationError == nil)
    }

    @Test func linksAcceptedLikeOkHttp() {
        for good in ["http://example.com", "HTTPS://Example.COM/A?b=c#d", "  https://example.com  ", "https://example",
                     "https://example.com:8443/x", "https://example.com:/x", "https://user:pw@example.com/x",
                     "https://example.com/a b", "https://café.fr", "http:example.com", "https://example.com.",
                     "https://[::1]:8080/", "https://my_host.example/", "https://ex#ample.com"] {
            #expect(WebLink.isValid(good.trimmingCharacters(in: .whitespaces)), "\(good)")
        }
        for bad in ["www.example.com", "ftp://example.com", "mailto:a@b.c", "http://", "https://", "https:///",
                    "https://exa mple.com", "https://example.com:99999", "https://example.com:0", "https://example.com:x",
                    "https://a..b", "https://exa%20mple.com", "http//example.com",
                    "https://" + String(repeating: "a", count: 64) + ".com", "javascript://alert(1)"] {
            #expect(!WebLink.isValid(bad), "\(bad)")
        }
    }

    @Test func recurrenceNeedsAnEndAfterTheStartAndAValidFrequency() {
        let repeating = with { $0.repeats = true; $0.recurEndDate = "2026-12-31" }
        #expect(repeating.validationError == nil)
        var form = repeating
        form.recurEndDate = ""
        #expect(form.validationError == .recurrenceEndRequired)
        form.recurEndDate = "2026-11-05"
        #expect(form.validationError == .recurrenceEndBeforeStart)
        form = repeating
        form.recurFrequency = 0
        #expect(form.validationError == .recurrenceFrequency)
        form.recurFrequency = 31
        #expect(form.validationError == .recurrenceFrequency)
        form.recurFrequency = 30
        #expect(form.validationError == nil)
        // Without the switch, the recurrence fields are not checked
        #expect(with { $0.recurEndDate = ""; $0.recurFrequency = 0 }.validationError == nil)
    }

    @Test func onlyTheFirstBrokenRuleIsReported() {
        var form = TaskForm()
        form.endDate = "2026-11-01"
        form.mode = .times
        form.startTime = "12:00"
        form.endTime = "11:00"
        form.title = String(repeating: "a", count: 300)
        form.link = "nope"
        form.repeats = true
        form.recurFrequency = 99
        var seen: [FormError] = []
        while let error = form.validationError {
            seen.append(error)
            switch error {
            case .projectRequired: form.projectId = "p"
            case .usersRequired: form.userIds = ["u"]
            case .statusRequired: form.statusId = "s"
            case .startDateRequired: form.startDate = "2026-11-05"
            case .endDateBeforeStart: form.endDate = ""
            case .timesRequired: Issue.record("times were valid")
            case .endTimeBeforeStart: form.endTime = "13:00"
            case .textTooLong: form.title = ""
            case .linkInvalid: form.link = ""
            case .recurrenceEndRequired: form.recurEndDate = "2026-11-05"
            case .recurrenceEndBeforeStart: form.recurEndDate = "2026-11-30"
            case .recurrenceFrequency: form.recurFrequency = 2
            }
        }
        #expect(seen == FormError.allCases.filter { $0 != .timesRequired })
    }

    @Test func errorsNameTheirMessageAndField() {
        #expect(FormError.allCases.map(\.rawValue) == [
            "val_project", "val_users", "val_status", "val_start", "val_end_before_start", "val_times", "val_end_time",
            "val_text_long", "val_link", "val_recur_end", "val_recur_end_before", "val_recur_frequency",
        ])
        #expect(FormError.projectRequired.field == .project && FormError.linkInvalid.field == .link)
        #expect(FormError.recurrenceFrequency.field == .frequency && FormError.endTimeBeforeStart.field == nil)
    }

    // MARK: Payload (test 62)

    @Test func allDayClearsTheTimes() {
        let payload = with { $0.startTime = "08:00"; $0.endTime = "09:00" }.payload(references: refs, canLock: false)
        #expect(payload.startTime == nil && payload.endTime == nil)
    }

    @Test func halfDaysUseTheHoursOfTheServer() {
        #expect(with { $0.mode = .morning }.payload(references: refs, canLock: false).startTime == "07:30")
        #expect(with { $0.mode = .morning }.payload(references: refs, canLock: false).endTime == "11:30")
        #expect(with { $0.mode = .afternoon }.payload(references: refs, canLock: false).startTime == "13:00")
        #expect(with { $0.mode = .afternoon }.payload(references: refs, canLock: false).endTime == "17:00")
        let defaults = with { $0.mode = .afternoon }.payload(references: References(), canLock: false)
        #expect(defaults.startTime == "14:00" && defaults.endTime == "17:00")
    }

    @Test func customTimesArePadded() {
        let payload = with { $0.mode = .times; $0.startTime = "9:00"; $0.endTime = "10:30" }.payload(references: refs, canLock: false)
        #expect(payload.startTime == "09:00" && payload.endTime == "10:30")
    }

    @Test func aSingleDayHasNoEndDate() {
        #expect(with { $0.endDate = "2026-11-05" }.payload(references: refs, canLock: false).endDate == nil)
        #expect(with { $0.endDate = "2026-11-06" }.payload(references: refs, canLock: false).endDate == "2026-11-06")
    }

    @Test func titleAndNotesGoOutEmptyAndTheOtherTextAsNull() {
        let payload = valid.payload(references: refs, canLock: false)
        #expect(payload.title == "" && payload.notes == "")
        #expect(payload.link == nil && payload.placeId == nil && payload.placeText == nil && payload.resourceId == nil)
        #expect(!payload.clearPlaceCoordinates && !payload.isMilestone)
        let typed = with {
            $0.title = "  Visit  "; $0.notes = " as typed "; $0.link = " https://x.example "; $0.placeText = " 1 rue A "
            $0.resourceId = "r"; $0.milestone = true
        }.payload(references: refs, canLock: false, placeTextChanged: true)
        #expect(typed.title == "Visit" && typed.notes == " as typed " && typed.link == "https://x.example")
        #expect(typed.placeText == "1 rue A" && typed.resourceId == "r" && typed.isMilestone && typed.clearPlaceCoordinates)
        #expect(typed.projectId == "p" && typed.userIds == ["u"] && typed.statusId == "s" && typed.startDate == "2026-11-05")
    }

    @Test func lockOnlyGoesOutWithTheRight() {
        #expect(with { $0.locked = true }.payload(references: refs, canLock: false).isLocked == nil)
        #expect(with { $0.locked = true }.payload(references: refs, canLock: true).isLocked == true)
        #expect(valid.payload(references: refs, canLock: true).isLocked == false)
    }

    @Test func theRepeatRequestCarriesTheRule() {
        let form = with { $0.repeats = true; $0.recurType = "daily"; $0.recurFrequency = 2; $0.recurEndDate = "2026-11-30"; $0.recurException = "include" }
        #expect(form.repeatRequest == RepeatRequest(recurType: "daily", recurFrequency: 2, recurEndDate: "2026-11-30", recurException: "include"))
        #expect(form.hasSameRule(as: form))
        #expect(!form.hasSameRule(as: valid))
    }

    // MARK: Read from a task

    @Test func aTaskWithoutStartTimeIsAllDay() {
        var source = task("t", "2026-11-05", "2026-11-05", title: "Visit", users: ["u1", "u2"])
        source.notes = "n"
        source.link = "https://x.example"
        source.placeId = "pl"
        source.placeText = "addr"
        source.resourceId = "r"
        source.isMilestone = true
        source.isLocked = true
        let form = TaskForm(task: source, references: refs)
        #expect(form.mode == .allDay && form.startTime == "" && form.endTime == "")
        #expect(form.endDate == "")
        #expect(form.projectId == "p1" && form.statusId == "s1" && form.userIds == ["u1", "u2"] && form.title == "Visit")
        #expect(form.notes == "n" && form.link == "https://x.example" && form.placeId == "pl" && form.placeText == "addr")
        #expect(form.resourceId == "r" && form.milestone && form.locked)
        #expect(!form.repeats && form.recurType == "weekly" && form.recurFrequency == 1 && form.recurEndDate == "" && form.recurException == "skip")
    }

    @Test func halfDaysAreRecognisedFromTheServerHours() {
        #expect(TaskForm(task: task("t", "2026-11-05", from: "07:30:00", to: "11:30:00"), references: refs).mode == .morning)
        #expect(TaskForm(task: task("t", "2026-11-05", from: "13:00:00", to: "17:00:00"), references: refs).mode == .afternoon)
        #expect(TaskForm(task: task("t", "2026-11-05", from: "8:00", to: "12:00:00"), references: References()).mode == .morning)
        let custom = TaskForm(task: task("t", "2026-11-05", "2026-11-07", from: "07:30:00", to: "12:00:00"), references: refs)
        #expect(custom.mode == .times && custom.startTime == "07:30" && custom.endTime == "12:00" && custom.endDate == "2026-11-07")
        let open = TaskForm(task: task("t", "2026-11-05", from: "09:15:00"), references: refs)
        #expect(open.mode == .times && open.startTime == "09:15" && open.endTime == "")
    }

    @Test func aSeriesRootRepeatsWithItsRule() {
        var root = task("root", "2026-11-05")
        root.parentId = "root"
        root.recurType = "monthly"
        root.recurFrequency = 3
        root.recurEndDate = "2027-11-05"
        root.recurException = "shift"
        let form = TaskForm(task: root, references: refs)
        #expect(form.repeats && form.recurType == "monthly" && form.recurFrequency == 3)
        #expect(form.recurEndDate == "2027-11-05" && form.recurException == "shift")
        var occurrence = root
        occurrence.id = "occ"
        #expect(!TaskForm(task: occurrence, references: refs).repeats)
    }

    // MARK: Edits

    @Test func editsMadeByTheScreen() {
        var form = with { $0.endDate = "2026-11-07" }
        form.setStartDate(day("2026-11-06"))
        #expect(form.startDate == "2026-11-06" && form.endDate == "2026-11-07")
        form.setStartDate(day("2026-11-08"))
        #expect(form.endDate == "")
        form.setEndDate(day("2026-11-08"))
        #expect(form.endDate == "")
        form.setEndDate(day("2026-11-10"))
        #expect(form.endDate == "2026-11-10")
        form.setEndDate(nil)
        #expect(form.endDate == "")
        form.setRecurrenceEnd(day("2026-12-31"))
        #expect(form.recurEndDate == "2026-12-31")

        form.setPlace("pl")
        form.setPlaceText("  ")
        #expect(form.placeId == "pl" && form.placeText == "  ")
        form.setPlaceText("1 rue A")
        #expect(form.placeId == "" && form.placeText == "1 rue A")
        form.setPlace("pl")
        #expect(form.placeId == "pl" && form.placeText == "")
        form.setPlace(nil)
        #expect(form.placeId == "")

        form.setTitle(String(repeating: "a", count: 300))
        #expect(form.title.count == 255)
        form.setTitle(String(repeating: "😀", count: 200))
        #expect(form.title.utf16.count == 254)

        form.frequencyText = "1a2b3"
        #expect(form.recurFrequency == 12 && form.frequencyText == "12")
        form.frequencyText = ""
        #expect(form.recurFrequency == 0 && form.frequencyText == "")

        form.setTime(.start, hour: 7, minute: 5)
        form.setTime(.end, hour: 18, minute: 30)
        #expect(form.startTime == "07:05" && form.endTime == "18:30")
    }

    @Test func pickersOpenOnTheValueOrASensibleDefault() {
        var form = valid
        #expect(form.timePickerStart(.start, references: refs) == (7, 30))
        #expect(form.timePickerStart(.end, references: refs) == (11, 30))
        #expect(form.timePickerStart(.start, references: References(config: ["AM_START": "bad"])) == (8, 0))
        form.startTime = "9:45"
        #expect(form.timePickerStart(.start, references: refs) == (9, 45))
        form.endTime = "25:99"
        #expect(form.timePickerStart(.end, references: refs) == (23, 59))
        let today = day("2026-11-09")
        #expect(form.datePickerStart(.start, today: today) == day("2026-11-05"))
        #expect(form.datePickerStart(.end, today: today) == day("2026-11-05"))
        #expect(form.datePickerStart(.recurrenceEnd, today: today) == day("2026-11-05"))
        form.endDate = "2026-11-07"
        #expect(form.datePickerStart(.end, today: today) == day("2026-11-07"))
        #expect(TaskForm().datePickerStart(.start, today: today) == today)
    }

    @Test func theFormIsKeptAsJSON() throws {
        let form = with { $0.mode = .afternoon; $0.repeats = true; $0.userIds = ["a", "b"] }
        let data = try JSONEncoder().encode(TaskFormDraft(form: form, initial: TaskForm(), createdId: "new"))
        let back = try JSONDecoder().decode(TaskFormDraft.self, from: data)
        #expect(back.form == form && back.initial == TaskForm() && back.createdId == "new")
    }
}
