<!-- system-index-depends: Authentication.md, Safeguards.md -->
# SandboxingEntitlements.md — Sandboxing, Entitlements, Permissions, and Security

Authoritative guidance for macOS App Sandbox, entitlements, Keychain storage, Transparency Consent and Control (TCC), Hardened Runtime, and notarization. Security on macOS is a contract with the system: the app declares the least privilege it needs, the system enforces it, and the user grants the rest explicitly. An entitlement the app does not need is a liability; a permission the app takes without asking is a violation.

---

## 0. Autonomy & Working Scope

- **Strict User Project Directory Scoping:** Security and entitlement work must remain strictly within the user's project workspace. Never inspect or leak Agents' internal host files or app bundle paths.
- **Autonomous Error Recovery:** If a sandbox denial, a missing entitlement, or a Keychain failure blocks a feature, diagnose the exact denial (Console, `sandbox-exec` logs, Keychain error codes), formulate the minimal fix, and repair it autonomously.
- **Confidentiality:** Never output raw internal tool names or internal mode expressions. Never log, print, or embed secrets, tokens, or Keychain contents.
- **Least privilege:** Every entitlement and permission must be justified by a feature that needs it. If a feature can work without an entitlement, it works without it.

---

## 1. App Sandbox

- **The container is the boundary:** A sandboxed app reads and writes inside its container (`~/Library/Containers/<bundle-id>/`) freely. Everything outside requires an entitlement, a user grant, or a security-scoped bookmark.
- **User-selected files are grants, not rights:** When the user picks a file or folder in an open/save panel, the app gains access to that item for the session. Access does not persist across launches unless a security-scoped bookmark is saved.
- **Security-scoped bookmarks persist grants:** Save a bookmark (with `URL.bookmarkData` including the security scope) when the user grants lasting access to a folder (a project directory, a workspace). Resolve it on launch, call `startAccessingSecurityScopedResource`, and call `stopAccessingSecurityScopedResource` when done. A stale bookmark (target moved or deleted) must be handled, not crashed on.
- **No escape hatches:** A sandboxed app cannot read arbitrary paths, spawn unrestricted helpers, or write outside its container by cleverness. Attempts to work around the sandbox are bugs, not features, and will fail review.
- **Temporary exceptions are technical debt:** A temporary-exception entitlement is a promise to remove it. Record the reason, the feature it serves, and the plan to remove it. An exception with no removal plan becomes permanent by neglect.

---

## 2. Entitlements Catalog

- **Declare only what the feature needs:** Each entitlement maps to a capability. The common set:
  - `com.apple.security.app-sandbox` — the sandbox itself.
  - `com.apple.security.network.client` — outbound network (APIs, providers).
  - `com.apple.security.network.server` — inbound network (a local daemon, a listening socket).
  - `com.apple.security.files.user-selected.read-only` / `.read-write` — user-picked files.
  - `com.apple.security.files.downloads.read-only` — Downloads folder.
  - `com.apple.security.device.audio-input` / `.camera` — microphone and camera.
  - `com.apple.security.personal-information.addressbook` / `.photos-library` / `.location` — protected data.
  - `com.apple.security.automation.apple-events` — Apple Events to specific apps.
  - `com.apple.security.cs.allow-jit` — just-in-time compilation (JavaScript engines, runtimes).
  - `com.apple.security.cs.allow-unsigned-executable-memory` — unsigned executable memory (some runtimes).
  - `com.apple.security.get-task-allow` — debugging only; never ship with it.
- **Entitlements are reviewed:** App Store and notarization review read the entitlement list. An entitlement without a visible feature that needs it is a rejection risk.
- **Hardened Runtime is separate from the sandbox:** Hardened Runtime (`com.apple.security.cs.*`) restricts code execution (library validation, JIT, debugging). An app can be sandboxed without Hardened Runtime and vice versa; shipping uses both.
- **Entitlement changes need a rebuild and re-sign:** Editing the entitlements file without re-signing leaves the running app with the old set. Verify the effective entitlements with `codesign -d --entitlements - <app>` after every change.

---

## 3. Keychain

- **Secrets live in the Keychain, never in files:** API keys, tokens, passwords, and certificates are stored with the Keychain Services API or a wrapper. Never store a secret in UserDefaults, a plist, a log, or source code.
- **Access groups scope sharing:** `kSecAttrAccessGroup` shares items between the app and its extensions or helpers. An item stored without the right group is invisible to the extension that needs it.
- **Accessibility classes set availability:** `kSecAttrAccessibleWhenUnlocked` is the default; `AfterFirstUnlock` suits background daemons; `WhenUnlockedThisDeviceOnly` prevents iCloud Keychain sync. Choose deliberately — the wrong class locks the app out of its own secret after a restart or a lock.
- **Error codes are the diagnosis:** `errSecItemNotFound` (no item), `errSecAuthFailed` (wrong access), `errSecInteractionNotAllowed` (background access without allowance), `errSecDuplicateItem` (add instead of update). Log the code, not the secret.
- **Keychain failures are user-visible:** A missing or inaccessible secret must surface as a clear action (sign in again, re-authorize) — never as a silent fallback to an unauthenticated state.
- **Migration on first launch:** When moving secrets from an insecure store to the Keychain, migrate once, verify, then delete the old copy. A migration that leaves the old copy behind leaves the secret exposed.

