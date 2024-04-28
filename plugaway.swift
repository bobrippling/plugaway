import Carbon

let kIOUSBDeviceClassName = "IOUSBDevice"

enum Event {
    case ExternalKeyboard(name: String)
    case InternalKeyboard
}

func startMonitoring() {
    let matchingDict = IOServiceMatching(kIOUSBDeviceClassName)!
    let notificationPort: IONotificationPortRef = IONotificationPortCreate(kIOMainPortDefault)

    let runLoop: CFRunLoop = CFRunLoopGetCurrent()
    let runLoopSource = IONotificationPortGetRunLoopSource(notificationPort).takeRetainedValue()
    CFRunLoopAddSource(runLoop, runLoopSource, .defaultMode)

    var deviceIterator: io_iterator_t = 0

    IOServiceAddMatchingNotification(
        notificationPort,
        kIOMatchedNotification,
        matchingDict,
        deviceAdded,
        nil, // context
        &deviceIterator
    )

    // Empty the iterator to arm the notification
    drain(deviceIterator)

    IOServiceAddMatchingNotification(
        notificationPort,
        kIOTerminatedNotification,
        matchingDict,
        deviceRemoved,
        nil, // context
        &deviceIterator
    )
    drain(deviceIterator)
}

func drain(_ it: io_iterator_t) {
    while IOIteratorNext(it) != IO_OBJECT_NULL {}
}

func deviceAdded(context: UnsafeMutableRawPointer?, service: io_iterator_t) {
    let event = IOIteratorNext(service)
    if let name = keyboardName(event) {
        onChange(Event.ExternalKeyboard(name: name))
    }
    drain(service)
}

func deviceRemoved(context: UnsafeMutableRawPointer?, service: io_iterator_t) {
    let event = IOIteratorNext(service)
    if keyboardName(event) != nil {
        onChange(Event.InternalKeyboard)
    }
    drain(service)
}

func keyboardName(_ service: io_service_t) -> String? {
    var nameBuffer: [CChar] = Array(repeating: 0, count: 1024)

    guard IORegistryEntryGetName(service, &nameBuffer) == KERN_SUCCESS else {
        return nil
    }

    let name = String(cString: nameBuffer)
    if debug {
        print("Device: \"\(name)\"")
    }
    switch name {
        case "Apple Internal Keyboard / Trackpad":
            return nil

        case "IOUSBHostDevice":
            return name

        default:
            break
    }

    if name.hasSuffix("Keyboard") {
        return name
    }

    return nil
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

func onChange(_ event: Event) {
    switch event {
        case Event.InternalKeyboard:
            print("InternalKeyboard")
            TISSelectInputSource(internalLayout)

        case Event.ExternalKeyboard(let name):
            print("ExternalKeyboard: \(name)")
            TISSelectInputSource(externalLayout)
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
