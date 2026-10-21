# AI agent engineering contract

- Work only on the agreed issue/PR scope; do not merge or publish releases automatically.
- PowerShell 5.1 syntax is the compatibility baseline, but test both 5.1 and 7 on Windows before claiming compatibility.
- Use approved verbs, advanced functions, typed result objects and meaningful errors.
- Preserve a single authoritative function implementation under src/; generate standalone scripts during builds.
- Diagnostic tools must be read-only and require no telemetry, network downloads or credentials.
- Missing, blocked or unsupported checks must never be treated as passing.
- Add Pester tests for core logic and failure conditions; run static checks.
- Update documentation and examples for public behavior changes.
- Do not weaken or delete failing tests just to pass CI.
- Treat Windows-specific environment facts as unverified until tested.

- **Never** wrap a `System.Collections.Generic.List[object]` with `@($list)` in a result-object literal. Use `$list.ToArray()` and test fully constructed output objects.
- In Pester 5, initialize test fixtures and variables inside `BeforeAll` (not at test-file scope). Keep and extend `tests/Conventions.Tests.ps1`.
- Exercise zero, one and multiple output rows, partial collection and standalone/module parity in Windows CI.
