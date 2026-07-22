---
title: SwiftLibModbus architecture and maintenance
description: Module boundaries, concurrency and connection behavior, vendored C policy, testing, and release documentation.
status: active
last_updated: 2026-07-22
---

# Architecture and maintenance

## Package shape

`Package.swift` requires Swift 6.3, enables Swift 6 language mode and strict-concurrency checking, and publishes two library products:

- `SwiftLibModbus` is the public Swift wrapper in `Sources/SwiftLibModbus/ModbusDevice.swift`.
- `CModbus` is the vendored libmodbus C implementation and public headers in `Sources/CModbus`.

`Tests/SwiftLibModbusTests` uses Swift Testing. The manifest declares macOS 15 and iOS 18 as minimum Apple platforms; the package and tests also contain Linux-specific paths.

## Swift wrapper

`ModbusDevice` is an actor that owns one opaque libmodbus context and its default device address. On Darwin it uses a dedicated serial dispatch executor so blocking libmodbus calls do not occupy Swift's cooperative executor. Actor isolation also keeps device selection and the following operation together when callers use per-operation `deviceAddress` overloads.

The public surface comprises:

- TCP and RTU initializers;
- explicit `connect()` and `disconnect()` lifecycle methods;
- coil and discrete-input reads plus single-coil writes;
- generic fixed-width integer and floating-point register reads;
- generic fixed-width integer register writes;
- ASCII string reads and writes;
- big- and little-endian conversion;
- overloads that use either the default address or an address supplied for one operation.

Generic register `count` values describe result elements. The wrapper converts the element width to the required number of 16-bit Modbus registers. Changes in this area must test more than `UInt16`, because byte count, word count, memory binding, and byte order interact.

## Connection behavior

Before an operation, the actor connects when necessary and selects the requested device address. Successful operations restart the idle-disconnect task. The auto-reconnect task closes a connection after its configured lifetime; the next operation reconnects. A non-positive timer interval disables the corresponding task.

TCP contexts enable libmodbus link and protocol error recovery. RTU configuration includes the serial path, default slave address, baud rate, data bits, parity, and stop bits. Preserve lifecycle behavior conservatively: downstream long-running bridges depend on reconnect, idle-disconnect, and timeout semantics.

## Vendored libmodbus

The C target is based on libmodbus v3.2.0 at upstream commit `a9b025d12289855490b10d77461c99e001abfc0f`. `Sources/CModbus/UPSTREAM.md` is authoritative for provenance and the intentionally small SwiftPM adaptations.

When updating the vendored library:

1. Start from a named upstream release and record its tag, commit, and release date in `Sources/CModbus/UPSTREAM.md`.
2. Keep the upstream implementation and public headers recognizable; isolate SwiftPM-specific changes.
3. Retain `config.h`, the portable `strlcpy` implementation, and only those warning fixes required by supported compilers.
4. Review upstream API and ABI changes against both the Swift wrapper and the public `CModbus` product.
5. Update the bundled LGPL license and `CHANGELOG.md` when required.

Do not make wrapper-level workarounds for faults that clearly belong in the C transport implementation. Conversely, avoid changing vendored C code for Swift API design concerns.

## Validation

The primary check is:

```sh
swift test
```

The default suite verifies the bundled library version, address-aware API availability, response-timeout persistence across TCP reconnects, and atomic per-operation device selection through a loopback server. Hardware-dependent RTU and device-specific tests are disabled by default.

Use targeted checks in addition to the full suite:

- API changes: compile representative calls for every affected overload and result type.
- Endianness or sizing changes: cover `UInt8`, `UInt16`, wider integers, and floating-point values in both byte orders.
- TCP changes: use a bounded loopback server or packet-level assertion; check reconnect and timeout preservation.
- RTU changes: test with explicit hardware only when available and keep the hardware test disabled for normal CI.
- Vendored C updates: verify the version macros and exercise both Swift and direct `CModbus` callers.

Run tests on macOS and Linux for changes involving conditional imports, socket constants, dispatch executors, or C configuration. Do not enable network or hardware tests in the default suite if they require an external service or attached device.

## Documentation and releases

- Keep `README.md` focused on consumer installation and public API usage.
- Record user-visible release changes and migration requirements in `CHANGELOG.md`.
- Keep provenance and C-layer adaptation details in `Sources/CModbus/UPSTREAM.md`.
- Update this document when module boundaries, concurrency isolation, lifecycle semantics, supported platforms, or validation strategy changes.
- Ensure version examples and the Swift badge match the latest release and manifest before tagging.

The Swift wrapper is MIT-licensed. Bundled libmodbus remains LGPL-2.1-or-later; preserve the license split in distributions and documentation.
