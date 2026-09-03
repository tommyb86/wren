import Foundation
import SwiftData
import WrenCore

/// A recurring household cost. Deliberately has no reminder settings: bills are
/// an informative, reporting feature, so nothing here feeds the notification
/// scheduler.
@Model
final class Bill {
    var billID: UUID = UUID()
    var name: String = ""
    /// The expected amount, in cents. For variable bills this is an estimate,
    /// and the variance report is where the truth shows up.
    var amountCents: Int = 0
    var isVariableAmount: Bool = false
    var scheduleData: Data = Data()
    var category: String = ""
    /// Optional, for a shared household.
    var paidBy: String = ""
    /// Direct debit. Occurrences past their due date count as settled so there
    /// is nothing to tick — but no amount is ever invented for them.
    var paysAutomatically: Bool = false
    var isActive: Bool = true
    var sortOrder: Int = 0

    @Relationship(deleteRule: .cascade, inverse: \BillPayment.bill)
    var payments: [BillPayment]? = []

    init(
        billID: UUID = UUID(),
        name: String = "",
        amountCents: Int = 0,
        isVariableAmount: Bool = false,
        schedule: Schedule? = nil,
        category: String = "",
        paidBy: String = "",
        paysAutomatically: Bool = false,
        isActive: Bool = true,
        sortOrder: Int = 0
    ) {
        self.billID = billID
        self.name = name
        self.amountCents = amountCents
        self.isVariableAmount = isVariableAmount
        self.scheduleData = (try? schedule?.encoded()) ?? Data()
        self.category = category
        self.paidBy = paidBy
        self.paysAutomatically = paysAutomatically
        self.isActive = isActive
        self.sortOrder = sortOrder
        self.payments = []
    }
}

extension Bill {
    var schedule: Schedule? {
        guard !scheduleData.isEmpty else { return nil }
        return Schedule.lenientlyDecoded(from: scheduleData)
    }

    func apply(_ schedule: Schedule) {
        scheduleData = (try? schedule.encoded()) ?? Data()
    }

    /// Bridge into WrenCore, which knows nothing about SwiftData.
    var spec: BillSpec? {
        guard let schedule else { return nil }
        return BillSpec(
            id: billID,
            name: name,
            amountCents: amountCents,
            isVariableAmount: isVariableAmount,
            schedule: schedule,
            category: category,
            paidBy: paidBy,
            paysAutomatically: paysAutomatically,
            isActive: isActive
        )
    }

    var paymentRecords: [BillPaymentRecord] {
        (payments ?? []).map {
            BillPaymentRecord(
                billID: billID,
                amountCents: $0.amountCents,
                dueDate: $0.dueDate,
                paidAt: $0.paidAt
            )
        }
    }

    var monthlyEquivalentCents: Int {
        guard let schedule else { return 0 }
        return BillingPeriod.monthlyEquivalentCents(amountCents: amountCents, schedule: schedule)
    }

    var annualCents: Int {
        guard let schedule else { return 0 }
        return BillingPeriod.annualCents(amountCents: amountCents, schedule: schedule)
    }

    func nextDue(after date: Date = Date(), calendar: Calendar = .current) -> Date? {
        guard let schedule else { return nil }
        return ScheduleEngine.next(schedule, after: date, calendar: calendar)
    }
}

/// What was actually paid, against the occurrence it settles. Recording both the
/// expected amount on the bill and the actual amount here is what makes the
/// reports honest — the variance is the interesting signal.
@Model
final class BillPayment {
    var paidAt: Date = Date()
    /// What was ACTUALLY paid.
    var amountCents: Int = 0
    /// Which occurrence this settles.
    var dueDate: Date = Date()
    var bill: Bill?

    init(paidAt: Date = Date(), amountCents: Int = 0, dueDate: Date = Date(), bill: Bill? = nil) {
        self.paidAt = paidAt
        self.amountCents = amountCents
        self.dueDate = dueDate
        self.bill = bill
    }
}
