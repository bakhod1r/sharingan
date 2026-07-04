import Foundation

@MainActor
public protocol BreakPresenter: AnyObject {
    func presentBreak(timer: PomodoroTimer, onTapSkip: @escaping () -> Void)
    func dismissAll()
}