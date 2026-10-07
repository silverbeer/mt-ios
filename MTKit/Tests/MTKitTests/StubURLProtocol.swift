import Foundation
@testable import MTKit

/// Routes requests from a test URLSession to a per-session handler.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) throws -> (Int, Data)

    /// Throw from a handler to leave the request unanswered until it is cancelled.
    struct NoAnswer: Error {}

    private static let lock = NSLock()
    nonisolated(unsafe) private static var handlers: [String: Handler] = [:]

    /// A client whose requests go to `handler`. Each client gets its own host, which is
    /// how concurrent tests are kept apart.
    static func client(tokens: TokenStore, _ handler: @escaping Handler) -> APIClient {
        let host = "\(UUID().uuidString.lowercased()).test"
        lock.withLock { handlers[host] = handler }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return APIClient(baseURL: URL(string: "https://\(host)")!, session: URLSession(configuration: config),
                         tokens: tokens)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let id = request.url?.host ?? ""
        guard let handler = Self.lock.withLock({ Self.handlers[id] }) else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        do {
            var request = request
            if request.httpBody == nil, let stream = request.httpBodyStream {
                request.httpBody = Data(reading: stream)
            }
            let (status, data) = try handler(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
                                           headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch is NoAnswer {
            // Stall: URLSession calls stopLoading when the task is cancelled.
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private extension Data {
    init(reading stream: InputStream) {
        self.init()
        stream.open()
        defer { stream.close() }
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            append(buffer, count: count)
        }
    }
}

/// Thread-safe recorder for requests seen by a stub handler.
final class Recorder: @unchecked Sendable {
    private let lock = NSLock()
    private var _requests: [URLRequest] = []

    func record(_ request: URLRequest) { lock.withLock { _requests.append(request) } }
    var requests: [URLRequest] { lock.withLock { _requests } }
    var paths: [String] { requests.map { $0.url!.path } }
}

func json(_ string: String) -> Data { Data(string.utf8) }
