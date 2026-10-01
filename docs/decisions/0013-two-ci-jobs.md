# D13. Two CI jobs

Status: accepted (2026-10-01)

A Linux job (fast and cheap) runs Core, API, Simulator and Server tests on every push. A
macOS job (slow, limited minutes) runs on PRs and `main`: XcodeGen, then build, unit,
snapshot and UI tests, then exports screenshots and a simulator video as artifacts. These
artifacts replace Xcode Previews.
