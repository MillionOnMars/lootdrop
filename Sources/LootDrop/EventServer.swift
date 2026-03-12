import Foundation
import Network

class EventServer {
    private var listener: NWListener?
    private let port: UInt16
    private let onEvent: @Sendable (IncomingEvent) -> Void

    init(port: UInt16 = 7777, onEvent: @escaping @Sendable (IncomingEvent) -> Void) {
        self.port = port
        self.onEvent = onEvent
    }

    func start() {
        do {
            let params = NWParameters.tcp
            listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
        } catch {
            print("LootDrop: Failed to create listener: \(error)")
            return
        }

        listener?.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }

        listener?.stateUpdateHandler = { state in
            switch state {
            case .ready:
                print("LootDrop: Server listening on port \(self.port)")
            case .failed(let error):
                print("LootDrop: Server failed: \(error)")
            default:
                break
            }
        }

        listener?.start(queue: .global(qos: .userInitiated))
    }

    func stop() {
        listener?.cancel()
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .userInitiated))
        accumulateData(connection: connection, buffer: Data())
    }

    private func accumulateData(connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self else { connection.cancel(); return }

            var accumulated = buffer
            if let data = data {
                accumulated.append(data)
            }

            // Try to parse what we have
            if let raw = String(data: accumulated, encoding: .utf8),
               let headerEnd = raw.range(of: "\r\n\r\n") {

                // We have complete headers - check if we have the full body
                let headerSection = String(raw[..<headerEnd.lowerBound])
                let bodyStr = String(raw[headerEnd.upperBound...])

                // Parse Content-Length
                var contentLength = 0
                for line in headerSection.components(separatedBy: "\r\n") {
                    if line.lowercased().hasPrefix("content-length:") {
                        let val = line.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)
                        contentLength = Int(val) ?? 0
                    }
                }

                // Do we have enough body data?
                if bodyStr.utf8.count >= contentLength {
                    self.processRequest(connection: connection, raw: raw)
                    return
                }
            }

            // Need more data (or connection closed)
            if isComplete || error != nil {
                // Connection done, try to process what we have
                if let raw = String(data: accumulated, encoding: .utf8) {
                    self.processRequest(connection: connection, raw: raw)
                } else {
                    connection.cancel()
                }
                return
            }

            // Keep reading
            self.accumulateData(connection: connection, buffer: accumulated)
        }
    }

    private func processRequest(connection: NWConnection, raw: String) {
        // Parse HTTP request line
        let lines = raw.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            sendResponse(connection: connection, status: "400 Bad Request", body: "No request line")
            return
        }

        let parts = requestLine.split(separator: " ", maxSplits: 2)
        guard parts.count >= 2 else {
            sendResponse(connection: connection, status: "400 Bad Request", body: "Malformed request")
            return
        }

        let method = String(parts[0])
        let path = String(parts[1])

        if method == "GET" && path == "/health" {
            sendResponse(connection: connection, status: "200 OK", body: "OK")
            return
        }

        if method == "POST" && path == "/event" {
            if let bodyRange = raw.range(of: "\r\n\r\n") {
                let bodyStr = String(raw[bodyRange.upperBound...])
                if let bodyData = bodyStr.data(using: .utf8), !bodyStr.isEmpty {
                    do {
                        let incoming = try JSONDecoder().decode(IncomingEvent.self, from: bodyData)
                        onEvent(incoming)
                        sendResponse(connection: connection, status: "201 Created", body: "{\"status\":\"ok\"}")
                        return
                    } catch {
                        print("LootDrop: JSON decode error: \(error)")
                        print("LootDrop: Body was: \(bodyStr)")
                        sendResponse(connection: connection, status: "400 Bad Request", body: "{\"error\":\"Invalid JSON\"}")
                        return
                    }
                }
            }
            sendResponse(connection: connection, status: "400 Bad Request", body: "{\"error\":\"No body\"}")
            return
        }

        sendResponse(connection: connection, status: "404 Not Found", body: "Not found")
    }

    private func sendResponse(connection: NWConnection, status: String, body: String) {
        let response = "HTTP/1.1 \(status)\r\nContent-Type: application/json\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
        let data = Data(response.utf8)
        connection.send(content: data, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
