import XCTest

enum TestDoubleTransportError: ErrorType {
    case NotConnected(localizedDescription: String)
    case ArbitraryError(localizedDescription: String)
}

@objc class ControlledInteractionTransport: NSObject, RMQTransport {
    var delegate: RMQTransportDelegate? = nil
    var connected = false
    var outboundData: [NSData] = []
    var readCallbacks: Array<(NSData) -> Void> = []
    var callbackIndexToRunNext = 0
    var stubbedToProduceErrorOnWrite: String?
    var stubbedToThrowErrorOnConnect: String?

    func connect() throws {
        if let stubbedError = stubbedToThrowErrorOnConnect {
            throw NSError(domain: RMQErrorDomain, code: 0, userInfo: [ NSLocalizedDescriptionKey: stubbedError ])
        } else {
            connected = true
        }
    }
    
    func close(onClose: () -> Void) {
        connected = false
        onClose()
    }

    func write(data: NSData) {
        if let description = stubbedToProduceErrorOnWrite {
            let error = NSError(domain: RMQErrorDomain, code: 0, userInfo: [ NSLocalizedDescriptionKey: description ])
            delegate?.transport(self,
                                failedToWriteWithError: error)
        } else {
            outboundData.append(data)
        }
    }

    func isConnected() -> Bool {
        return connected
    }

    func readFrame(complete: (NSData) -> Void) {
        readCallbacks.append(complete)
    }

    func handshake() -> Self {
        self.serverSendsPayload(MethodFixtures.connectionStart(), channelNumber: 0)
        self.serverSendsPayload(MethodFixtures.connectionTune(), channelNumber: 0)
        self.serverSendsPayload(MethodFixtures.connectionOpenOk(), channelNumber: 0)
        return self
    }

    func serverSendsPayload(payload: RMQPayload, channelNumber: Int) -> Self {
        serverSendsData(RMQFrame(channelNumber: channelNumber, payload: payload).amqEncoded())
        return self
    }

    func serverSendsData(data: NSData) -> Self {
        if readCallbacks.isEmpty {
            XCTFail("No read callbacks stored for \(decode(data))!")
        } else if callbackIndexToRunNext == readCallbacks.count - 1 {
            readCallbacks.last!(data)
            callbackIndexToRunNext += 1
        } else {
            XCTFail("No read callbacks left to fulfill! Already fulfilled \(readCallbacks.count).")
        }
        return self
    }

    func assertClientSentMethod(amqMethod: RMQMethod, channelNumber: Int) -> Self {
        if outboundData.isEmpty {
            XCTFail("Nothing sent. Expected \(amqMethod.dynamicType).")
        } else {
            let actual = outboundData.last!
            let parser = RMQParser(data: actual)
            let frame = RMQFrame(parser: parser)
            TestHelper.assertEqualBytes(
                RMQFrame(channelNumber: channelNumber, payload: amqMethod).amqEncoded(),
                actual,
                "\nExpected:\n\(amqMethod.dynamicType)\nGot:\n\(frame.payload.dynamicType)"
            )
        }
        return self
    }

    func lastSentPayload() -> RMQPayload {
        let actual = outboundData.last!
        let parser = RMQParser(data: actual)
        let frame = RMQFrame(parser: parser)
        return frame.payload
    }

    func assertClientSentMethods(methods: [RMQMethod], channelNumber: Int) -> Self {
        if outboundData.isEmpty {
            XCTFail("nothing sent")
        } else {
            let lastIndex = outboundData.count - 1
            let startIndex = lastIndex - methods.count + 1
            let actual = Array(outboundData[startIndex...lastIndex])
            let decoded = outboundData.map { (data) -> String in
                decode(data)
            }
            let expected = methods.map { (method) -> NSData in
                return RMQFrame(channelNumber: channelNumber, payload: method).amqEncoded()
            }
            XCTAssertEqual(expected, actual, "\nAll outgoing methods: \(decoded)")
        }
        return self
    }

    func assertClientSentProtocolHeader() -> Self {
        TestHelper.pollUntil { return self.outboundData.count > 0 }
        TestHelper.assertEqualBytes(
            RMQProtocolHeader().amqEncoded(),
            outboundData.last!
        )
        return self
    }

    func decode(data: NSData) -> String {
        let parser = RMQParser(data: data)
        let frame = RMQFrame(parser: parser)
        let decoded = frame.payload as? RMQMethod
        return "\(decoded?.dynamicType)"
    }
}