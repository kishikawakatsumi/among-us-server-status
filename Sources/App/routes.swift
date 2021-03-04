import Vapor
import AmongUsProtocol

private var lastUpdate: TimeInterval = Date.distantPast.timeIntervalSince1970
private var cachedResponse: IndexResponse?
private let cacheExpiryDuration: TimeInterval = 300

func routes(_ app: Application) throws {
    app.get { (req) -> EventLoopFuture<View> in
        try index(req)
    }

    func index(_ req: Request) throws -> EventLoopFuture<View> {
        if var cachedResponse = cachedResponse, Date().timeIntervalSince1970 - lastUpdate < cacheExpiryDuration {
            cachedResponse.lastUpdate = lastUpdate
            return req.view.render("index", cachedResponse)
        }

        let promise = req.eventLoop.makePromise(of: View.self)

        var clients = [UDPClient]()
        let futures = try fetchStatuses(clients: &clients)

        let group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
        EventLoopFuture
            .reduce([], futures, on: group.next()) { $0 + parsePacket($1) }
            .whenComplete {
                defer { clients.removeAll() }

                switch $0 {
                case .success(let servers):
                    defer { clients.removeAll() }
                    lastUpdate = Date().timeIntervalSince1970

                    let response = buildIndexResponse(servers: servers)
                    cachedResponse = response

                    return req.view.render(
                        "index", response
                    )
                    .cascade(to: promise)
                case .failure(let error):
                    promise.fail(error)
                }
        }

        return promise.futureResult
    }

    app.get("discord-embed") { (req) -> EventLoopFuture<DiscordEmbedResponse> in
        if var cachedResponse = cachedResponse, Date().timeIntervalSince1970 - lastUpdate < cacheExpiryDuration {
            cachedResponse.lastUpdate = lastUpdate
            return req.eventLoop.makeSucceededFuture(
                buildDiscordEmbed(response: cachedResponse)
            )
        }

        let promise = req.eventLoop.makePromise(of: DiscordEmbedResponse.self)

        var clients = [UDPClient]()
        let futures = try fetchStatuses(clients: &clients)

        let group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
        EventLoopFuture
            .reduce([], futures, on: group.next()) { $0 + parsePacket($1) }
            .whenComplete {
                defer { clients.removeAll() }

                switch $0 {
                case .success(let servers):
                    defer { clients.removeAll() }
                    lastUpdate = Date().timeIntervalSince1970

                    let response = buildIndexResponse(servers: servers)
                    cachedResponse = response

                    return req.eventLoop.makeSucceededFuture(
                        buildDiscordEmbed(response: response)
                    )
                    .cascade(to: promise)
                case .failure(let error):
                    promise.fail(error)
                }
        }

        return promise.futureResult
    }

    func fetchStatuses(clients: inout [UDPClient]) throws -> [EventLoopFuture<Data>] {
        var futures = [EventLoopFuture<Data>]()

        for (address, port) in [("104.237.135.186", 22023), ("139.162.111.196", 22023), ("172.105.251.170", 22023)] {
            let client = try UDPClient(address, port: port, bindHost: "0.0.0.0", bindPort: 0)
            clients.append(client)
            let future = client.execute(Data(hex: "080001004ae202030a496e6e657273726f7468")!)
            futures.append(future)
        }

        return futures
    }

    func parsePacket(_ data: Data) -> [[String: String]] {
        let numberFormatter = NumberFormatter()
        numberFormatter.numberStyle = .decimal

        let packet = PacketParser.parse(packet: data)
        if case .normal(let packet) = packet {
            if case .reselectServer(let reselectServer)  = packet.messages[0].payload {
                let masterServers = reselectServer
                    .masterServers
                    .sorted { $0.name < $1.name }
                    .map { (masterServer) -> [String: String] in
                        ["region": masterServer.name.starts(with: "Asia") ? "Asia" : masterServer.name.starts(with: "Europe") ? "Europe" : "North America",
                         "regionEmoji": masterServer.name.starts(with: "Asia") ? "🌏" : masterServer.name.starts(with: "Europe") ? "🌍" : "🌎",
                         "name": masterServer.name,
                         "ipAddress": "\(masterServer.ipAddress)",
                         "port": "\(masterServer.port)",
                         "numberOfConnections": "\(numberFormatter.string(from: NSNumber(value: masterServer.numberOfConnections))!)",
                         "order": masterServer.name.starts(with: "Asia") ? "2" : masterServer.name.starts(with: "Europe") ? "3" : "1",
                        ]
                }
                return masterServers
            }
        }
        return [[:]]
    }

    func buildIndexResponse(servers: [[String : String]]) -> IndexResponse {
        let servers = Dictionary(grouping: servers) { $0["region"]! }
            .values
            .map { $0 }
            .sorted { $0[0]["order"]! < $1[0]["order"]! }

        return IndexResponse(servers: servers, lastUpdate: lastUpdate)
    }

    func buildDiscordEmbed(response: IndexResponse) -> DiscordEmbedResponse {
        var fields = [DiscordEmbedField]()
        for server in response.servers {
            let value = """
            ```
            \(
                server
                    .map { "\($0["ipAddress"]!.padding(toLength: 15, withPad: " ", startingAt: 0)) \($0["numberOfConnections"]!.paddingToLeft(upTo: 5, using: " ")) players" }
                    .joined(separator: "\n")
            )
            ```
            """
            fields.append(
                DiscordEmbedField(
                    name: "\(server[0]["regionEmoji"]!) \(server[0]["region"]!)",
                    value: value,
                    inline: false)
            )
        }

        let dateFormatter = ISO8601DateFormatter()
        return DiscordEmbedResponse(
            embed: DiscordEmbed(
                timestamp: "\(dateFormatter.string(from: Date(timeIntervalSince1970: lastUpdate)))",
                fields: fields
            )
        )
    }
}

struct IndexResponse: Content {
    var servers: [[[String : String]]]
    var lastUpdate: TimeInterval
}

struct DiscordEmbedResponse: Content {
    var embed: DiscordEmbed
}

struct DiscordEmbed: Content {
    var title = "Among Us Server Status"
    var url = "https://among-us-server-status.herokuapp.com/"
    var timestamp: String
    var fields = [DiscordEmbedField]()
}

struct DiscordEmbedField: Content {
    var name: String
    var value: String
    var inline: Bool
}

private extension Data {
    init?(hex: String) {
        let len = hex.count / 2
        var data = Data(capacity: len)
        for i in 0..<len {
            let j = hex.index(hex.startIndex, offsetBy: i * 2)
            let k = hex.index(j, offsetBy: 2)
            let bytes = hex[j..<k]
            if var num = UInt8(bytes, radix: 16) {
                data.append(&num, count: 1)
            } else {
                return nil
            }
        }
        self = data
    }

    var hex: String {
        return reduce("") { $0 + String(format: "%02x", $1) }
    }
}

private extension RangeReplaceableCollection where Self: StringProtocol {
    func paddingToLeft(upTo length: Int, using element: Element = " ") -> SubSequence {
        return repeatElement(element, count: Swift.max(0, length-count)) + suffix(Swift.max(count, count-length))
    }
}
