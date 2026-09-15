# Repository Guidelines

## Project Structure & Module Organization

Paper is a Swift 6 macOS 14+ application built with Swift Package Manager. `App/` contains the application entry point, `Views/` contains SwiftUI screen composition, `Stores/` owns document state and file operations, and `Support/` contains reusable AppKit/SwiftUI editor infrastructure such as the line-number text editor. Keep troubleshooting notes in `docs/` and development utilities in `script/`. Treat `.build/` and `dist/` as generated output; do not commit them. If resources are added, place them in a dedicated `Resources/` directory and declare them in `Package.swift`.

## Build, Test, and Development Commands

- `swift build` compiles the executable in debug mode.
- `./script/build_and_run.sh` builds an app bundle in `dist/Paper.app` and launches it.
- `./script/build_and_run.sh --verify` builds, launches, and confirms that the process stays running.
- `./script/build_and_run.sh --debug` runs the executable directly for debugger-friendly output.
- `./script/build_and_run.sh --logs` streams Paper's unified macOS logs.
- `swift test` runs package tests after a test target has been added.

## Coding Style & Naming Conventions

Use four-space indentation and follow standard Swift API design guidelines. Name types in `UpperCamelCase`, members in `lowerCamelCase`, SwiftUI screens with a `View` suffix, and state containers with a `Store` suffix. Prefer one primary type per file. Keep views declarative and move document loading, saving, naming, and derived state into the store. Use `private` for implementation details and avoid force unwraps. No formatter or linter is currently configured, so keep formatting consistent with nearby code.

## Testing Guidelines

The repository does not yet define a test target. Add new tests under `Tests/PaperTests/` and register that target in `Package.swift`. Use focused names such as `DocumentStoreTests` and `testSavingUntitledDocumentPromptsForLocation`. Prioritize document-state transitions, file encoding, save behavior, and line-number calculations. For UI changes, run `--verify` and manually check light/dark contrast, caret visibility, scrolling, title editing, and text-to-gutter alignment. Record reusable fixes in `docs/`.

## Commit & Pull Request Guidelines

History currently contains only `first commit`, so there is no established convention. Use short, imperative subjects such as `Align line-number gutter`. Keep commits focused. Pull requests should explain the user-visible change, list validation commands, link relevant issues, and include before/after screenshots for UI work. Never include `.build/`, `dist/`, local logs, or machine-specific settings.
