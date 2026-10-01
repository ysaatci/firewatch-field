# D2. Develop locally in a Linux Docker image, not with the native Windows toolchain

Status: accepted (2026-10-01)

*Alternative:* the Swift for Windows toolchain.
*Why:* Smart App Control on this machine blocks unsigned compiled test binaries (this
already happened with Go). Vapor/SwiftNIO support on Windows is also weaker than on
Linux. Docker matches CI exactly. The native Windows toolchain is optional, mainly for
editor support.
