import Dispatch
import CLwIP

private var tcpipIntialized : () = {
    let sema = DispatchSemaphore(value: 0)
    tcpip_init({ unmanagedSema in
        let sema = Unmanaged<DispatchSemaphore>.fromOpaque(unmanagedSema!).takeRetainedValue()
        sema.signal()

    }, Unmanaged<DispatchSemaphore>.passRetained(sema).toOpaque())
    sema.wait()
}()

/// Initialize the TCP/IP stack
internal func initializeTCPIP() {
    _ = tcpipIntialized
}

func assertCoreLocked() {
    sys_check_core_locking()
}

func tcpip<Result>(perform block: () throws -> Result ) rethrows -> Result {
    sys_lock_tcpip_core()
    defer {
        sys_unlock_tcpip_core()
    }

    return try block()
}

class CallbackQueue {
    /// List of pending callbacks which will be invoked once the queue has been started
    private var pendingCallbacks : [() -> Void] = []

    /// DispatchQueue which will be used to dispatch all external events
    private(set) var queue: DispatchQueue? = nil {
        didSet {
            if let queue = queue {
                assertCoreLocked()
                for callback in pendingCallbacks {
                    queue.async(execute: callback)
                }
                pendingCallbacks.removeAll()
            }
        }
    }

    func callback(invoking block : @escaping () -> Void) {
        assertCoreLocked()

        if let queue = queue {
            queue.async(execute: block)
        } else {
            pendingCallbacks.append(block)
        }
    }

    func start0(queue: DispatchQueue) {
        self.queue = queue
    }

    /// Start dispatching events of the connection/listener and set the queue to deliver the events on.
    /// - Parameter queue: The queue to dispatch the events on
    func start(queue: DispatchQueue) {
        tcpip {
            start0(queue: queue)
        }
    }
}

protocol CallbackQueueProtocol {
    var callbackQueue: CallbackQueue { get }
}

extension CallbackQueueProtocol {
    /// Invoke a callback on the callbackQueue. If no queue is present, the callback will be held back until
    /// `start(queue:)` has been called
    func callback(invoking block :@escaping () -> Void) {
        callbackQueue.callback(invoking: block)
    }

    /// Start dispatching events of the connection/listener and set the queue to deliver the events on.
    /// - Parameter queue: The queue to dispatch the events on
    func start(queue: DispatchQueue) {
        callbackQueue.start(queue: queue)
    }
}
