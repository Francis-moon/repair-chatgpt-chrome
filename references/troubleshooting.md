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

The script copies package content through file streams so Windows writes ordinary unencrypted destination files. It verifies file count, total bytes, and SHA-256 hashes before activating the cache. It then runs the plugin's own manifest installer, prepends a current record to both v2 manifests, and restarts only the matching extension-host process.

Existing caches are retained. Existing same-version content is renamed with a timestamp, and edited manifests are copied to a timestamped backup directory under the Codex home.

## Escalation

If all invariants pass but the side panel still shows an old error:

1. Click **Try again** or close and reopen the side panel.
2. Save browser work and restart Chrome.
3. Restart the ChatGPT/Codex desktop app.
4. If the issue persists, use the app's feedback command and include the chat ID.

Official setup and troubleshooting guidance: https://learn.chatgpt.com/docs/chrome-extension
