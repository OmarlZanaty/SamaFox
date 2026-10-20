# Rules for every SPEC52 Codex batch (read first)

Repo: SamaFox. Flutter app in `app/`, Node/Express/Prisma/Socket.IO backend in `backend/`
(TypeScript in `backend/src`, compiled to `backend/dist` — never edit dist), admin dashboard
static files in `backend/public/` (`admin-dashboard.html`, `app.js`, `economy-admin.js`,
`staff-admin.js`, `gifts-admin/`). Full spec: `docs/spec52/SPEC.md` (Arabic). Code audit with
exact file/line pointers for every item: `docs/spec52/AUDIT.md` — read the sections for your
items before coding; they are accurate.

Hard rules
1. Server is the authority for anything involving permissions, coins, VIP, CP, rewards, agencies,
   store, IDs. Flutter only renders and sends intents. Every new endpoint checks auth + permission.
2. Money/reward/CP/ID operations: one Prisma `$transaction` (Serializable where balances are read),
   guarded decrements (`updateMany where coinsBalance >= x`), idempotent via the existing
   `idempotent(...)` middleware (`backend/src/middlewares/idempotency.middleware.ts`) and/or unique
   business keys. Never double-charge on retry.
3. Admin mutations write `recordAdminAudit` (`backend/src/services/adminAudit.service.ts`) with real
   before/after values, inside the same transaction when the change is financial/permission-related.
4. Database: additive, safe migrations only. Add models/columns to `backend/prisma/schema.prisma`
   AND a hand-written SQL migration in `backend/prisma/migrations/<timestamp>_<name>/migration.sql`
   (timestamps 202610200000xx … use the one given in your batch), using
   `CREATE TABLE IF NOT EXISTS`, `ADD COLUMN IF NOT EXISTS`, explicit defaults, no data deletion,
   quoted mapped table names exactly like existing migrations. Backfills must be idempotent.
5. Backward compatibility: installed app builds (older clients) must keep working. Keep existing
   socket event names/payload fields; add new fields/events next to them.
6. Socket rule (codex.md): every new server emit has a Flutter listener and vice versa; keep names
   consistent; no duplicate emits.
7. UI text is Arabic (RTL). Follow existing widget/style conventions (look at neighbouring code,
   `app/lib/theme`, `app/lib/l10n/app_strings.dart`). Everything responsive: use LayoutBuilder /
   MediaQuery / SafeArea, no fixed screen sizes. Test sizes: 360x640 (Realme C3), 393x873, 412x915.
8. Performance: no heavy work on the UI thread; cap concurrent animations; dispose controllers;
   respect `DeviceTier` lite modes.
9. Do not touch files unrelated to your batch. Do not reformat whole files. Do not delete existing
   features unless the spec says so. Do not commit (the reviewer commits). Do not edit
   `app/pubspec.yaml` version line.
10. You may try `cd backend && npx tsc --noEmit -p .` and `cd app && flutter analyze <files>`; if the
    sandbox blocks them, continue — the reviewer runs them. Write code that compiles: check imports,
    names, nullability, and Prisma field names against the schema you edited.
11. Add focused unit tests where cheap (backend `src/**/__tests__/*.test.ts` using the existing
    in-memory fake style; Flutter `app/test/`).
12. When done, write `docs/spec52/notes-<batch>.md` (English, concise): per spec item → what you
    did, files changed, new/changed APIs (method + path), socket events, migration dir, new
    tables/fields, new permissions/settings keys, anything not done and why, and what needs a real
    device to verify.
13. ENCODING (mandatory): Arabic text must be written as UTF-8. Never write files through
    PowerShell `Set-Content`/`Out-File`/`>` redirection — use apply_patch only. Before finishing,
    search your changes for `????` (corrupted Arabic) and fix every occurrence.
