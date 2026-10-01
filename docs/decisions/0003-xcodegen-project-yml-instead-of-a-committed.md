# D3. XcodeGen (`project.yml`) instead of a committed `.xcodeproj`

Status: accepted (2026-10-01)

*Alternative:* a hand-made Xcode project, or Tuist.
*Why:* you can't create or reliably edit `.pbxproj` files without Xcode. A YAML spec is
readable, merges cleanly, and CI generates the project. Tuist is more powerful but
heavier than this project needs.
