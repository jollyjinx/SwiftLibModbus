# SwiftLibModbus

## Version 2 (Swift Concurrency)

Version 2 has been developed by @jollyjinx for Swift Concurrency Support and is being used by [modbus2mqtt bridge](https://github.com/jollyjinx/swift-modbus-2-mqtt-bridge)

Example usage:
```
let modbusDeviceA = try ModbusDevice(networkAddress:"example.com",port:502,deviceAddress:3)

let modbusDeviceB = try ModbusDevice(device: "/dev/tty.usbserial-42340",baudRate:9600)

let data:[UInt16] = try await modbusDeviceA.readRegisters(from: 0x1000, count: 0x10, type: .holding)
```

For example usage look at:
- [modbus2mqtt bridge](https://github.com/jollyjinx/swift-modbus-2-mqtt-bridge)


Be aware that this code is MIT Licenced, but the underlying CModbus library is LGPL Licensed.
