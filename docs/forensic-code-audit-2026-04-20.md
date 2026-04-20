# Forensic Code Audit — SamaFox

Date: 2026-04-20 (UTC)

## Scope and method
- Repository-level file inventory (`rg --files`, `find backend/src -type f`).
- Static backend route/controller/service review with line-level inspection.
- Flutter entrypoint/socket layer review for user-facing flow and lifecycle handling.
- Build/health checks (`npm run build`), dependency checks attempted (`npm audit`, `npm outdated`, `flutter --version`).

---

## PHASE 1 — STRUCTURAL INVENTORY

### Top-level structure
- `backend/` Node.js + TypeScript API, Socket.IO realtime server, Prisma ORM (SQLite).
- `app/` Flutter mobile app.
- `docs/` design/audit notes.
- Security-sensitive artifact present at repo root: `SamaFox-NewServerKey.pem`.

### Backend module map
- Entrypoint: `backend/src/index.ts`.
- Middlewares: auth/admin/rate limiting under `backend/src/middlewares/`.
- REST route modules under `backend/src/routes/` and feature route folders (`follow/`, `relations/`, `search/`, `gifts/`, `agencies/`).
- Controllers under `backend/src/controllers/` plus feature controllers under `follow/`, `relations/`, `search/`, `gifts/`, `agencies/`.
- Services under `backend/src/services/` including a very large `socket.service.ts` realtime orchestrator.
- Prisma schema/migrations in `backend/prisma/`.

### API/route inventory (mounted)
From `backend/src/index.ts`, active mounts include:
- Admin/dashboard/auth: `/api/v1/admin`, `/api/v1/admin-dashboard`, `/api/v1/admin-dashboard-auth`, `/admin-dashboard*` compatibility paths.
- Auth/users/rooms/messages/gifts/upload/store/search/follow/relations/notifications.
- Real-time via Socket.IO initialized in `initializeSocketHandlers(io)`.

### Flutter module map (user-facing)
- App bootstrap + route table in `app/lib/main.dart`.
- Main navigation/screens under `app/lib/screens/*`.
- Network/realtime services in `app/lib/services/*`.
- State providers in `app/lib/providers/*`.

### Tech stack + declared dependency baseline
- Backend: Express 5.1, Socket.IO 4.8, Prisma 6.17, jsonwebtoken 9.x, multer 2.x.
- Mobile: Flutter SDK (not available in audit environment), Riverpod + Provider, Dio + Retrofit, socket_io_client 2.x.

### Deprecated/outdated/vulnerable packages
- Could not confirm latest/vulnerable status via registry due environment-level npm 403 on `npm audit` and `npm outdated`.
- Risk note: dependency freshness and CVE posture are unverified in this environment.

### Architecture anti-patterns observed
- Duplicate/parallel feature implementations for gifts (`controllers/gift.controller.ts` and `gifts/gift.controller.ts`) and follows (`controllers/user.controller.ts` relationship flow vs `follow/follow.controller.ts` follow table flow).
- God-object service: `socket.service.ts` handles auth, chat, gifts, moderation, seat state, queue state, notifications in one file with heavy shared mutable in-memory maps.
- Multiple backup/disabled historical files committed (`*.backup`, `*.old`, `*.DISABLED`, `*.correct`) increasing drift risk.

---

## PHASES 2–8 FINDINGS (grouped by severity)

## CRITICAL

### 1) Hardcoded private key committed to repository
SEVERITY: CRITICAL  
FILE: `SamaFox-NewServerKey.pem` (line 1)  
TYPE: security  
ISSUE: A full RSA private key is committed in plaintext.  
IMPACT: Immediate credential compromise risk; key can be exfiltrated and abused for server access or impersonation.  
FIX: Revoke/rotate key immediately, remove from repo/history, move to secure secret manager, add secret scanning/pre-commit checks.

### 2) Insecure JWT secret fallback enables token forgery if env missing
SEVERITY: CRITICAL  
FILE: `backend/src/utils/jwt.ts` (line 6)  
TYPE: security  
ISSUE: JWT signing/verifying falls back to `'your-secret-key'` and `'your-refresh-secret-key'` when env vars are absent.  
IMPACT: Attackers can mint valid tokens in misconfigured environments; complete auth bypass.  
FIX: Fail-fast startup when secrets are absent (throw on boot), remove all static defaults, enforce secret length/entropy checks.

