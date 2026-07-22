# SwiftLibModbus

SwiftLibModbus is a Swift Concurrency wrapper around the bundled [libmodbus](https://libmodbus.org/) C library. It provides an actor-isolated API for Modbus TCP and RTU devices, typed register access, coil operations, endianness conversion, connection lifecycle management, and per-operation device addressing.

[![Swift](https://img.shields.io/badge/Swift-6.3-orange.svg)](https://swift.org)
[![License](https://img.shields.io/badge/License-MIT%20%2F%20LGPL--2.1--or--later-blue.svg)](LICENSE)

## Requirements

- Swift 6.3 or newer
- macOS 15 or newer
- iOS 18 or newer
- Linux with a Swift 6.3-compatible toolchain

The libmodbus 3.2.0 sources are included in the package; consumers do not need to install libmodbus separately.

## Installation

Add the package through Swift Package Manager:

```swift
dependencies: [
    .package(
        url: "https://gitmaster.jinx.eu/jnxpublic/SwiftLibModbus.git",
        from: "3.0.0"
    )
]
```

Then add the Swift wrapper product to your target:

```swift
.target(
    name: "YourTarget",
    dependencies: [
        .product(name: "SwiftLibModbus", package: "SwiftLibModbus")
    ]
)
```

The package also publishes `CModbus` for callers that intentionally need the underlying C API.

## Modbus TCP

```swift
import SwiftLibModbus

let device = try ModbusDevice(
    networkAddress: "192.168.1.100",
    port: 502,
    deviceAddress: 1
)

let registers: [UInt16] = try await device.readHoldingRegisters(
    from: 0x1000,
    count: 16
)

try await device.writeRegisters(
    to: 0x1000,
    arrayToWrite: [UInt16(1), UInt16(2), UInt16(3)]
)
```

TCP connections are established when needed. You can also call `connect()` and `disconnect()` explicitly. The actor serializes access to the shared libmodbus context, including device-address selection.

### Addressing multiple devices

Every read and write operation has an overload that accepts `deviceAddress`. This is useful for gateways that expose multiple Modbus devices through one connection:

```swift
let first: [UInt16] = try await device.readHoldingRegisters(
    from: 0,
    count: 1,
    deviceAddress: 1
)

let second: [UInt16] = try await device.readHoldingRegisters(
    from: 0,
    count: 1,
    deviceAddress: 2
)
```

## Modbus RTU

```swift
import SwiftLibModbus

let device = try ModbusDevice(
    device: "/dev/tty.usbserial-42340",
    slaveid: 1,
    baudRate: 9_600,
    dataBits: 8,
    parity: .none,
    stopBits: 1
)

let coils = try await device.readInputCoilsFrom(
    startAddress: 0,
    count: 10
)

let inputRegisters: [UInt16] = try await device.readInputRegisters(
    from: 0,
    count: 10
)
```

## Typed registers and strings

The generic register APIs support fixed-width integers and floating-point values. `count` is the number of requested values of the inferred result type, while Modbus transfers still operate on 16-bit register words.

```swift
let words: [UInt16] = try await device.readRegisters(
    from: 0x1000,
    count: 10,
    type: .holding
)

let values: [Float32] = try await device.readRegisters(
    from: 0x1000,
    count: 5,
    type: .holding,
    endianness: .littleEndian
)

let label = try await device.readASCIIString(
    from: 0x1100,
    count: 16,
    type: .holding
)
```

## Connection lifecycle

`autoReconnectAfter` closes long-lived connections after the configured interval so the next operation reconnects. `disconnectWhenIdleAfter` closes an idle connection after the configured interval. Set either value to `0` to disable that timer.

```swift
let device = try ModbusDevice(
    networkAddress: "example.com",
    port: 502,
    deviceAddress: 1,
    autoReconnectAfter: 3_600,
    disconnectWhenIdleAfter: 30
)
```

Operations throw `ModbusError` when a device cannot be created or connected, or when a read or write fails.

## Development

Run the package test suite from the repository root:

```sh
swift test
```

The default suite checks the bundled C-library version, API compilation, timeout behavior, and per-operation addressing through a loopback TCP server. Tests that require physical Modbus hardware are disabled unless deliberately enabled in the test source.

See [AI/ARCHITECTURE.md](AI/ARCHITECTURE.md) for module boundaries, concurrency behavior, vendored-source policy, and validation guidance. Release changes are recorded in [CHANGELOG.md](CHANGELOG.md).

## License

The Swift wrapper is available under the [MIT License](LICENSE). The bundled libmodbus 3.2.0 C sources are licensed under [LGPL-2.1-or-later](LICENSES/libmodbus-LGPL-2.1-or-later.txt); provenance and SwiftPM-specific adaptations are documented in [Sources/CModbus/UPSTREAM.md](Sources/CModbus/UPSTREAM.md).
