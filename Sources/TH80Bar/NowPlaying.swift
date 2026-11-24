import AppKit

/// Lê a música atual do Spotify ou do app Música via AppleScript (só se o app já estiver aberto).
enum NowPlaying {
    struct Track {
        var title: String
        var artist: String
        var artwork: CGImage?
    }

    enum NowPlayingError: LocalizedError {
        case nothingPlaying, denied(String)
        var errorDescription: String? {
            switch self {
            case .nothingPlaying: "Nenhuma música tocando no Spotify ou no app Música."
            case .denied(let app): "Permita o TH80 Bar controlar o \(app) em Ajustes do Sistema › Privacidade › Automação."
            }
        }
    }

    static func current() async throws -> Track {
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        if running.contains("com.spotify.client"), let t = try await spotify() { return t }
        if running.contains("com.apple.Music"), let t = try music() { return t }
        throw NowPlayingError.nothingPlaying
    }

    private static func run(_ source: String, app: String) throws -> NSAppleEventDescriptor? {
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error, (error[NSAppleScript.errorNumber] as? Int) == -1743 { throw NowPlayingError.denied(app) }
        return error == nil ? result : nil
    }

    private static func spotify() async throws -> Track? {
        let script = """
        tell application "Spotify"
            if player state is stopped then return ""
            return (name of current track) & "\\n" & (artist of current track) & "\\n" & (artwork url of current track)
        end tell
        """
        guard let parts = try run(script, app: "Spotify")?.stringValue?.components(separatedBy: "\n"), parts.count >= 3,
              !parts[0].isEmpty else { return nil }
        var art: CGImage?
        if let url = URL(string: parts[2]), let (data, _) = try? await URLSession.shared.data(from: url),
           let img = NSImage(data: data) {
            art = img.cgImage(forProposedRect: nil, context: nil, hints: nil)
        }
        return Track(title: parts[0], artist: parts[1], artwork: art)
    }

    private static func music() throws -> Track? {
        let info = """
        tell application "Music"
            if player state is stopped then return ""
            return (name of current track) & "\\n" & (artist of current track)
        end tell
        """
        guard let parts = try run(info, app: "Música")?.stringValue?.components(separatedBy: "\n"), parts.count >= 2,
              !parts[0].isEmpty else { return nil }
        let artScript = "tell application \"Music\" to get raw data of artwork 1 of current track"
        let data = (try? run(artScript, app: "Música"))?.flatMap { $0.data }
        let art = data.flatMap { NSImage(data: $0) }?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        return Track(title: parts[0], artist: parts[1], artwork: art)
    }
}