### 3) Plaintext password fallback in login path
SEVERITY: CRITICAL  
FILE: `backend/src/controllers/auth.controller.ts` (line 207)  
TYPE: security  
ISSUE: On bcrypt compare error, login falls back to plaintext equality (`user.passwordHash === password`).  
IMPACT: Supports insecure stored plaintext passwords and weakens authentication guarantees; increases breach blast radius.  
FIX: Remove plaintext fallback; migrate legacy plaintext hashes with one-time forced reset/re-hash migration.

### 4) IDOR: inventory activation updates arbitrary inventory record
SEVERITY: CRITICAL  
FILE: `backend/src/routes/store.routes.ts` (line 107)  
TYPE: security  
ISSUE: `/activate` updates `userItem` by `id` only, without scoping to current `userId`.  
IMPACT: Authenticated attacker can activate/deactivate other users’ inventory items if IDs are guessed/leaked.  
FIX: Update with compound scope (`where: { id, userId }`) or `updateMany` with ownership guard and check affected row count.

## HIGH

### 5) Host header injection -> SSRF vector in admin dashboard auth flow
SEVERITY: HIGH  
FILE: `backend/src/routes/admin-dashboard-auth.routes.ts` (line 39)  
TYPE: security  
ISSUE: Builds internal fetch target from `req.get('host')`, then server performs `fetch()` to that URL.  
IMPACT: Crafted Host headers can redirect server-side request to attacker-controlled/internal destinations.  
FIX: Use fixed internal base URL from trusted config/env, never from request Host.

### 6) Path traversal risk in file deletion endpoint
SEVERITY: HIGH  
FILE: `backend/src/controllers/upload.controller.ts` (line 117)  
TYPE: security  
ISSUE: `path.join(uploadsDir, filename)` uses untrusted path segment without normalization/containment checks.  
IMPACT: `../` traversal can delete files outside uploads directory.  
FIX: Reject path separators, normalize and assert resulting path starts with `uploadsDir`, or map by opaque file IDs only.

### 7) CORS allow-all fallback when not configured
SEVERITY: HIGH  
FILE: `backend/src/index.ts` (line 50)  
TYPE: security  
ISSUE: If `CORS_ORIGIN` is empty, all origins are allowed by default.  
IMPACT: Browser clients from untrusted origins can issue credentialed requests depending on cookie/token usage.  
FIX: Default-deny CORS in production and require explicit origin allowlist.

### 8) Sensitive internal error detail reflected to clients
SEVERITY: HIGH  
FILE: `backend/src/index.ts` (line 159)  
TYPE: security  
ISSUE: Global error handler returns raw `err.message` to clients.  
IMPACT: SQL/schema/internal implementation details leak, aiding exploitation and reconnaissance.  
FIX: Return generic user-safe messages; log full details server-side only with request correlation IDs.

### 9) Monetary arithmetic uses Number with BigInt conversions (overflow/precision risk)
SEVERITY: HIGH  
FILE: `backend/src/services/socket.service.ts` (line 1046)  
TYPE: logic-bug  
ISSUE: Large coin values are converted from BigInt to Number for DB increments/decrements in financial paths.  
IMPACT: Precision loss / overflow may corrupt balances and transactions for high values.  
FIX: Use DB bigint columns + Prisma bigint handling end-to-end; disallow unsafe casts to Number.

### 10) Unbounded in-memory room state maps cause memory growth/leak over uptime
SEVERITY: HIGH  
FILE: `backend/src/services/socket.service.ts` (line 12)  
TYPE: perf  
ISSUE: Global maps for seats/mutes/queues/admins/voice/locked seats are never garbage-collected per empty room lifecycle.  
IMPACT: Long-running process can accumulate stale room state and degrade memory/perf.  
FIX: Implement room teardown cleanup when room empties and periodic scavenger for stale room IDs.

## MEDIUM

