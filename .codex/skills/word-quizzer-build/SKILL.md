---
name: word-quizzer-build
description: Automate Word Quizzer Flutter builds in this repo. Use when asked to run flutter build (web/PWA, apk/appbundle, ios) or manage app version/build numbers. Always bump the pubspec build number on every build. Only change semantic version when explicitly requested, keeping major at 0 unless told otherwise.
---

# Word Quizzer Build

## Overview

Run repo-local Flutter builds with automatic build-number bumps. Keep semantic version changes explicit and user-driven.

## Workflow

1) Choose target
- Default to `web` (PWA) if the user does not specify a build target.
- Use the target the user requests (`web`, `apk`, `appbundle`, `ios`, etc.).

2) Run build (always bump build number)
- From repo root, run `tools/build.sh <target> [extra flutter args]`.
- This script bumps `mobile_app/pubspec.yaml` build number, then runs `flutter build` inside `mobile_app`.
- Do not run `flutter build` directly unless the user explicitly asks to bypass the bump.

3) Semantic version changes (only when asked)
- Edit `mobile_app/pubspec.yaml` `version:` only when the user asks for a major/minor/patch change.
- Keep major at `0` unless the user explicitly requests a major bump.
- If the user requests "next version" without specifying which part, ask a brief clarification.
- After updating semantic version, run `tools/build.sh <target>`.

4) Report
- Confirm the updated `version` and build number after a successful build.
- Provide the output path if the user asks (e.g., `mobile_app/build/web/` or `mobile_app/build/app/outputs/`).
