# Repair ChatGPT Chrome

[![Windows tests](https://github.com/Francis-moon/repair-chatgpt-chrome/actions/workflows/test.yml/badge.svg)](https://github.com/Francis-moon/repair-chatgpt-chrome/actions/workflows/test.yml)

A community-maintained Codex skill for repairing ChatGPT Chrome side-panel integration after Windows desktop app updates. **v0.2.0** · MIT · [中文说明](README.zh-CN.md)

Typical error: `Codex app-server manifest entry is missing required path nodePath`.

## Scope

Windows x64, Windows PowerShell 5.1, and the `OpenAI.Codex` AppX package with its bundled Chrome plugin. Discovers installed versions and paths; no account credentials, browser-profile access or third-party runtime downloads. Not an official OpenAI product. Future desktop layouts may require another update.

## Install

Ask Codex Skill Installer to install `https://github.com/Francis-moon/repair-chatgpt-chrome` at tag `v0.2.0`, or clone that tag into your supported personal skills directory. Then invoke `$repair-chatgpt-chrome` and describe the error. The agent diagnoses first and uses your explicit authorization before applying a repair.

For manual use, clone the repository and run from its directory:

```powershell
git clone --branch v0.2.0 https://github.com/Francis-moon/repair-chatgpt-chrome.git
cd repair-chatgpt-chrome
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Repair-ChatGPTChrome.ps1 -Mode Diagnose -Json
```

After reviewing the failed checks and accepting the changes:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Repair-ChatGPTChrome.ps1 -Mode Repair -Force -Json
```

Run Diagnose again, then click **Try again** in Chrome. Exit **0** means all configuration checks pass; **1** means failed checks; **2** means discovery, compatibility or execution error. Browser confirmation is a separate final step.

## What v0.2.0 improves

- Diagnoses malformed JSON and missing fields without crashing.
- Detects stale runtimes even when old files still exist; checks native-host identity and extension origins.
- Checks prerequisites before activation, rejects redirected write paths and unknown v2 schemas, and prevents concurrent repairs.
- Skips healthy installations; preserves JSON backups, prior registry value, junction target and old caches for recovery.
- Provides JSON output, documented exit codes and isolated Windows regression tests.

Repair stops only matching extension hosts. It never closes Chrome or deletes browser profiles. An interrupted repair may need manual recovery; automatic transaction rollback is not provided. See [troubleshooting and recovery](references/troubleshooting.md).

## Validation and contributions

Run `powershell -NoProfile -ExecutionPolicy Bypass -File tests/Run-Tests.ps1`. The same tests run in CI under Windows PowerShell 5.1 and PowerShell 7. Tests use temporary fixtures and simulated registry/process discovery; they do not prove end-to-end Chrome behavior on every desktop release.

[Design sources](references/design-sources.md) records the high-star repositories consulted and the methods adopted. [Changelog](CHANGELOG.md) records release changes. Report failures through [GitHub Issues](https://github.com/Francis-moon/repair-chatgpt-chrome/issues) with the skill version, OS architecture, failed check names and a redacted error. Do not upload raw JSON diagnostics, registry exports, backups, tokens or browser-profile data.

[Official browser-extension guidance](https://learn.chatgpt.com/docs/chrome-extension).
