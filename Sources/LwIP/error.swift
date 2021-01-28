import CLwIP

public enum LwIPError: Int, Error {
    case outOfMemory = -1
    case bufferError = -2
    case timeout = -3
    case routingProblem = -4
    case operationInProgress = -5
    case illegalValue = -6
    case operationWouldBlock = -7
    case addressInUse = -8
    case alreadyConnecting = -9
    case connAlreadyEstablished = -10
    case notConnected = -11
    case netifError = -12
    case connectionAborted = -13
    case connectionReset = -14
    case connectionClosed = -15
    case illegalArgument = -16
}

extension err_t {
    func `throw`() throws {
        if let error = self.error {
            throw error
        }
    }

    var error: LwIPError? {
        return LwIPError(rawValue: Int(self.rawValue))
    }
}
