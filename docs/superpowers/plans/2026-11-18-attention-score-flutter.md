# Flutter Attention Score Implementation Plan

> **For agentic workers:** Use executing-plans task by task. Independent ABI, Dart, and Flutter work may run in parallel against the interface below.

**Goal:** Show SDK attention scores in a dedicated Flutter view before extending the other examples.

**Architecture:** A processed subscription owns an optional attention consumer and bounded ordered queue. New polling exports avoid changing the existing port message kinds and delivery masks. Dart exposes configuration and bounded polling; Flutter owns polling and bounded display history independently of its selected view.

**Tech Stack:** Rust axon-api/axon-ffi, Dart FFI, Flutter CustomPainter.

**Spec:** ../../attention-score-flutter-design.md (approved 2026-11-18).

## Global Constraints

- All-channel unfiltered EEG input; default native reference and scoring algorithm.
- Fixed 0–100 plot, 200 results, two-second windows, distinct artifact status.
- Keep history across view switches and manual stop; clear on restart/source change.
- Only Flutter example changes this round. Preserve existing ABI contracts and bindings.
- Work in the existing sibling checkouts to preserve their relative Dart dependency.

## Shared Interface

- `axon_subscription_set_attention_score(AxonSubscriptionHandle*)`, `axon_subscription_clear_attention_score(AxonSubscriptionHandle*)` return `AxonResult`.
- `axon_subscription_poll_attention_score(AxonSubscriptionHandle*, AxonAttentionScoreEvent*)` returns `AxonResult` and one queued event (kind 0 if empty).
- DTO schema 1, size 304, align 8: u32 struct_size, u32 struct_version, u32 kind, u32 reserved, i64 timestamp, f64 score, f64 mean_ratio, f64 raw_score, char diagnostic[256]. Timestamp is epoch microseconds. Only fresh events have meaningful ratio/raw score.
- Kinds: 0 empty, 1 fresh, 2 heldArtifact, 3 reset, 4 processingError, 5 failed, 6 suspended, 7 resumed, 8 closed.
- Dart `AxonSubscription.configureAttentionScore()`, `clearAttentionScore()`, `List<AttentionScoreEvent> pollAttentionScores({int maxEvents = 64})`.
- Immutable Dart `AttentionScoreEvent` named constructor fields: required `kind` (`AttentionScoreEventKind`, same names without empty), `timestamp=0`, `score=0`, nullable `meanRatio`, `rawScore`, `message`.

## Review Focus

- Parent closure and concurrent clear must retire the consumer safely.
- Event/error recovery order must survive delayed polling; failures must not show stale success.
- Empty/initial artifact windows must not be confused with a fresh valid zero.
- Missing native symbols must yield a useful Flutter error without stopping existing views.
- Small windows and view switches must preserve layout and collected history.

### Task 1: Native score polling

Files: axon-ffi new attention module/test, lib.rs, ffi.rs, objects.rs, include/axon.h, attention guide.

- [ ] Write failing tests for score/held conversion, bounded ordering, reset/failure handling, raw rejection and parent cleanup.
- [ ] Run focused tests and confirm missing interface failure.
- [ ] Implement shared exports and subscription-owned lifecycle using the existing native metric.
- [ ] Run focused tests, header smoke, workspace tests; format modified Rust files only.

### Task 2: Dart score interface

Files: bindings/dart/lib/src/attention_score.dart, session.dart, axon.dart, tests and binding README.

- [ ] Write failing tests for decoding fresh/held/status and invalid maxEvents, native simulated score when available.
- [ ] Implement shared interface with lazy symbol lookups and normal subscription error handling.
- [ ] Run Dart analyze/test against rebuilt native library.

### Task 3: Flutter curve and integration

Files: flutter/lib/attention_score.dart, app.dart, test/attention_score_test.dart, README.md.

- [ ] Write failing tests for initial state, fresh/held display, history limit, reset/error/recovery and stop/restart behavior.
- [ ] Implement a change-notifying bounded history model and CustomPainter with timestamp-based gap-aware curve; wire independent unfiltered subscription and timer at screen level.
- [ ] Run Flutter analyze/test/build Windows; launch simulator to inspect score curve, view switching, and stop/restart.
- [ ] Review full diff and report actual checks and any limitations.

## Execution result — 2026-11-18

Native, Dart and Flutter implementations complete in the existing sibling checkouts, without commits. A separate reviewer found one input-overflow notification defect; its actual stalled-worker regression was verified RED→GREEN and the input now uses fail-on-overflow. A Flutter regression also covers an initial held zero after missing windows. The workspace export parity test was updated to include the new module. The missing-symbol Dart fixture was isolated from process-global native symbols after the native suite exposed interference.

Verification: Rust workspace passed; native header/Clippy/rustdoc passed; Dart 113 passed and 2 skipped; Flutter 17 passed, analyze clean, Windows Debug built; Python 120 passed plus 10 subtests; .NET 8/9/10 each 183 passed. Both repos pass diff checks. No Python/C# example changes. Actual desktop waiting/artifact/stop behavior verified; user stopped Computer Use with Escape before final normal-curve visual acceptance. Added the SDK EEG simulator option after the protocol simulator was observed to produce artifact-held results. Details: [verification record](../../attention-score-flutter-verification.md).
