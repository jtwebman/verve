# Verve Roadmap

One language, one monorepo: backend APIs, desktop apps, mobile apps — all native, all safe, all auditable by AI.

## Now — Backend Foundation (weeks)

- [x] Process model with bounded mailboxes
- [x] TCP networking
- [x] JSON scanning API
- [ ] JSON typed struct parsing
- [ ] HTTP server (Tcp + JSON + routing)
- [ ] HTTP client
- [ ] Database driver (PostgreSQL)
- [ ] Auth patterns (JWT, session)

## Next — Tooling & Ecosystem (weeks)

- [ ] LSP (Language Server Protocol) — editor support
- [ ] Package manager (`verve install`, `verve publish`)
- [ ] Signed source packages — AI-auditable dependencies
- [ ] WASM compilation target — browsers, edge functions
- [ ] `verve doc` — generate docs from doc comments

## Then — Desktop Native (weeks)

- [ ] C FFI — call native libraries
- [ ] Linux: GTK bindings
- [ ] macOS: Cocoa/AppKit bindings
- [ ] Windows: Win32/WinUI bindings
- [ ] UI component model — structs define views, processes handle state + events
- [ ] Shared business logic across all platforms

## Then — Mobile Native (weeks)

- [ ] iOS: UIKit/SwiftUI bindings via FFI
- [ ] Android: Jetpack Compose bindings via JNI/FFI
- [ ] Shared code: API calls, data models, business logic
- [ ] Platform-specific: thin UI layer per platform (5 targets)

## The Vision

Write your backend, desktop app, and mobile app in one language. Share business logic, data models, and API clients across all platforms. Each platform gets native UI components — not a cross-platform rendering engine. Process model handles all async, networking, and state management naturally.

Signed source-code packages mean your AI can audit every dependency. Compiled to native binaries — fast startup, small footprint, no runtime. The language is designed so AI writes correct code on the first attempt and humans can verify it at a glance.
