# Contributing

File a focused issue with reproduction steps and Windows/PowerShell versions. Make small PRs with test coverage and documentation updates. Run `tooling/Test.ps1` on Windows (needs Pester 5.7.1 and PSScriptAnalyzer); CI runs it on Windows PowerShell 5.1 and PowerShell 7. `tooling/Package.ps1` builds the release archive and is covered by `tests/Package.Tests.ps1`. Do not include private hostnames, secrets, or unredacted diagnostic reports. Contributions are licensed under MIT. See [AGENTS.md](AGENTS.md) for the repeated PowerShell/Pester pitfalls (for example `.ToArray()` instead of `@($list)`, and Pester setup inside `BeforeAll`).

`main` is protected: changes land through pull requests, and the `powershell (powershell)` and `powershell (pwsh)` checks must pass before merging. Direct pushes, force pushes and deleting `main` are blocked.
