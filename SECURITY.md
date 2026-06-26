# Security Policy

## Supported versions

`EventBus` is in active development ahead of its first tagged release. Until versioned releases are published, security fixes are applied to the latest `main`.

## Scope

`EventBus` is an in-process Swift library: it routes events between components within a single application and performs no networking, persistence, or handling of untrusted external input. The most relevant considerations for reports are therefore:

- **Log data exposure** — when event logging is enabled, event payloads may be written to the unified logging system. Avoid logging sensitive data; see the logging guidance in the documentation.
- **Availability** — defects in concurrency, cancellation, or buffering could crash or hang the host application. (Buffer sizing and policy are slated to become configurable in a future release.)
- **Dependencies** — vulnerabilities in the package's dependencies or CI tooling. We monitor and update these.

## Reporting a vulnerability

Please **do not** report security vulnerabilities through public GitHub issues, discussions, or pull requests.

Instead, report privately through one of:

- GitHub's [private vulnerability reporting](https://docs.github.com/en/code-security/security-advisories/guidance-on-reporting-and-writing-information-about-vulnerabilities/privately-reporting-a-security-vulnerability) for this repository (the **Security** tab → **Report a vulnerability**), or
- [TODO: confirm SiriusXM security disclosure contact/process]

Please include a description, steps to reproduce, affected versions, and any potential impact. We will acknowledge your report and keep you informed of progress.
