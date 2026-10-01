# D11. Static bearer token, stored in Keychain

Status: accepted (2026-10-01)

Real authentication is out of scope, but credentials still go through Keychain, never
`UserDefaults`, so the pattern is right when real auth arrives.
