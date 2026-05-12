import Foundation

struct XPostCreatedPost: Decodable, Equatable {
    let id: String
    let text: String
}

struct XPostHTTPError: LocalizedError, Equatable {
    let statusCode: Int
    let responseText: String

    var errorDescription: String? {
        if responseText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "X API request failed with HTTP \(statusCode)."
        }

        return "X API request failed with HTTP \(statusCode): \(responseText)"
    }
}

struct XPostAPIClient {
    private let apiBaseURL = URL(string: "https://api.x.com/2/")!

    func fetchCurrentUser(accessToken: String) async throws -> XPostAccount {
        struct Response: Decodable {
            struct User: Decodable {
                let id: String
                let name: String
                let username: String
            }

            let data: User
        }

        let response: Response = try await request(
            path: "users/me",
            method: "GET",
            accessToken: accessToken,
            body: nil
        )
        return XPostAccount(
            id: response.data.id,
            name: response.data.name,
            username: response.data.username
        )
    }

    func createPost(text: String, accessToken: String) async throws -> XPostCreatedPost {
        struct Body: Encodable {
            let text: String
        }

        struct Response: Decodable {
            let data: XPostCreatedPost
        }

        let body = try JSONEncoder().encode(Body(text: text))
        let response: Response = try await request(
            path: "tweets",
            method: "POST",
            accessToken: accessToken,
            body: body
        )
        return response.data
    }

    private func request<Response: Decodable>(
        path: String,
        method: String,
        accessToken: String,
        body: Data?
    ) async throws -> Response {
        var request = URLRequest(url: URL(string: path, relativeTo: apiBaseURL)!.absoluteURL)
        request.httpMethod = method
        request.timeoutInterval = 20
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse,
           !(200 ..< 300).contains(httpResponse.statusCode) {
            throw XPostHTTPError(
                statusCode: httpResponse.statusCode,
                responseText: String(decoding: data, as: UTF8.self)
            )
        }

        return try JSONDecoder().decode(Response.self, from: data)
    }
}
