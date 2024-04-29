import Carbon

let kIOUSBDeviceClassName = "IOUSBDevice"

enum Keyboard {
    case External(_ name: String)
    case Internal
}

extension Keyboard {
    static func from(_ name: String) -> Keyboard? {
        switch name {
            case "Apple Internal Keyboard / Trackpad":
                return Keyboard.Internal

            default:
                break
        }

        if name.hasSuffix("Keyboard") {
            return Keyboard.External(name)
        }

        return nil
    }

    func isExternal() -> Bool {
        switch self {
            case Keyboard.External(_): return true
            case Keyboard.Internal: return false
        }
    }
}

func startMonitoring() {
    let matchingDict = IOServiceMatching(kIOUSBDeviceClassName)!
    let notificationPort: IONotificationPortRef = IONotificationPortCreate(kIOMainPortDefault)

    let runLoop: CFRunLoop = CFRunLoopGetCurrent()
    let runLoopSource = IONotificationPortGetRunLoopSource(notificationPort).takeRetainedValue()
    CFRunLoopAddSource(runLoop, runLoopSource, .defaultMode)

    var addIter: io_iterator_t = 0
    IOServiceAddMatchingNotification(
        notificationPort,
        kIOMatchedNotification,
        matchingDict,
        { _ctx, svc in deviceChange(in: true, svc) },
        nil, // context
        &addIter
    )

    var removeIter: io_iterator_t = 0
    IOServiceAddMatchingNotification(
        notificationPort,
        kIOTerminatedNotification,
        matchingDict,
        { ctx, svc in deviceChange(in: false, svc) },
        nil, // context
        &removeIter
    )

    var events: [io_service_t] = []
    ioIterate(addIter) { events.append($0) }
    ioIterate(removeIter) { events.append($0) }
    let keyboards = events.compactMap({ keyboard($0) })
    let externalKbd = keyboards.last(where: { $0.isExternal() });
    if let externalKbd = externalKbd {
        onPlug(in: true, externalKbd)
    } else {
        onPlug(in: true, keyboards[0])
    }
}

func ioIterate(_ it: io_iterator_t, _ cb: (_: io_service_t) -> Void) {
    while true {
        let event = IOIteratorNext(it)
        guard event != IO_OBJECT_NULL else {
            break
        }
        cb(event)
    }
}

func deviceChange(in: Bool, _ service: io_iterator_t) {
    ioIterate(service) { event in
        if let keyboard = keyboard(event) {
            onPlug(in: `in`, keyboard)
        }
    }
}

func keyboard(_ event: io_service_t) -> Keyboard? {
    var nameBuffer: [CChar] = Array(repeating: 0, count: 1024)

    guard IORegistryEntryGetName(event, &nameBuffer) == KERN_SUCCESS else {
        return nil
    }

    let name = String(cString: nameBuffer)
    let kbd = Keyboard.from(name)
    if debug {
        print("event: \"\(name)\", keyboard: \(String(describing: kbd))")
    }

    return kbd
}

func getLayouts() -> (TISInputSource, TISInputSource) {
    let selectableIsProperties = [
        kTISPropertyInputSourceIsEnableCapable: true,
        kTISPropertyInputSourceCategory: kTISCategoryKeyboardInputSource ?? "" as CFString,
    ] as CFDictionary
    let inputSources = TISCreateInputSourceList(selectableIsProperties, false).takeUnretainedValue() as! [TISInputSource]

    for src in inputSources {
        let name = TISGetInputSourceProperty(src, kTISPropertyInputSourceID)

        if let cfValue = name {
            let value = Unmanaged.fromOpaque(cfValue).takeUnretainedValue() as CFString
            if CFGetTypeID(value) == CFStringGetTypeID() {
                print("layout: \(String(describing: value))")
            }
        }
    }

    guard inputSources.count >= 2 else {
        print("Too few keyboard layouts")
        exit(1)
    }

    let internalLayout = inputSources[0]
    let externalLayout = inputSources[1]

    return (internalLayout, externalLayout)
}

func onPlug(in: Bool, _ keyboard: Keyboard) {
    switch keyboard {
        case Keyboard.Internal:
            if `in` {
                print("plug InternalKeyboard")
                TISSelectInputSource(internalLayout)
            } else {
                if (debug) { print("unplug InternalKeyboard?") }
            }

        case Keyboard.External(let name):
            if `in` {
                print("plug ExternalKeyboard: \(name)")
                TISSelectInputSource(externalLayout)
            } else {
                print("unplug ExternalKeyboard: \(name)")
                TISSelectInputSource(internalLayout)
            }
    }
}

func usage() {
    print("Usage: \(CommandLine.arguments[0]) [-d]")
    print("  -d: debug output")
    exit(2)
}

var debug = false
for arg in CommandLine.arguments[1...] {
    if arg == "-d" {
        debug = true
    } else {
        usage()
    }
}

let (internalLayout, externalLayout) = getLayouts()

startMonitoring()
RunLoop.current.run()