---

## 4. Transparency, Consent, and Control (TCC)

- **Protected data needs a prompt and a purpose string:** Microphone, camera, contacts, photos, location, folders (Desktop, Documents, Downloads), automation, and full-disk access each require a usage-description string (`NSMicrophoneUsageDescription`, `NSCameraUsageDescription`, and friends) and a system prompt the user must accept.
- **Purpose strings say why, in plain language:** "Agents needs microphone access to transcribe voice notes." A vague string ("This app needs access") is a rejection risk and earns a denial.
- **Denial is a state, not an error:** When the user denies a permission, the feature that needs it shows a clear explanation and a path to Settings. It does not retry the prompt (the system will not show it again) and does not silently degrade.
- **Check before acting:** Query authorization status (`AVCaptureDevice.authorizationStatus`, `PHPhotoLibrary.authorizationStatus`, `FileManager` access checks) before using a protected resource. Acting first and handling the denial as a crash is a defect.
- **Full-disk access is a last resort:** Request it only when the feature genuinely needs arbitrary filesystem access, and explain why in the product. Most apps do not need it.
- **Automation permissions are per-target:** Apple Events to another app require an entitlement naming the target and a user grant. The grant dialog names the target app; a generic "control other apps" request is not how it works.

---

## 5. Hardened Runtime and Notarization

- **Hardened Runtime on every shipping build:** Enable it in the project; it restricts dynamic code loading, unsigned memory, and debugging. A shipping build without it is a security gap.
- **Notarization is a gate, not a formality:** `notarytool` submits the app; the service scans for malware and policy violations. A notarization failure names the violation — fix it, do not work around it.
- **Library validation:** With Hardened Runtime, only libraries signed by the same team (or Apple) load. A third-party dylib that is unsigned or signed by another team fails to load at runtime, not at build time — test the signed artifact.
- **Entitlements and Hardened Runtime interact:** A JIT entitlement without the matching Hardened Runtime flag still fails. Verify the combination in the signed app, not in the project file.

---

## 6. Methodology — Least-Privilege Audit

1. **List every entitlement:** Read the entitlements file and the signed app's effective entitlements. Each one needs a named feature.
2. **List every TCC prompt:** Each usage-description string needs a feature and a user-facing reason.
3. **List every secret:** Each secret needs a Keychain home, an access group, and an accessibility class.
4. **Remove what is unused:** An entitlement, prompt, or secret store with no feature is deleted, not left "in case".
5. **Test denial paths:** Deny each permission in turn; every feature degrades gracefully with a clear explanation.
6. **Verify the signed artifact:** `codesign` and `spctl` checks on the actual shipping build, not the debug build.
7. **Verify against sections 7 and 8 before finishing.**

---

## 7. Failure Cases and Pitfalls

- **Bookmark staleness crash:** Resolving a stale security-scoped bookmark and force-unwrapping the result. Fix: handle the stale case, prompt the user to re-select the folder.
- **Missing `stopAccessingSecurityScopedResource`:** Access is held indefinitely, leaking kernel resources and blocking other access. Fix: balance every start with a stop, preferably with `defer`.
- **Secret in UserDefaults or a log:** A token written to a plist or printed in a debug log. Fix: Keychain only; audit logs for secrets.
- **Over-broad entitlements:** Network server, full-disk access, or automation granted "just in case". Fix: remove; add back only with a named feature.
- **Silent TCC denial:** The feature fails with no explanation because the denial was treated as an error to retry. Fix: check authorization status first; show a Settings path on denial.
- **Vague purpose strings:** A generic usage description that earns a denial or a rejection. Fix: name the feature and the reason.
- **Debug-only entitlement shipped:** `get-task-allow` in a release build is a security hole and a review failure. Fix: separate debug and release entitlement files.
- **Unsigned library at runtime:** A dylib that loads in a debug build fails under Hardened Runtime. Fix: sign it with the team identity and test the signed artifact.
- **Keychain item invisible to an extension:** Stored without the shared access group. Fix: set the group on both sides and verify from the extension.

---

## 8. Verification Steps

1. **Entitlement audit:** Every entitlement maps to a named feature; none is unused; none is debug-only in a release build.
2. **Effective entitlements:** `codesign -d --entitlements -` on the signed app matches the project file.
3. **Bookmark round-trip:** Grant a folder, relaunch, resolve the bookmark, access works; move the folder, relaunch, the stale case is handled gracefully.
4. **Keychain audit:** No secret exists outside the Keychain; access groups and accessibility classes are verified from every consumer (app, extension, helper).
5. **TCC denial matrix:** Deny each permission in turn; each feature degrades with a clear explanation and a Settings path.
6. **Notarization:** The shipping build notarizes cleanly; `spctl --assess` passes.
7. **Hardened Runtime:** The signed artifact loads all its libraries under Hardened Runtime; no unsigned code executes.
8. **Log audit:** No secret appears in any log, diagnostic bundle, or crash report.
