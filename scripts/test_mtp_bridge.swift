import Foundation
import Darwin

typealias CallbackFn = @convention(c) (UnsafePointer<CChar>?) -> Void

final class MTPBridgeTest: @unchecked Sendable {
    static let shared = MTPBridgeTest()
    private let lock = NSLock()
    
    private var initFn: (@convention(c) (UnsafeRawPointer) -> Void)?
    private var disposeFn: (@convention(c) (UnsafeRawPointer) -> Void)?
    private var walkFn: (@convention(c) (UnsafePointer<CChar>, UnsafeRawPointer) -> Void)?
    
    private static var activeDoneHandler: ((String) -> Void)?
    
    private static let cDoneCallback: CallbackFn = { jsonPtr in
        guard let jsonPtr = jsonPtr else { return }
        let str = String(cString: jsonPtr)
        activeDoneHandler?(str)
    }
    
    init() {
        let path = "/Users/sarvesh/Desktop/LiquidDynamo-1.9.2/Frameworks/kalam.dylib"
        guard let handle = dlopen(path, RTLD_NOW) else {
            fatalError("Cannot dlopen kalam.dylib: \(String(cString: dlerror()))")
        }
        
        if let sym = dlsym(handle, "Initialize") {
            initFn = unsafeBitCast(sym, to: (@convention(c) (UnsafeRawPointer) -> Void).self)
        }
        if let sym = dlsym(handle, "Dispose") {
            disposeFn = unsafeBitCast(sym, to: (@convention(c) (UnsafeRawPointer) -> Void).self)
        }
        if let sym = dlsym(handle, "Walk") {
            walkFn = unsafeBitCast(sym, to: (@convention(c) (UnsafePointer<CChar>, UnsafeRawPointer) -> Void).self)
        }
    }
    
    func execute<T>(_ block: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try block()
    }
    
    func initialize() async -> String {
        await withCheckedContinuation { continuation in
            execute {
                Self.activeDoneHandler = { json in
                    Self.activeDoneHandler = nil
                    continuation.resume(returning: json)
                }
                let ptr = unsafeBitCast(Self.cDoneCallback, to: UnsafeRawPointer.self)
                initFn?(ptr)
            }
        }
    }
    
    func dispose() async -> String {
        await withCheckedContinuation { continuation in
            execute {
                Self.activeDoneHandler = { json in
                    Self.activeDoneHandler = nil
                    continuation.resume(returning: json)
                }
                let ptr = unsafeBitCast(Self.cDoneCallback, to: UnsafeRawPointer.self)
                disposeFn?(ptr)
            }
        }
    }
}

Task {
    let bridge = MTPBridgeTest.shared
    print("Testing async initialize...")
    let initRes = await bridge.initialize()
    print("Init result len: \(initRes.count)")
    
    print("Testing async dispose...")
    let dispRes = await bridge.dispose()
    print("Dispose result: \(dispRes)")
    exit(0)
}

RunLoop.main.run()
