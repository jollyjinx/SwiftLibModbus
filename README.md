# SwiftLibModbus

SwiftLibModbus is a modern Swift wrapper around the libmodbus C library, providing a convenient, type-safe interface for communicating with Modbus devices using Swift Concurrency features.

[![Swift](https://img.shields.io/badge/Swift-6.1-orange.svg)](https://swift.org)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

## Overview

SwiftLibModbus leverages Swift Concurrency (async/await) to provide a clean, efficient API for Modbus RTU and TCP communication. The library is designed for ease of use while maintaining the full power of the underlying libmodbus implementation.

Key features:
- Swift Concurrency support (async/await)
- Support for Modbus RTU (serial) and Modbus TCP connections
- Type-safe register/coil reading and writing
- Automatic connection management 
- Swift actor model for thread safety
- Easy handling of endianness

## Requirements

- Swift 6.1+
- iOS 18+ or macOS 15+

## Installation

### Swift Package Manager

Add SwiftLibModbus as a dependency to your `Package.swift` file:

```swift
dependencies: [
    .package(url: "https://github.com/jollyjinx/SwiftLibModbus.git", from: "2.0.0")
]
```

Then add the dependency to your target:

```swift
.target(
    name: "YourTarget",
    dependencies: ["SwiftLibModbus"]
)
```

## Usage

### Connecting to a Modbus TCP Device

```swift
import SwiftLibModbus

// Connect to a Modbus TCP device
let device = try ModbusDevice(
    networkAddress: "192.168.1.100", 
    port: 502,
    deviceAddress: 1
)

// Read holding registers
let holdingRegisters: [UInt16] = try await device.readHoldingRegisters(
    from: 0x1000, 
    count: 16
)

// Write to holding registers
try await device.writeRegisters(
    to: 0x1000, 
    arrayToWrite: [UInt16(1), UInt16(2), UInt16(3)]
)
```

### Connecting to a Modbus RTU Device

```swift
import SwiftLibModbus

// Connect to a Modbus RTU (serial) device
let device = try ModbusDevice(
    device: "/dev/tty.usbserial-42340",
    slaveid: 1,
    baudRate: 9600,
    dataBits: 8,
    parity: .none,
    stopBits: 1
)

// Read coils
let coils = try await device.readInputCoilsFrom(
    startAddress: 0x00, 
    count: 10
)

// Read input registers
let inputRegisters: [UInt16] = try await device.readInputRegisters(
    from: 0x00, 
    count: 10
)
```

### Reading Different Data Types

The library supports reading various fixed-width integer types as well as floating point values:

```swift
// Read as 16-bit unsigned integers
let uint16Values: [UInt16] = try await device.readRegisters(
    from: 0x1000, 
    count: 10, 
    type: .holding
)

// Read as 32-bit unsigned integers
let uint32Values: [UInt32] = try await device.readRegisters(
    from: 0x1000, 
    count: 5, 
    type: .holding
)

// Read as IEEE-754 floating point
let floatValues: [Float] = try await device.readRegisters(
    from: 0x1000, 
    count: 5, 
    type: .holding
)

// Read as ASCII string
let asciiString = try await device.readASCIIString(
    from: 0x1000, 
    count: 10, 
    type: .holding
)
```

### Handling Endianness

You can specify endianness when reading or writing registers:

```swift
// Read registers with little endian byte order
let values: [UInt32] = try await device.readRegisters(
    from: 0x1000, 
    count: 10, 
    type: .holding, 
    endianness: .littleEndian
)
```

## Auto-Reconnect and Idle Disconnect Features

The library has built-in management for connections:

```swift
// Connect with auto-reconnect after 1 hour and disconnect when idle for 30 seconds
let device = try ModbusDevice(
    networkAddress: "example.com",
    port: 502,
    deviceAddress: 1,
    autoReconnectAfter: 3600.0,  // 1 hour in seconds
    disconnectWhenIdleAfter: 30.0  // 30 seconds
)
```

## Example Projects

For more complete examples, see:

- [swift-modbus-2-mqtt-bridge](https://github.com/jollyjinx/swift-modbus-2-mqtt-bridge) - A bridge converting Modbus to MQTT

## License

SwiftLibModbus Version 2 has been developed by @jollyjinx for Swift Concurrency Support and is available under the MIT license. The underlying libmodbus C library is licensed under LGPL.