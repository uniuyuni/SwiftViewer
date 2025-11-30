import SwiftUI
import AVKit

struct VideoPlayerView: NSViewRepresentable {
    let url: URL
    
    func makeNSView(context: Context) -> AVPlayerView {
        let playerView = AVPlayerView()
        playerView.controlsStyle = .inline
        playerView.player = AVPlayer(url: url)
        playerView.player?.play()
        return playerView
    }
    
    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        // Check if URL changed
        if let currentAsset = nsView.player?.currentItem?.asset as? AVURLAsset,
           currentAsset.url == url {
            return
        }
        
        nsView.player?.pause()
        nsView.player = AVPlayer(url: url)
        nsView.player?.play()
    }
    
    static func dismantleNSView(_ nsView: AVPlayerView, coordinator: ()) {
        nsView.player?.pause()
        nsView.player = nil
    }
}
