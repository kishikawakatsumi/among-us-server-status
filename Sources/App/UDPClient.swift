import Foundation
import NIO

public class UDPClient {
    let group: EventLoopGroup
    let host: String
    let port: Int
    let bindHost: String
    let bindPort: Int
    private let isSharedPool: Bool
    let socketAddress: SocketAddress

    let errorCallback: (Error?) -> Void = { _ in }

    public init(_ host: String, port: Int, bindHost: String, bindPort: Int) throws {
        self.host = host
        self.port = port

        group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        isSharedPool = false

        socketAddress = try SocketAddress.makeAddressResolvingHost(self.host, port: self.port)
        self.bindHost = bindHost
        self.bindPort = bindPort
    }

    public func execute(_ data: Data) -> EventLoopFuture<Data> {
        let promise = group.next().makePromise(of: Data.self)
        let handler = UDPChannelHandler(for: data, remote: socketAddress, promise: promise)
        let bootstrap = DatagramBootstrap(group: group)
            .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
            .channelInitializer { channel in
                return channel.pipeline.addHandler(handler)
            }
        _ = bootstrap.bind(host: bindHost, port: bindPort)
        return promise.futureResult
    }

    deinit {
        if !self.isSharedPool {
            group.shutdownGracefully(self.errorCallback)
        }
    }
}

private final class UDPChannelHandler: ChannelInboundHandler {
    typealias InboundIn = AddressedEnvelope<ByteBuffer>
    typealias OutboundOut = AddressedEnvelope<ByteBuffer>

    let data: Data
    let remoteAddress: SocketAddress
    let responsePromise: EventLoopPromise<Data>

    init(for data: Data, remote: SocketAddress, promise: EventLoopPromise<Data>) {
        self.data = data
        responsePromise = promise
        remoteAddress = remote
    }

    public func channelActive(context: ChannelHandlerContext) {
        var buffer = context.channel.allocator.buffer(capacity: data.count)
        buffer.writeBytes(data)
        let addBuffer = AddressedEnvelope<ByteBuffer>(remoteAddress: remoteAddress, data: buffer)
        context.writeAndFlush(wrapOutboundOut(addBuffer), promise: nil)
    }

    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var response = unwrapInboundIn(data)
        if let bytes = response.data.readBytes(length: response.data.readableBytes) {
            responsePromise.succeed(Data(bytes))
        } else {
            responsePromise.succeed(Data())
        }
        context.close(promise: nil)
    }
}
