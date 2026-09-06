# Troubleshooting reference

Use this reference after running scripts/Repair-ChatGPTChrome.ps1 in diagnostic mode.

## Invariants

| Check | Meaning when false |
|---|---|
| PluginCacheComplete | The desktop app did not finish synchronizing its bundled Chrome plugin. Windows package files may carry an encrypted attribute, so an ordinary recursive copy can fail. |
| LatestTargetsCurrentPlugin | The current junction still selects an older plugin after an app update. |
| HostConfigPathsValid | extension-host-config.json contains stale runtime paths. A reinstall can change the Node and Codex runtime hashes. |
| NativeManifestValid | Chrome's native-messaging manifest or registry value is missing or targets the wrong extension host. |
| AppDataV2ManifestCurrent | The local-app-data app-server manifest lacks a current entry or its paths no longer exist. |
| CodexHomeV2ManifestCurrent | The Codex-home app-server manifest lacks a current entry or its paths no longer exist. |

## Why one repair may appear insufficient

The integration has three independent layers:

1. The versioned bundled-plugin cache and its current junction.
2. The Chrome native-host manifest plus extension-host-config.json.
3. Two v2 app-server discovery manifests, one under local app data and one under the Codex home.

Repairing only one layer can make diagnostics look healthier while Chrome side chat still reports: Codex app-server manifest entry is missing required path nodePath.

## Repair behavior

The script copies package content through file streams so Windows writes ordinary unencrypted destination files. It verifies file count, total bytes, and SHA-256 hashes before activating the cache. It then runs the plugin's own manifest installer, prepends a current record to both v2 manifests, and stops only matching extension-host processes. Chrome launches a new host on the next connection.

Existing caches are retained. Existing same-version content is renamed with a timestamp, and edited manifests are copied to a timestamped backup directory under the Codex home.

## Escalation

If all invariants pass but the side panel still shows an old error:

1. Click **Try again** or close and reopen the side panel.
2. Save browser work and restart Chrome.
3. Restart the ChatGPT/Codex desktop app.
4. If the issue persists, use the app's feedback command and include the chat ID.

Official setup and troubleshooting guidance: https://learn.chatgpt.com/docs/chrome-extension

## Exit codes and blocked repairs

`0`: all six configuration checks pass (browser confirmation still required). `1`: failed checks. `2`: discovery, compatibility or execution error. `-Json` emits structured output; do not publicly share it without removing personal paths.

Malformed JSON yields a failed diagnostic check. Repair refuses malformed input or unknown v2 document schemas rather than discarding unknown data. Keep the app open and use Windows PowerShell 5.1 x64. Missing package/runtime files require normal app setup first. A non-junction `latest` or redirected write ancestor requires manual investigation; do not delete it to force a repair.

Runtime discovery currently chooses the newest complete runtime/CLI by filesystem modification time. Multiple retained runtimes can make that choice ambiguous; treat a reported mismatch as evidence to investigate, not proof that an older runtime cannot work.

## Recovery after an interrupted repair

Do not repeatedly run Repair. On failure, JSON includes `backupDirectory` and text output identifies the backup directory under the discovered Codex home, in `repair-backups/chatgpt-chrome`. Each attempt uses a unique timestamp and suffix. Backups include existing integration JSON, the old host config, and `recovery.json` with the prior junction target, native-host registry value and retained-cache path. Never publish these files unredacted.

The script is not a transaction and does not automatically roll back. With explicit recovery authorization, inspect which changes actually completed. Restore the matching backed-up JSON to its original location (app-data and Codex-home manifests are different). If a file was absent originally, there is no backup for it; do not invent prior content. Use `recovery.json` to restore the prior HKCU native-host default value and junction only after checking that the recorded target is inside the expected cache and still exists. If the old same-version cache was renamed, restore that retained directory to its original version path before restoring its junction. Retain any newly created cache by renaming it within the verified cache root. Never recursively remove a junction or delete an unrelated directory.

Restoring configuration may require stopping the matching extension host; Chrome itself should remain open unless the user separately authorizes a restart. Re-run Diagnose after recovery. A rollback restores the previous state, which may still contain the original error.
