# Changelog

## 0.2.0 — 2026-09-06

Reliable diagnostic failures, current-path comparison, native-host identity/origin checks, preflight validation, redirected-path rejection, concurrent-repair guard, healthy no-op, recovery metadata, JSON output and meaningful exit codes. Added Windows fixture tests, CI, bilingual installation/usage instructions and source attribution.

Compatibility: Windows x64 with the existing OpenAI.Codex AppX bundled-plugin layout. A failed diagnostic now exits 1 instead of always returning success; execution errors exit 2. Repair still requires `-Force` and explicit user authorization.

Validation: isolated tests on Windows PowerShell 5.1 and PowerShell 7; read-only diagnosis on a real installation. No claim of end-to-end repair across all desktop versions. Interrupted repairs retain recovery material but do not automatically roll back.

## Initial release

Original three-layer cache, native-host and v2 manifest repair workflow.
