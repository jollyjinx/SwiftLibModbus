# Changelog

## 3.0.0 (2026-07-13)

- Updated the bundled libmodbus C library from the legacy 3.1.0-era sources to upstream 3.2.0.
- Imported upstream request validation, bounds checks, TCP reconnect and socket lifecycle fixes, RTU improvements, and integer/float conversion hardening.
- Preserved the public Swift `ModbusDevice` API.
- Replaced the macOS-only `Foundation.Host` lookup with libmodbus's protocol-independent resolver, restoring iOS support and allowing IPv4 or IPv6 connections.
- Updated the public `CModbus` timeout API to libmodbus 3.2.0. C callers must replace `timeval` arguments with separate `UInt32` seconds and microseconds values.
- Added explicit provenance and LGPL licensing for the bundled C sources.
