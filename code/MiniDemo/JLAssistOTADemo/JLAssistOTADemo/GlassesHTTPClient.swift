import Foundation

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

    private func performTextRequest(urlString: String, completion: @escaping (Result<String, Error>) -> Void) {
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

            if let text = String(data: data, encoding: .utf8), !text.isEmpty {
                completion(.success(text))
                return
            }

            completion(.success(data.hexString))
        }
        task.resume()
    }
}
