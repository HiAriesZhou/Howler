import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct MagpieSelection: Codable, Equatable, Sendable {
    public let port: UInt16
    public let model: String

    public init(port: UInt16, model: String) {
        self.port = port
        self.model = model
    }

    public var service: ModelService {
        var service = ModelService(format: .openAICompatible, baseURL: URL(string: "http://127.0.0.1:\(port)/v1")!, model: model)
        service.magpie = self
        return service
    }
}

final class RefuseRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

public enum Magpie {
    public struct Model: Decodable, Identifiable, Sendable {
        public let id: String
        public let modalities: Modalities?
        public struct Modalities: Decodable, Sendable { public let input: [String]? }
    }

    public static func models(port: UInt16) async throws -> [Model] {
        struct Hello: Decodable { let name: String }
        struct Catalog: Decodable { let data: [Model] }
        let session = URLSession(configuration: .ephemeral, delegate: RefuseRedirect(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        func fetch(_ path: String) async throws -> Data {
            let url = URL(string: "http://127.0.0.1:\(port)/\(path)")!
            let (data, response) = try await session.data(for: URLRequest(url: url, timeoutInterval: 3))
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            return data
        }
        let decoder = JSONDecoder()
        guard try await decoder.decode(Hello.self, from: fetch("api/hello")).name == "magpie" else {
            throw URLError(.badServerResponse)
        }
        return try await decoder.decode(Catalog.self, from: fetch("v1/models")).data.filter { !$0.id.isEmpty }
    }
}
