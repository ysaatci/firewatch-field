# D8. MVVM with `@Observable`, no TCA

Status: accepted (2026-10-01)

*Alternative:* The Composable Architecture.
*Why:* it has no third-party dependency, it's the approach Apple promotes, and it's
easy for a reviewer to follow. Testable logic sits in Core actors anyway, so view models
stay thin. The trade-off (less enforced structure than TCA) is acceptable at this size.
