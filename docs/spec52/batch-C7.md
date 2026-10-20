# Batch C7 — Charging-agency branches in the app (spec item 36, Flutter only)
Read `docs/spec52/RULES.md`, then SPEC.md item 36 and AUDIT.md section 36.
The BACKEND is already done and must not be changed (unless a real bug blocks the UI — then fix it
minimally and say so in the notes). Read these first to learn the exact request/response shapes:
`backend/src/agencies/agencyIdentity.controller.ts`, `backend/src/services/agencyIdentity.service.ts`,
`backend/src/agencies/agency.routes.ts` (routes `/agencies/:id/branches`, POST, PATCH
`/:id/branches/:branchId`, GET `/:id/branches/:branchId/transfers`), and the branch attribution in
`backend/src/controllers/charging-agency.controller.ts`.

Main files: `app/lib/screens/charging_agent_screen.dart`, `app/lib/services/agency_service.dart`
(or a small new `app/lib/services/agency_branch_service.dart`), optionally one new screen
`app/lib/screens/agency_branches_screen.dart`. Do NOT touch room_screen.dart, gifts/**, chat, or
AndroidManifest/MainActivity (another developer is editing those).

## What to build
- Parent agency OWNER (charging agency): «الفروع» entry in the charging-agent screen → list of
  branches (Branch ID, name, owner (name + displayId), status active/suspended, created at),
  create branch (name + owner by user displayId/ID), rename, suspend/activate (PATCH), and per
  branch its transfers (amount, coins, user, time, transaction id) via the transfers endpoint,
  paginated if the API supports it.
- BRANCH owner: sees ONLY his own branch (name, status) and his own transfers — never sibling
  branches or the parent's combined list. Rely on what the server returns; never filter money
  data client-side as the only protection.
- Every charge row shows Parent Agency, Branch (or «الوكالة الرئيسية»), user, amount/coins, time,
  transaction id.
- Server error messages shown as-is (Arabic) in a SnackBar; loading/empty/error states; RTL;
  works at phone width; no hard-coded colors that break the existing dark theme.
- `flutter analyze` must report no errors/warnings in the files you touched.

Notes file: `docs/spec52/notes-C7.md` (what was built, screens, anything not done).