### 11) Admin product upload middleware lacks try/catch in admin guard
SEVERITY: MEDIUM  
FILE: `backend/src/routes/adminProduct.routes.ts` (line 9)  
TYPE: crash  
ISSUE: Async middleware directly awaits DB call without error handling.  
IMPACT: DB failure bubbles as 500; behavior depends on global handler and may leak details.  
FIX: Wrap in try/catch and return controlled error response.

### 12) Duplicate follow systems create data inconsistency
SEVERITY: MEDIUM  
FILE: `backend/src/controllers/user.controller.ts` (line 209)  
TYPE: logic-bug  
ISSUE: `user.controller` follow endpoints use `Relationship`, while other follow features use `Follow` table.  
IMPACT: follower counts/status/UI can diverge by endpoint, causing stale or contradictory user state.  
FIX: Consolidate to one follow model + one route family, migrate data, remove duplicate pathways.

### 13) Message reaction endpoint lacks authentication guard
SEVERITY: MEDIUM  
FILE: `backend/src/routes/messages.routes.ts` (line 54)  
TYPE: security  
ISSUE: `POST /:id/react` has no auth middleware.  
IMPACT: Unauthenticated clients can spam reaction endpoint and generate noisy state/events once persistence is added.  
FIX: Require auth and validate user’s authorization to react in conversation context.

### 14) Duplicate gift endpoints with inconsistent auth behavior
SEVERITY: MEDIUM  
FILE: `backend/src/routes/gift.routes.ts` (line 11)  
TYPE: logic-bug  
ISSUE: `/send` is authenticated, but legacy `/sendGift` applies only rate limiter and still calls same handler.  
IMPACT: Inconsistent API contract and avoidable attack surface/noise for unauthenticated requests.  
FIX: Gate all send endpoints with auth or remove deprecated route.

### 15) Store purchase duplicate treated as HTTP 200 error state
SEVERITY: MEDIUM  
FILE: `backend/src/routes/store.routes.ts` (line 48)  
TYPE: logic-bug  
ISSUE: Duplicate purchase returns status 200 while semantically representing conflict/duplicate operation.  
IMPACT: Client success/error handling ambiguity and hard-to-debug state logic.  
FIX: Return 409 (or 208 if intentional idempotency contract documented) with explicit status semantics.

### 16) Pagination parameters not bounded in several endpoints
SEVERITY: MEDIUM  
FILE: `backend/src/controllers/room.controller.ts` (line 9)  
TYPE: perf  
ISSUE: `limit` and `page` are accepted as Numbers without strict upper bounds in room listing/messages routes.  
IMPACT: Expensive queries and potential denial-of-service amplification through huge limits.  
FIX: Clamp limits globally (e.g., max 100) and validate integer ranges.

## LOW

### 17) Dead/legacy files committed in active source tree
SEVERITY: LOW  
FILE: `backend/src/services/socket.service.ts.backup` (line 1)  
TYPE: dead-code  
ISSUE: Multiple backup/old/disabled source files remain committed in runtime code directories.  
IMPACT: Developer confusion, accidental import drift, larger review surface, and stale logic resurrection risk.  
FIX: Remove archival files from repo or move to versioned docs/archive folder.

### 18) TODOs in user-visible screens indicate incomplete UX/error paths
SEVERITY: LOW  
FILE: `app/lib/screens/settings_screen.dart` (line 424)  
TYPE: edge-case  
ISSUE: Important flows such as logout/delete account are TODO placeholders.  
IMPACT: User cannot complete expected account lifecycle actions from UI; inconsistent product behavior.  
FIX: Implement and test complete flows with loading/success/error handling.

### 19) Diagnostic logging includes token prefixes and sensitive runtime metadata
SEVERITY: LOW  
FILE: `backend/src/services/socket.service.ts` (line 203)  
TYPE: security  
ISSUE: Socket auth logs token prefixes and extensive per-user debug output.  
IMPACT: Increases sensitive data exposure in logs and operational noise.  
FIX: Remove/guard debug logs behind secure log level controls and redact credentials.

---

## PHASE 3 — FEATURE TRACE (end-to-end)

### Auth lifecycle
UI (`app/lib/main.dart` routes `/login`, `/register`) -> API `/api/v1/auth/*` -> Prisma user tables -> token issuance.  
Primary breakpoints:
- plaintext fallback in login, weak secret fallback, and reflected errors in failure path.
- refresh token flow has no revocation/rotation store; replay remains possible.

