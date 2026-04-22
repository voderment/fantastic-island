import Foundation

struct PlayerPreviewPanelModel {
    let title: String
    let artist: String
    let isIdle: Bool
}

enum PlayerPreviewMocks {
    static let playing = PlayerPreviewPanelModel(
        title: "Shelter",
        artist: "Porter Robinson & Madeon",
        isIdle: false
    )

    static let idle = PlayerPreviewPanelModel(
        title: "Nothing Playing",
        artist: "Select a default source to control playback.",
        isIdle: true
    )

    static let peekTitle = "New Track"
    static let peekArtist = "Preview Artist"
}
