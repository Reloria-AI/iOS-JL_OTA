import Foundation
import UIKit

struct GlassesFileEntry: Equatable {
    enum MediaType {
        case image
        case video
        case unknown
    }

    let path: String
    let mediaType: MediaType

    var fileName: String {
        URL(fileURLWithPath: path).lastPathComponent
    }
}

enum GlassesHTTPError: LocalizedError {
    case invalidURL
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "URL 无效"
        case .emptyResponse:
            return "设备返回为空"
        }
    }
}

final class GlassesHTTPClient {
    static let shared = GlassesHTTPClient()

    private let session: URLSession

    private init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 12
        configuration.timeoutIntervalForResource = 20
        session = URLSession(configuration: configuration)
    }

    func fetchFileList(mode: GlassesWiFiMode, completion: @escaping (Result<String, Error>) -> Void) {
        performTextRequest(urlString: "http://\(mode.host)/?custom=1&cmd=3015", completion: completion)
    }

    func fetchFileEntries(mode: GlassesWiFiMode, completion: @escaping (Result<[GlassesFileEntry], Error>) -> Void) {
        fetchFileList(mode: mode) { result in
            switch result {
            case .success(let text):
                completion(.success(Self.parseFileEntries(from: text)))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    func syncDateTime(mode: GlassesWiFiMode, date: Date, completion: @escaping (Result<String, Error>) -> Void) {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")

        formatter.dateFormat = "yyyy-MM-dd"
        let dateString = formatter.string(from: date)

        formatter.dateFormat = "HH:mm:ss"
        let timeString = formatter.string(from: date)

        let group = DispatchGroup()
        let lock = NSLock()
        var firstError: Error?
        var responses: [String] = []

        group.enter()
        performTextRequest(urlString: "http://\(mode.host)/?custom=1&cmd=3005&str=\(dateString)") { result in
            lock.lock()
            switch result {
            case .success(let response):
                responses.append("date=\(response)")
            case .failure(let error):
                firstError = error
            }
            lock.unlock()
            group.leave()
        }

        group.enter()
        performTextRequest(urlString: "http://\(mode.host)/?custom=1&cmd=3006&str=\(timeString)") { result in
            lock.lock()
            switch result {
            case .success(let response):
                responses.append("time=\(response)")
            case .failure(let error):
                firstError = error
            }
            lock.unlock()
            group.leave()
        }

        group.notify(queue: .main) {
            if let firstError {
                completion(.failure(firstError))
            } else {
                completion(.success(responses.joined(separator: "\n")))
            }
        }
    }

    func downloadThumbnail(relativePath: String, mode: GlassesWiFiMode, completion: @escaping (Result<String, Error>) -> Void) {
        let path = relativePath.hasPrefix("/") ? relativePath : "/\(relativePath)"
        performTextRequest(urlString: "http://\(mode.host)\(path)?custom=1&cmd=4001", completion: completion)
    }

    func downloadThumbnailImage(relativePath: String, mode: GlassesWiFiMode, completion: @escaping (Result<UIImage, Error>) -> Void) {
        let path = relativePath.hasPrefix("/") ? relativePath : "/\(relativePath)"
        performDataRequest(urlString: "http://\(mode.host)\(path)?custom=1&cmd=4001") { result in
            switch result {
            case .success(let data):
                if let image = UIImage(data: data) {
                    completion(.success(image))
                } else {
                    completion(.failure(GlassesHTTPError.emptyResponse))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    func downloadImage(relativePath: String, mode: GlassesWiFiMode, completion: @escaping (Result<UIImage, Error>) -> Void) {
        let path = relativePath.hasPrefix("/") ? relativePath : "/\(relativePath)"
        performDataRequest(urlString: "http://\(mode.host)\(path)") { result in
            switch result {
            case .success(let data):
                if let image = UIImage(data: data) {
                    completion(.success(image))
                } else {
                    completion(.failure(GlassesHTTPError.emptyResponse))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    private func performTextRequest(urlString: String, completion: @escaping (Result<String, Error>) -> Void) {
        performDataRequest(urlString: urlString) { result in
            switch result {
            case .success(let data):
                if let text = String(data: data, encoding: .utf8), !text.isEmpty {
                    completion(.success(text))
                    return
                }
                completion(.success(data.hexString))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    private func performDataRequest(urlString: String, completion: @escaping (Result<Data, Error>) -> Void) {
        guard let encoded = urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: encoded) else {
            completion(.failure(GlassesHTTPError.invalidURL))
            return
        }

        let task = session.dataTask(with: url) { data, _, error in
            if let error {
                completion(.failure(error))
                return
            }
            guard let data, !data.isEmpty else {
                completion(.failure(GlassesHTTPError.emptyResponse))
                return
            }
            completion(.success(data))
        }
        task.resume()
    }

    static func parseFileEntries(from response: String) -> [GlassesFileEntry] {
        let pattern = #"(/?DCIM/[^"'\\\s<>()]+\.(?:jpg|jpeg|png|bmp|gif|webp|heic|mp4|mov|avi))"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }

        let nsResponse = response as NSString
        let matches = regex.matches(in: response, range: NSRange(location: 0, length: nsResponse.length))

        var seen = Set<String>()
        var entries: [GlassesFileEntry] = []

        for match in matches {
            let rawPath = nsResponse.substring(with: match.range(at: 1))
            let path = rawPath.hasPrefix("/") ? rawPath : "/\(rawPath)"
            let normalized = path.lowercased()
            guard !seen.contains(normalized) else { continue }
            seen.insert(normalized)

            let mediaType: GlassesFileEntry.MediaType
            if normalized.hasSuffix(".jpg") || normalized.hasSuffix(".jpeg") || normalized.hasSuffix(".png") || normalized.hasSuffix(".bmp") || normalized.hasSuffix(".gif") || normalized.hasSuffix(".webp") || normalized.hasSuffix(".heic") {
                mediaType = .image
            } else if normalized.hasSuffix(".mp4") || normalized.hasSuffix(".mov") || normalized.hasSuffix(".avi") {
                mediaType = .video
            } else {
                mediaType = .unknown
            }

            entries.append(GlassesFileEntry(path: path, mediaType: mediaType))
        }

        return entries
    }
}
