import Vapor
import AmongUsProtocol

private var lastUpdateTimestamp: TimeInterval = 0
private var cachedResponse: IndexResponse?

func routes(_ app: Application) throws {
    app.get { (req) -> EventLoopFuture<View> in
        try index(req)
    }

    func index(_ req: Request) throws -> EventLoopFuture<View> {
        if var cachedResponse = cachedResponse, Date().timeIntervalSince1970 - lastUpdateTimestamp < 60 {
            let dateFormatter = ISO8601DateFormatter()
            let lastUpdate = dateFormatter.string(from: Date(timeIntervalSince1970: lastUpdateTimestamp))
            cachedResponse.lastUpdate = lastUpdate

            return req.view.render("index", cachedResponse)
        }

        let promise = req.eventLoop.makePromise(of: View.self)

        let evGroup = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
        var futures = [EventLoopFuture<Data>]()

        let numberFormatter = NumberFormatter()
        numberFormatter.numberStyle = .decimal

        var clients = [UDPClient]()

        for (address, port) in [("104.237.135.186", 22023), ("139.162.111.196", 22023), ("172.105.251.170", 22023)] {
            let client = try UDPClient(address, port: port, bindHost: "0.0.0.0", bindPort: 0)
            clients.append(client)
            let future = client.execute(Data(hex: "080001004ae202030a496e6e657273726f7468")!)
            futures.append(future)
        }

        let futureResult = EventLoopFuture.reduce([], futures, on: evGroup.next()) { (servers, data) -> [[String: String]] in
            let packet = PacketParser.parse(packet: data)
            if case .normal(let packet) = packet {
                if case .reselectServer(let reselectServer)  = packet.messages[0].payload {
                    let masterServers = reselectServer
                        .masterServers
                        .sorted { $0.name < $1.name }
                        .map { (masterServer) -> [String: String] in
                            ["region": masterServer.name.starts(with: "Asia") ? "Asia" : masterServer.name.starts(with: "Europe") ? "Europe" : "North America",
                             "name": masterServer.name,
                             "ipAddress": "\(masterServer.ipAddress)",
                             "port": "\(masterServer.port)",
                             "numberOfConnections": "\(numberFormatter.string(from: NSNumber(value: masterServer.numberOfConnections))!)",
                             "order": masterServer.name.starts(with: "Asia") ? "2" : masterServer.name.starts(with: "Europe") ? "3" : "1",
                            ]
                    }
                    return servers + masterServers
                }
            }
            return [[:]]
        }

        futureResult.whenComplete {
            defer { clients.removeAll() }

            switch $0 {
            case .success(let servers):
                defer { clients.removeAll() }
                lastUpdateTimestamp = Date().timeIntervalSince1970

                let dateFormatter = ISO8601DateFormatter()
                let lastUpdate = dateFormatter.string(from: Date(timeIntervalSince1970: lastUpdateTimestamp))

                let servers = Dictionary(grouping: servers) { $0["region"]! }
                    .values
                    .map { $0 }
                    .sorted { $0[0]["order"]! < $1[0]["order"]! }

                let response = IndexResponse(servers: servers, lastUpdate: lastUpdate)
                cachedResponse = response

                return req.view.render("index", response)
                    .cascade(to: promise)
            case .failure(let error):
                promise.fail(error)
            }
        }

        return promise.futureResult
    }

    app.get("discord-embed") { (req) -> EventLoopFuture<DiscordEmbedResponse> in
        if var cachedResponse = cachedResponse, Date().timeIntervalSince1970 - lastUpdateTimestamp < 60 {
            let dateFormatter = ISO8601DateFormatter()
            let lastUpdate = dateFormatter.string(from: Date(timeIntervalSince1970: lastUpdateTimestamp))
            cachedResponse.lastUpdate = lastUpdate

            var fields = [DiscordEmbedField]()
            for server in cachedResponse.servers {
                fields.append(
                    DiscordEmbedField(
                        name: "Region",
                        value: "\(server[0]["region"]!)",
                        inline: false)
                )
                for s in server {
                    fields.append(
                        DiscordEmbedField(
                            name: "\(s["ipAddress"]!)",
                            value: "\(s["numberOfConnections"]!) players\n ",
                            inline: true)
                    )
                }
            }

            return req.eventLoop.makeSucceededFuture(
                DiscordEmbedResponse(
                    embed: DiscordEmbed(timestamp: "\(dateFormatter.string(from: Date(timeIntervalSince1970: lastUpdateTimestamp)))", fields: fields)
                )
            )
        }

        let promise = req.eventLoop.makePromise(of: DiscordEmbedResponse.self)

        let evGroup = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
        var futures = [EventLoopFuture<Data>]()

        let numberFormatter = NumberFormatter()
        numberFormatter.numberStyle = .decimal

        var clients = [UDPClient]()

        for (address, port) in [("104.237.135.186", 22023), ("139.162.111.196", 22023), ("172.105.251.170", 22023)] {
            let client = try UDPClient(address, port: port, bindHost: "0.0.0.0", bindPort: 0)
            clients.append(client)
            let future = client.execute(Data(hex: "080001004ae202030a496e6e657273726f7468")!)
            futures.append(future)
        }

        let futureResult = EventLoopFuture.reduce([], futures, on: evGroup.next()) { (servers, data) -> [[String: String]] in
            let packet = PacketParser.parse(packet: data)
            if case .normal(let packet) = packet {
                if case .reselectServer(let reselectServer)  = packet.messages[0].payload {
                    let masterServers = reselectServer
                        .masterServers
                        .sorted { $0.name < $1.name }
                        .map { (masterServer) -> [String: String] in
                            ["region": masterServer.name.starts(with: "Asia") ? "Asia" : masterServer.name.starts(with: "Europe") ? "Europe" : "North America",
                             "name": masterServer.name,
                             "ipAddress": "\(masterServer.ipAddress)",
                             "port": "\(masterServer.port)",
                             "numberOfConnections": "\(numberFormatter.string(from: NSNumber(value: masterServer.numberOfConnections))!)",
                             "order": masterServer.name.starts(with: "Asia") ? "2" : masterServer.name.starts(with: "Europe") ? "3" : "1",
                            ]
                    }
                    return servers + masterServers
                }
            }
            return [[:]]
        }

        futureResult.whenComplete {
            defer { clients.removeAll() }

            switch $0 {
            case .success(let servers):
                defer { clients.removeAll() }
                lastUpdateTimestamp = Date().timeIntervalSince1970

                let dateFormatter = ISO8601DateFormatter()
                let lastUpdate = dateFormatter.string(from: Date(timeIntervalSince1970: lastUpdateTimestamp))

                let servers = Dictionary(grouping: servers) { $0["region"]! }
                    .values
                    .map { $0 }
                    .sorted { $0[0]["order"]! < $1[0]["order"]! }

                let response = IndexResponse(servers: servers, lastUpdate: lastUpdate)
                cachedResponse = response

                var fields = [DiscordEmbedField]()
                for server in response.servers {
                    fields.append(
                        DiscordEmbedField(
                            name: "Region",
                            value: "\(server[0]["region"]!)",
                            inline: false)
                    )
                    for s in server {
                        fields.append(
                            DiscordEmbedField(
                                name: "\(s["ipAddress"]!)",
                                value: "\(s["numberOfConnections"]!) players\n ",
                                inline: true)
                        )
                    }
                }

                return req.eventLoop.makeSucceededFuture(
                    DiscordEmbedResponse(
                        embed: DiscordEmbed(timestamp: "\(dateFormatter.string(from: Date(timeIntervalSince1970: lastUpdateTimestamp)))", fields: fields)
                    )
                )
                .cascade(to: promise)
            case .failure(let error):
                promise.fail(error)
            }
        }

        return promise.futureResult
    }
}

struct IndexResponse: Content {
    var servers: [[[String : String]]]
    var lastUpdate: String
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

extension Data {
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
