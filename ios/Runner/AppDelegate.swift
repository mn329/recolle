import Flutter
import MusicKit
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    if let registrar = registrar(forPlugin: "AppleMusicPlaylistChannel") {
      AppleMusicPlaylistChannel.register(with: registrar.messenger())
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}

/// Apple Music のライブラリにプレイリストを作る。Dart 側は `AppleMusicPlaylistService`。
///
/// MusicKit は開発者トークンを自動で発行するため、キーをアプリに埋め込む必要はない
/// （Apple Developer の App ID で MusicKit を有効にしておく）。
enum AppleMusicPlaylistChannel {
  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "recolle/apple_music", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      guard call.method == "createPlaylist" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard
        let args = call.arguments as? [String: Any],
        let name = args["name"] as? String,
        let songIds = args["songIds"] as? [String],
        !name.isEmpty, !songIds.isEmpty
      else {
        result(FlutterError(code: "invalid_arguments", message: nil, details: nil))
        return
      }
      let description = args["description"] as? String
      guard #available(iOS 16.0, *) else {
        result(FlutterError(code: "unsupported_os", message: nil, details: nil))
        return
      }
      Task {
        let reply: Any
        do {
          reply = try await createPlaylist(name: name, description: description, songIds: songIds)
        } catch let error as PlaylistError {
          reply = FlutterError(code: error.rawValue, message: nil, details: nil)
        } catch {
          reply = FlutterError(code: "failed", message: error.localizedDescription, details: nil)
        }
        await MainActor.run { result(reply) }
      }
    }
  }

  private enum PlaylistError: String, Error {
    case denied
    case noSubscription = "no_subscription"
    case notFound = "not_found"
  }

  @available(iOS 16.0, *)
  private static func createPlaylist(
    name: String,
    description: String?,
    songIds: [String]
  ) async throws -> [String: Any] {
    guard await MusicAuthorization.request() == .authorized else {
      throw PlaylistError.denied
    }
    // カタログの曲をライブラリのプレイリストに入れるには、クラウドライブラリ（Apple Music 加入）が要る
    guard try await MusicSubscription.current.hasCloudLibraryEnabled else {
      throw PlaylistError.noSubscription
    }

    let ids = songIds.map { MusicItemID($0) }
    let request = MusicCatalogResourceRequest<Song>(matching: \.id, memberOf: Array(Set(ids)))
    let response = try await request.response()
    let songsById = Dictionary(
      response.items.map { ($0.id, $0) },
      uniquingKeysWith: { first, _ in first }
    )
    // セトリの順番（同じ曲が 2 回あればそのまま）で並べる
    let songs = ids.compactMap { songsById[$0] }
    guard !songs.isEmpty else { throw PlaylistError.notFound }

    let playlist = try await MusicLibrary.shared.createPlaylist(
      name: name,
      description: description,
      items: songs
    )
    var reply: [String: Any] = [:]
    if let url = playlist.url { reply["url"] = url.absoluteString }
    return reply
  }
}
