# AGENTS.md
This file provides strict guidance to Code Agents when working with code in the "WeaveFlux (织影)" repository.

## Project Overview
"WeaveFlux (织影)" is a decentralized, client-only AI video generation APP designed exclusively for Android (Target SDK 34+). 
It is built using Flutter (UI layer) and Go Mobile (Embedded Backend Core via .so compiled binaries).

### CRITICAL ARCHITECTURE RULES:
1. NO REMOTE SERVER: The app operates entirely without an external backend or cloud database. Do not write any code attempting to connect to custom authentication, Firebase, Supabase, or external server infrastructures.
2. BYO-KEY MODEL: The app relies entirely on the user's self-provided API keys and BaseURLs configured in the settings page. 
3. OPENAI SPEC COMPATIBILITY: All external AI video calls route directly to the user's configured provider (e.g., glosc ai one) using standard OpenAI endpoint structures, mapping tasks through custom headers or specific endpoints (e.g., `/videos/generations`).

## Essential Commands & Compilation
Ensure you run the correct commands for this specific hybrid setup:
- `flutter pub get` : Fetch Flutter dependencies
- `flutter run` : Run the Flutter application on connected Android device/emulator
- `gomobile bind -target=android/arm64` : Compile and bind the Go core into `.aar` / `.so` for Flutter plugin integration. Run this inside `lib/go_core/` whenever Go files change.

## Key Directory Structure
- `lib/` — Flutter frontend codebase
  - `lib/main.dart` — App root & dependency initialization
  - `lib/screens/` — UI Pages: `create_workspace.dart` (Workspace), `task_orbit.dart` (Queue), `private_gallery.dart` (Gallery), `settings_panel.dart` (Configuration)
  - `lib/bloc/` or `lib/provider/` — State management for tracking polling tasks and local metadata.
  - `lib/go_core/` — Embedded Go Backend Source (compiles to android binary via gomobile)
- `android/` — Native Android project wrappers (handling MediaStore API integration and native MethodChannels)

## Security & Storage Enforcement (Industry Standards)
1. API Credentials Protection: NEVER store BaseURL or API Key in cleartext via `SharedPreferences`. You MUST use `flutter_secure_storage`, which automatically maps secrets onto the hardware-backed Android Keystore System using AES-256 encryption.
2. Scoped Storage Compliance: The app targets Android 14 (API 34+). NEVER request or write code utilizing `MANAGE_EXTERNAL_STORAGE` or raw path manipulation outside the app sandbox. 
   - Temporarily downloaded videos must go into the app's isolated private cache (`path_provider`'s `getApplicationDocumentsDirectory()`).
   - Exporting to the user's device gallery MUST utilize the Android `MediaStore` API, targeting the relative path `Movies/WeaveFlux`.

## Code Style Guide
- Dart/Flutter: Follow standard Effective Dart guidelines. Use PascalCase for classes, camelCase for variables/functions. Use `const` constructor optimizations everywhere applicable.
- Go Mobile: Keep exportable functions simple. Go Mobile restricts types passed across the boundary (prefer raw strings, ints, or basic byte arrays over complex Go structs). Ensure exportable functions start with capital letters.
- Comments: Chinese preferred for inside-code annotations and reasoning.

## AI Collaboration & Transparency Rules
- Brainstorm Before Realizing: If a user instruction asks to build a new feature, analyze if it introduces external server dependencies. If it does, reject or propose a purely client-side local implementation alternative.
- Architecture Checkpoint: Before making large structural changes to Dart-to-Go platform channels, list the exact methods being modified, possible breaking boundaries, and fallback logic if Go routines crash due to device network loss.