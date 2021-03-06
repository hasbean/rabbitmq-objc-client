import XCTest

enum RecoveryTestError : ErrorType {
    case TimeOutWaitingForConnectionCountToDrop
}

class ConnectionRecoveryIntegrationTest: XCTestCase {
    let httpAPI = RMQHTTP("http://guest:guest@localhost:15672/api")

    func connections() -> [RMQHTTPConnection] {
        return RMQHTTPParser().connections(httpAPI.get("/connections"))
    }

    func closeAllConnections() throws {
        let conns = connections()
        XCTAssertGreaterThan(conns.count, 0)

        for conn in conns {
            let escapedName = conn.name.stringByAddingPercentEncodingWithAllowedCharacters(.URLHostAllowedCharacterSet())!
            let path = "/connections/\(escapedName)"
            httpAPI.delete(path)
        }

        if (!TestHelper.pollUntil(10) { self.connections().count == 0 }) {
            throw RecoveryTestError.TimeOutWaitingForConnectionCountToDrop
        }
    }

    func testReenablesConsumers() {
        let uri = "amqp://guest:guest@localhost"
        let conn = RMQConnection(uri: uri,
                                 tlsOptions: RMQTLSOptions.fromURI(uri),
                                 channelMax: 1000,
                                 frameMax: 131072,
                                 heartbeat: 10,
                                 syncTimeout: 10,
                                 delegate: RMQConnectionDelegateLogger(),
                                 delegateQueue: dispatch_get_main_queue(),
                                 recoverAfter: 1)
        conn.start()
        let ch = conn.createChannel()
        let q = ch.queue("")
        let semaphore = dispatch_semaphore_create(0)
        var messages: [RMQMessage] = []

        q.subscribe { (_, m) in
            messages.append(m)
            dispatch_semaphore_signal(semaphore)
        }

        q.publish("before close")
        XCTAssertEqual(0, dispatch_semaphore_wait(semaphore, TestHelper.dispatchTimeFromNow(5)),
                       "Timed out waiting for message")

        try! closeAllConnections()

        q.publish("after close 1")
        dispatch_semaphore_wait(semaphore, TestHelper.dispatchTimeFromNow(5))
        q.publish("after close 2")
        dispatch_semaphore_wait(semaphore, TestHelper.dispatchTimeFromNow(5))

        XCTAssertEqual(["before close", "after close 1", "after close 2"], messages.map { $0.content })
    }

}
