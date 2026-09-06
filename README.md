# Repair ChatGPT Chrome

A reusable Codex skill for diagnosing and repairing the ChatGPT Chrome extension integration on Windows after a ChatGPT/Codex desktop app update or reinstall.

It targets the recurring side-panel error:

> Unable to start ChatGPT — Codex app-server manifest entry is missing required path nodePath

The skill discovers all user-specific paths and installed versions at runtime. It does not contain usernames, machine paths, runtime hashes, or copied diagnostic logs.

## What it checks

- The current Windows AppX package and bundled Chrome plugin
- The versioned plugin cache and its current junction
- The native-messaging manifest and registry entry
- extension-host-config.json runtime paths
- Both chrome-native-hosts-v2.json discovery manifests

## Safety

Diagnostic mode is read-only. Repair mode requires an explicit Force switch, creates timestamped backups, retains old caches, and stops only the matching ChatGPT extension-host process. It does not close Chrome.

## Install

Install the repository as a personal Codex skill with Skill Installer, or place the repository folder in a supported personal skills directory.

## Use

Invoke the skill with:

    $repair-chatgpt-chrome

The skill diagnoses first and asks before applying repairs.

## Manual script usage

Diagnose:

    powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Repair-ChatGPTChrome.ps1 -Mode Diagnose

Repair after reviewing the diagnosis:

    powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Repair-ChatGPTChrome.ps1 -Mode Repair -Force

Official browser-extension guidance: https://learn.chatgpt.com/docs/chrome-extension
