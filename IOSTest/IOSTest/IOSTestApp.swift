import SwiftUI
import Combine
import MyndCore

@MainActor
class AudioPlayerViewModel: ObservableObject {
    private let sdk: MyndSDK
    private var cancellables = Set<AnyCancellable>()

    // Categories and Playlists
    @Published var categories: [MyndCore.Category] = []
    @Published var selectedCategory: MyndCore.Category?
    @Published var playlists: [Playlist] = []
    @Published var isLoadingCategories = false
    @Published var isLoadingPlaylists = false
    @Published var isLoadingPlaylistDetails = false
    @Published var errorMessage: String?

    // Player State
    @Published var playbackState: PlaybackState = .idle
    @Published var progress: PlaybackProgress = PlaybackProgress(
        trackCurrentTime: 0,
        trackDuration: 0,
        trackIndex: 0,
        playlistCurrentTime: 0,
        playlistDuration: 0
    )
    @Published var currentSong: Song?
    @Published var currentPlaylist: PlaylistWithSongs?
    @Published var repeatMode: RepeatMode = .none
    @Published var volume: Float = 1.0

    init() {
        self.sdk = MyndSDK(authFunction: authFn)
        setupPlayerObservers()
    }

    private func setupPlayerObservers() {
        sdk.player.events
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                self?.handlePlayerEvent(event)
            }
            .store(in: &cancellables)
        self.volume = sdk.player.volume
    }

    private func handlePlayerEvent(_ event: AudioPlayerEvent) {
        switch event {
        case .stateChanged(let state):
            self.playbackState = state
            if case .playing(let song, _) = state {
                self.currentSong = song
            }
        case .progressUpdated(let progress):
            self.progress = progress
        case .playlistQueued(let playlist):
            self.currentPlaylist = playlist
        case .errorOccurred(let error):
            self.errorMessage = error.localizedDescription
        case .volumeChanged(let volume):
            self.volume = volume
        default:
            break
        }
    }

    func loadCategories() async {
        isLoadingCategories = true
        errorMessage = nil

        do {
            categories = try await sdk.catalogue.getCategories()
        } catch {
            errorMessage = "Failed to load categories: \(error.localizedDescription)"
        }

        isLoadingCategories = false
    }

    func selectCategory(_ category: MyndCore.Category) async {
        selectedCategory = category
        isLoadingPlaylists = true
        errorMessage = nil
        playlists = []

        do {
            playlists = try await sdk.catalogue.getPlaylists(categoryId: category.id)
            print("Loaded \(playlists.count) playlists for category: \(category.name)")
        } catch {
            errorMessage = "Failed to load playlists: \(error.localizedDescription)"
            print("Error loading playlists for category \(category.name): \(error)")
        }

        isLoadingPlaylists = false
    }

        func play(_ playlist: Playlist) async {
        isLoadingPlaylistDetails = true
        errorMessage = nil
        print("Loading playlist details for: \(playlist.name)")

        do {
            let playlistWithSongs = try await sdk.catalogue.getPlaylist(playlistId: playlist.id)
            print("Loaded playlist with \(playlistWithSongs.songs.count) songs: \(playlist.name)")
          await sdk.player.play(playlistWithSongs)
        } catch {
            errorMessage = "Failed to load playlist details: \(error.localizedDescription)"
            print("Error loading playlist details for \(playlist.name): \(error)")
        }

        isLoadingPlaylistDetails = false
    }

    func togglePlayPause() {
        if sdk.player.isPlaying {
            sdk.player.pause()
        } else {
            sdk.player.resume()
        }
    }

    func stop() async {
        await sdk.player.stop()
    }

    func toggleRepeatMode() {
        let newMode: RepeatMode = repeatMode == .none ? .all : .none
        repeatMode = newMode
        sdk.player.setRepeatMode(newMode)
        print("Repeat mode changed to: \(newMode)")
    }

    func setVolume(_ value: Float) {
        let clamped = min(max(value, 0.0), 1.0)
        sdk.player.setVolume(clamped)
        volume = clamped
        print("Set volume to \(clamped)")
    }
}

struct ContentView: View {
    @StateObject private var viewModel = AudioPlayerViewModel()

