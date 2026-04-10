# Socket Event Audit (Backend vs Flutter)

Date: 2026-04-09

## Scope scanned

- Backend runtime entrypoint and handlers:
  - `backend/src/index.ts`
  - `backend/src/services/socket.service.ts`
- Flutter client sources:
  - Repository-wide search for `*.dart` files and socket listeners.

---

## 1) Backend socket event map

### Client -> Server (`socket.on(...)` handlers in backend)

- `send_dm`
- `seat_lock`
- `take_seat`
- `init_room_seats`
- `join_room`
- `leave_room`
- `send_message`
- `typing`
- `request_mic`
- `cancel_mic_request`
- `approve_mic`
- `reject_mic`
- `set_seat_mute`
- `remove_from_seat`
- `leave_seat`
- `toggle_mute`
- `send_gift`
- `user_joined_voice`
- `get_voice_users`
- `user_left_voice`
- `webrtc_offer`
- `webrtc_answer`
- `webrtc_ice_candidate`
- `disconnect`

### Server -> Client (`emit(...)` calls from backend)

- `room_seats_state`
- `voice_users`
- `dm_new_message`
- `dm_conversation_updated`
- `seat_lock`
- `seat_error`
- `seat_occupied`
- `seat_effect`
- `user_joined`
- `mic_queue_updated`
- `seat_released`
- `user_left`
- `new_message`
- `typing`
- `approveMic`  ← camelCase (not snake_case)
- `seat_mute_changed`
- `gift`
- `gift_error`
- `user_joined_voice`
- `user_left_voice`
- `webrtc_offer`
- `webrtc_answer`
- `webrtc_ice_candidate`

---

## 2) Flutter socket listener map

### Result

No Flutter source files were found in this repository snapshot:

- No `pubspec.yaml` file
- No `*.dart` files

Therefore, there are no in-repo Flutter `socket.on(...)` listeners to map from code.

---

## 3) Detected mismatches

Because Flutter sources are absent, hard validation is limited. However, the following likely mismatches/risk points are visible from backend contracts alone:

1. **Naming convention drift**
   - Most events use `snake_case` (e.g., `approve_mic`, `join_room`, `mic_queue_updated`).
   - One emitted event uses `camelCase`: `approveMic`.
   - If Flutter consistently listens with snake_case (`approve_mic`), approval notifications will be missed.

2. **One-way pair asymmetry**
   - Client sends `approve_mic`, server emits `approveMic`.
   - This is a non-obvious API contract and easy to wire incorrectly on client side.

3. **Potential undocumented events**
   - `seat_effect` is emitted with double-quoted event syntax in TS code and may be absent from client docs if event lists were generated with single-quote-only regex tooling.

4. **Legacy protocol residue in repo**
   - Old files (`socket.service.ts.old`, `socket.service.ts.old2`, `socket.service.ts.with-relations`, `backend/socket-server.js`) contain older namespaces (`webrtc:...`, `room:...`) that differ from active runtime (`webrtc_...`, `join_room`, etc.).
   - If Flutter was built against those legacy names, events will mismatch despite backend working as implemented now.

---

## 4) Suggested fixes

### A) Stabilize event naming (recommended)

Pick one convention (prefer `snake_case`) and enforce it.

- Rename backend emit `approveMic` -> `approve_mic` (or emit both during migration).
- Add an `events.ts` shared constant file in backend to avoid literal strings scattered across handlers.

### B) Backward-compatible migration window

For high-risk events, emit aliases temporarily:

- Emit both `approveMic` and `approve_mic` for one or two app releases.
- Log deprecation warnings server-side when old names are consumed (if tracking acknowledgements).

### C) Generate a contract artifact

Add a generated JSON/Markdown contract (CI step) from backend event constants:

- `clientToServer`
- `serverToClient`
- payload schemas (at least documented shape)

Have Flutter integration tests validate listeners against this artifact.

### D) Remove or quarantine legacy socket files

To reduce accidental client drift:

- Move non-runtime legacy socket files to an archive folder and mark clearly non-authoritative.
- Add a short `SOCKET_PROTOCOL.md` that points to the active handler file only.

### E) Add smoke tests

Create a lightweight socket integration test that:

- Connects two test users
- Exercises `join_room`, `approve_mic`, `send_message`, `send_dm`, `send_gift`, `webrtc_offer`
- Asserts exact emitted event names

This catches regressions in naming and payloads before client breakage.

---

## Quick action plan

1. Decide naming standard (`snake_case` everywhere).
2. Add alias for `approveMic` immediately.
3. Publish `SOCKET_PROTOCOL.md` from source-of-truth constants.
4. Once Flutter repo is available, run a cross-repo event diff and remove alias after rollout.
