import SwiftUI

/// The transient "done, undo?" strip. Floats above a list with a deeper
/// shadow than anything else on the screen, since it is the one thing that
/// moves. Callers own the timer and the state; this only draws.
struct WrenUndoBanner: View {
    let title: String
    let detail: String
    let undo: () -> Void

    var body: some View {
        HStack(spacing: Space.m) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(WrenFont.value)
                    .foregroundStyle(Color.wren.textPrimary)
                    .lineLimit(1)
                Text(detail)
                    .font(WrenFont.detail)
                    .foregroundStyle(Color.wren.textSecondary)
            }
            Spacer()
            Button("Undo", action: undo)
                .buttonStyle(WrenCompactButtonStyle())
        }
        .padding(.vertical, Space.s + 2)
        .padding(.horizontal, Space.m)
        .wrenBox()
        .wrenHardShadow(offset: 3)
        .padding(Space.l)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

/// A completed task waiting for its undo window to close.
struct SettledTask: Equatable {
    let taskID: UUID
    let title: String
    let due: Date

    var detail: String {
        "Settled \(due.formatted(.dateTime.weekday(.abbreviated).day().month()))"
    }
}
