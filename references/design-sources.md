# Design sources and validation

## Selection

On 2026-09-06, queried GitHub REST repository search with `"skills" in:name,description stars:>20000`, sorted by stars descending (first 10 results). This is a reproducible search snapshot, not a claim to rank every skill or a measure of reliability. Chose the three highest results and the official Anthropic collection for relevant debugging/authoring methods. Star counts change.

| Repository | Stars in snapshot | Source read | Adaptation |
|---|---:|---|---|
| [obra/superpowers](https://github.com/obra/superpowers) | 282,199 | [systematic-debugging](https://github.com/obra/superpowers/blob/main/skills/systematic-debugging/SKILL.md) | Identify the failed layer before making changes; verify the result. |
| [mattpocock/skills](https://github.com/mattpocock/skills) | 253,304 | [tdd](https://github.com/mattpocock/skills/blob/main/skills/engineering/tdd/SKILL.md) | Observable fixture outcomes for broken/current configurations; avoid wording-only tests. |
| [affaan-m/ECC](https://github.com/affaan-m/ECC) | 250,316 | [verification-loop](https://github.com/affaan-m/ECC/blob/main/skills/verification-loop/SKILL.md) | Run checks and review the diff before publishing; report limitations. |
| [anthropics/skills](https://github.com/anthropics/skills) | 174,693 | [skill-creator](https://github.com/anthropics/skills/blob/main/skills/skill-creator/SKILL.md) | Concise entrypoint, supporting references, explicit usage boundaries. |

Methods were adapted, not copied as executable code or imported as mandatory workflows. No affiliation or endorsement is implied. Official [OpenAI skill guidance](https://learn.chatgpt.com/docs/build-skills) and [browser-extension guidance](https://learn.chatgpt.com/docs/chrome-extension) were also consulted. Internal repair paths are based on the inspected installed bundle, not a published stable API.

## Release checks

Run `tests/Run-Tests.ps1` using Windows PowerShell 5.1 and PowerShell 7. The fixture suite exercises all six diagnostics, malformed and incomplete JSON, stale-but-existing paths, wrong native-host origins, repair authorization, no-op behavior, rejected preflight without changes, junction preservation, containment and hash corruption detection.

Registry/process discovery is simulated. The suite never invokes the real installer or stops real extension hosts. A real read-only diagnostic was also run for v0.2.0. End-to-end browser repair, automatic rollback and support for future AppX layouts are not established by these tests.

Before each release: inspect changed files for local paths or secrets, validate the SKILL frontmatter, run both shells and inspect CI. Publish a version tag and release notes that distinguish tested behavior from remaining uncertainty.

## v0.2.1 real-world follow-up

A real repair exposed quote stripping in Windows PowerShell 5.1 native `node -e` argument conversion, which the original isolated suite did not exercise. The corrected helper writes a temporary UTF-8 module file and removes it after execution. `tests/Test-NodeInvocation.ps1` launches real Node and verifies Unicode, quotes, backslashes and nonzero exit propagation. CI runs it in both shells.

The interrupted repair was resumed from the installer step after checking its retained backup and completed cache activation. All six diagnostics then passed; the user confirmed the side panel worked. This is one confirmed recovery, not a full fresh-run compatibility matrix.
