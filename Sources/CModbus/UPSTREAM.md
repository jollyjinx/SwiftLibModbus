# Vendored libmodbus

The C sources in this directory are based on upstream libmodbus v3.2.0:

- Repository: https://github.com/stephane/libmodbus
- Tag: `v3.2.0`
- Commit: `a9b025d12289855490b10d77461c99e001abfc0f`
- Release date: 2026-07-02

The upstream `src` implementation and public headers are vendored directly. SwiftPM-specific adaptations are intentionally kept small:

- `config.h` is maintained for the supported SwiftPM platforms and explicitly included before upstream feature checks.
- The bundled `strlcpy.c` supplies `strlcpy` consistently on platforms such as Linux.
- Safe explicit casts silence width-conversion warnings from Apple Clang.

The libmodbus sources are licensed under LGPL-2.1-or-later. The license text is stored at `LICENSES/libmodbus-LGPL-2.1-or-later.txt` in the repository root.