    var body: some View {
        NavigationView {
            VStack {
                if viewModel.isLoadingCategories {
                    ProgressView("Loading categories...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.categories.isEmpty {
                    VStack {
                        Text("No categories loaded")
                            .foregroundColor(.secondary)
                        Button("Load Categories") {
                            Task {
                                await viewModel.loadCategories()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    CategoryListView(viewModel: viewModel)
                }

                if viewModel.currentPlaylist != nil {
                    PlayerControlsView(viewModel: viewModel)
                        .padding()
                        .background(Color.gray.opacity(0.1))
                }
            }
            .navigationTitle("Mynd Audio")
            .onAppear {
                Task {
                    await viewModel.loadCategories()
                }
            }
        }
        .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") {
                viewModel.errorMessage = nil
            }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }
}

struct CategoryListView: View {
    @ObservedObject var viewModel: AudioPlayerViewModel

    var body: some View {
        List {
            Section("Categories") {
                ForEach(viewModel.categories, id: \.id) { category in
                    CategoryRow(category: category, isSelected: viewModel.selectedCategory?.id == category.id) {
                        Task {
                            await viewModel.selectCategory(category)
                        }
                    }
                }
            }

            if let selectedCategory = viewModel.selectedCategory {
                Section("Playlists in \(selectedCategory.name)") {
                    if viewModel.isLoadingPlaylists {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        ForEach(viewModel.playlists, id: \.id) { playlist in
                            PlaylistRow(
                                playlist: playlist,
                                isPlaying: viewModel.currentPlaylist?.playlist.id == playlist.id,
                                isLoadingDetails: viewModel.isLoadingPlaylistDetails
                            ) {
                                Task {
                                    await viewModel.play(playlist)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

struct CategoryRow: View {
    let category: MyndCore.Category
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(category.name)
                    .font(.headline)
            }

            Spacer()

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.accentColor)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}

struct PlaylistRow: View {
    let playlist: Playlist
    let isPlaying: Bool
    let isLoadingDetails: Bool
    let onTap: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(playlist.name)
                    .font(.headline)
                Text(playlist.description ?? "No description")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            if isLoadingDetails && !isPlaying {
                ProgressView()
                    .scaleEffect(0.8)
            } else if isPlaying {
                Image(systemName: "speaker.wave.3.fill")
                    .foregroundColor(.accentColor)
            } else {
                Image(systemName: "play.circle.fill")
                    .foregroundColor(.secondary)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if !isLoadingDetails {
                onTap()
            }
        }
        .opacity(isLoadingDetails && !isPlaying ? 0.6 : 1.0)
    }
}

struct PlayerControlsView: View {
    @ObservedObject var viewModel: AudioPlayerViewModel

    var body: some View {
        VStack(spacing: 12) {
            // Current Song Info
            if let song = viewModel.currentSong {
                VStack(spacing: 4) {
                    Text(song.name)
                        .font(.headline)
                        .lineLimit(1)
                    if let playlist = viewModel.currentPlaylist {
                        Text(playlist.playlist.name)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            // Progress Bar
            VStack(spacing: 4) {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(height: 4)

                        Rectangle()
                            .fill(Color.accentColor)
                            .frame(width: geometry.size.width * viewModel.progress.trackProgress, height: 4)
                    }
                }
                .frame(height: 4)

                HStack {
                    Text(formatTime(viewModel.progress.trackCurrentTime))
                        .font(.caption)
                        .monospacedDigit()

                    Spacer()

                    Text(formatTime(viewModel.progress.trackDuration))
                        .font(.caption)
                        .monospacedDigit()
                }
            }

            // Track Info
            HStack {
                Text("Track \(viewModel.progress.trackIndex + 1)")
                    .font(.caption)
                Spacer()
                Text("Playlist: \(formatTime(viewModel.progress.playlistCurrentTime)) / \(formatTime(viewModel.progress.playlistDuration))")
                    .font(.caption)
            }
            .foregroundColor(.secondary)

            // Playback Controls
            HStack(spacing: 20) {
                Button(action: {
                    Task {
                        await viewModel.stop()
                    }
                }) {
                    Image(systemName: "stop.fill")
                        .font(.title2)
                }

                Button(action: viewModel.togglePlayPause) {
                    Image(systemName: viewModel.playbackState.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title)
                }
                .buttonStyle(.borderedProminent)

                Button(action: viewModel.toggleRepeatMode) {
                    Image(systemName: viewModel.repeatMode == .none ? "repeat" : "repeat.1")
                        .font(.title2)
                        .foregroundColor(viewModel.repeatMode == .none ? .secondary : .accentColor)
                }
            }

            // State Display
            VStack(spacing: 2) {
                Text(stateDescription(viewModel.playbackState))
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("Repeat: \(repeatModeDescription(viewModel.repeatMode))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                HStack {
                    Text("Volume")
                    Slider(value: Binding(
                        get: { viewModel.volume },
                        set: { viewModel.setVolume($0) }
                    ), in: 0...1)
                    .frame(width: 120)
                    Text(String(format: "%d%%", Int(viewModel.volume * 100)))
                }
            }
        }
    }

    func formatTime(_ seconds: TimeInterval) -> String {
        guard !seconds.isNaN && !seconds.isInfinite else { return "--:--" }
        let minutes = Int(seconds) / 60
        let remainingSeconds = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }

    func stateDescription(_ state: PlaybackState) -> String {
        switch state {
        case .idle:
            return "Idle"
        case .playing(_, let index):
            return "Playing (Track \(index + 1))"
        case .paused(_, let index):
            return "Paused (Track \(index + 1))"
        case .stopped:
            return "Stopped"
        }
    }

    func repeatModeDescription(_ mode: RepeatMode) -> String {
        switch mode {
        case .none:
            return "Off"
        case .all:
            return "All"
        }
    }
}

extension PlaybackState {
    var isPlaying: Bool {
        if case .playing = self { return true }
        return false
    }
}

@main
struct IOSTestApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

// Preview
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
