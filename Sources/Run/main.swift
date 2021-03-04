import App
import Vapor

var env = try Environment.detect()
try LoggingSystem.bootstrap(from: &env)
let app = Application(env)
app.http.server.configuration.port = Int(Environment.process.PORT ?? "8080") ?? 8080
defer { app.shutdown() }
try configure(app)
try app.run()
