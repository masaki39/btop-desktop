import AppKit
import SwiftTerm

/// Runs btop inside a LocalProcessTerminalView and restarts it automatically if it exits.
@MainActor
final class BtopRunner: NSObject, LocalProcessTerminalViewDelegate {
    let terminalView: LocalProcessTerminalView
    private let btopPath: String

    private var shouldRun = false
    private var immediateRestart = false
    private var startedAt = Date.distantPast
    private var restartDelay: TimeInterval = 1
    private var pendingRestart: DispatchWorkItem?

    /// Current terminal size, computed by SwiftTerm from the view size and font.
    private(set) var cols = 0
    private(set) var rows = 0

    init(btopPath: String, frame: NSRect) {
        self.btopPath = btopPath
        terminalView = LocalProcessTerminalView(frame: frame)
        super.init()
        terminalView.processDelegate = self
        terminalView.nativeForegroundColor = NSColor(white: 0.9, alpha: 1)
        // Keep the terminal default background fully clear; opacity is drawn by the container.
        terminalView.nativeBackgroundColor = NSColor(white: 0, alpha: 0)
        terminalView.scrollerStyle = .overlay
        terminalView.optionAsMetaKey = false
    }

    var isRunning: Bool { terminalView.process?.running ?? false }

    func start() {
        shouldRun = true
        launchIfNeeded()
    }

    func stop() {
        shouldRun = false
        immediateRestart = false
        pendingRestart?.cancel()
        pendingRestart = nil
        if isRunning { terminalView.terminate() }
    }

    /// Restart to pick up configuration changes.
    func restart() {
        shouldRun = true
        pendingRestart?.cancel()
        restartDelay = 1
        if isRunning {
            immediateRestart = true
            terminalView.terminate()
        } else {
            launchIfNeeded()
        }
    }

    /// On app quit: send SIGTERM to btop, then SIGKILL if it has not exited shortly after.
    func terminateForQuit() {
        shouldRun = false
        pendingRestart?.cancel()
        guard isRunning, let pid = terminalView.process?.shellPid, pid > 0 else { return }
        kill(pid, SIGTERM)
        let deadline = Date().addingTimeInterval(1.0)
        while Date() < deadline {
            if kill(pid, 0) != 0 { return }
            usleep(20_000)
        }
        kill(pid, SIGKILL)
    }

    /// Re-measures the terminal for the current screen and makes sure btop sees the size.
    ///
    /// Reassigning the font recomputes the cell size for the current backing scale and resizes
    /// the terminal from the current view frame, which also pushes the size to the pty.
    /// SIGWINCH then makes btop re-read the size; btop ignores it if nothing changed.
    func resyncSize() {
        terminalView.font = terminalView.font
        // The resize soft-resets the terminal, which would show the cursor again.
        terminalView.feed(text: "\u{1b}[?25l")
        if isRunning, let pid = terminalView.process?.shellPid, pid > 0 {
            kill(pid, SIGWINCH)
        }
    }

    private func launchIfNeeded() {
        guard shouldRun, !isRunning else { return }
        // Clear leftovers from the previous run. Do not use RIS (ESC c): it also resets the terminal size.
        terminalView.feed(text: "\u{1b}[0m\u{1b}[2J\u{1b}[3J\u{1b}[H")
        startedAt = Date()
        terminalView.startProcess(
            executable: btopPath,
            args: [],
            environment: BtopEnvironment.processEnvironment(),
            execName: "btop",
            currentDirectory: NSHomeDirectory()
        )
    }

    private func scheduleRestart() {
        // A late termination callback can arrive after a new btop was already launched
        // (e.g. a quick hide/show). Ignore it in that case.
        guard shouldRun, !isRunning else { return }
        let delay: TimeInterval
        if immediateRestart {
            immediateRestart = false
            delay = 0.2
        } else {
            // Exponential backoff (up to 30 s) if btop keeps exiting right away.
            let lived = Date().timeIntervalSince(startedAt)
            if lived > 10 { restartDelay = 1 }
            delay = restartDelay
            restartDelay = min(restartDelay * 2, 30)
            terminalView.feed(text: "\r\n\u{1b}[33mbtop exited. Restarting in \(Int(delay))s...\u{1b}[0m\r\n")
        }
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.launchIfNeeded() }
        }
        pendingRestart = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    // MARK: - LocalProcessTerminalViewDelegate

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {
        // LocalProcessTerminalView computes rows/columns from the view size and sends TIOCSWINSZ
        // to the pty; btop receives SIGWINCH and re-lays itself out.
        cols = newCols
        rows = newRows
    }

    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        scheduleRestart()
    }

    /// No processTerminated callback follows a launch failure, so retry from here.
    func processFailedToStart(source: TerminalView, error: LocalProcessError) {
        scheduleRestart()
    }
}