### Room + realtime lifecycle
UI room screens -> socket events (`join_room`, `take_seat`, `send_message`, `send_gift`) -> Prisma updates -> room broadcasts.  
Primary breakpoints:
- in-memory authority/state divergence vs DB truth (seats/admin cache), stale maps, and overflow-prone monetary conversions.
- concurrent seat/mic operations rely on mutable memory without distributed locking (multi-instance risk).

### Store/inventory lifecycle
UI store screens -> `/api/v1/store/buy`, `/inventory`, `/activate*` -> Prisma item/userItem/user rows.  
Primary breakpoints:
- IDOR in `/activate` ownership check missing.
- mixed status semantics on duplicate purchase.

### Follow/relations lifecycle
UI events/notifications -> `/api/v1/follow/*` and `/api/v1/users/:id/follow` mixed endpoints -> `Follow` + `Relationship` tables + socket notifications.  
Primary breakpoints:
- dual data models cause inconsistent counts/status and brittle UX across screens.

### Upload lifecycle
UI upload endpoints -> multer disk write -> URL persisted on user/profile -> static file served from `/uploads`.  
Primary breakpoints:
- filename/path trust in delete path and inconsistent validation/content-type checks.

---

## PHASE 4 — DATA & STATE INTEGRITY
- Non-atomic multi-step updates are mostly wrapped in transactions for gifts/transfers, but some ancillary writes (notifications, agency earnedCoins) happen post-transaction and can diverge from core state.
- Dual follow schemas (`Follow` vs `Relationship`) create stale/inconsistent follower state.
- Realtime room state is primarily in-memory; DB and socket state can diverge after reconnect/restart.

## PHASE 5 — SECURITY AUDIT SUMMARY
- AuthN weaknesses: JWT fallback secrets; plaintext password fallback.
- AuthZ weakness: inventory IDOR.
- Secret handling: private key committed.
- SSRF/path traversal vectors exist.
- CORS default permissive when env missing.
- Rate limiting only appears on gifts; broad API abuse controls not consistently applied.

## PHASE 6 — ERROR HANDLING & RESILIENCE
- Many controllers swallow error specifics with generic 500 (safe), but global handler leaks `err.message` for uncaught paths.
- External dependency fallback checks (schema drift compatibility) increase complexity and hidden failure modes.
- Socket service lacks bounded cleanup/recovery strategy for long uptime.

## PHASE 7 — EDGE CASES
- Large numeric values can overflow Number conversions in coin operations.
- Pagination/query limits often unconstrained.
- Incomplete UI TODO states for account-critical actions.

## PHASE 8 — DEAD CODE & TECH DEBT
- High quantity of backup/old/disabled files in source tree.
- Duplicated feature implementations (gift/follow/socket variants).
- Extensive inline debug comments and compatibility patches indicate schema/client drift debt.

---

## Category scorecard (0–10; 10 = no issues)
- Architecture consistency: 4/10
- Runtime correctness: 5/10
- Data integrity: 5/10
- Security: 2/10
- Error handling/resilience: 5/10
- Performance/scalability: 5/10
- Maintainability/debt: 3/10

## Top 5 most critical fixes first
1. Remove/rotate leaked private key and purge git history exposure.
2. Remove JWT fallback secrets; enforce required strong env secrets.
3. Remove plaintext password fallback and migrate legacy credentials.
4. Fix store `/activate` IDOR by enforcing per-user ownership in write queries.
5. Fix Host-header-based internal fetch (SSRF) and lock internal auth integration to trusted base URL.

## Prioritized fix order
1. **Emergency security containment (same day):** key rotation, secret enforcement, auth hardening.
2. **Authorization/data protection (day 1–2):** IDOR, path traversal, CORS default deny, message auth gaps.
3. **Monetary correctness (day 2–4):** remove unsafe Number conversions from coin flows.
4. **State consistency (week 1):** unify follow model, deprecate duplicate endpoints/files.
5. **Resilience/perf hardening (week 1+):** socket map lifecycle cleanup, pagination caps, centralized validation.
