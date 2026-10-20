You are auditing the SamaFox repo (Flutter app in app/, Node/Express/Prisma/Socket.IO backend in backend/, admin dashboard in backend/public/*.html|js and backend/public/gifts-admin) against the spec in docs/spec52/SPEC.md (Arabic, 52 numbered items).

DO NOT modify any source file. Your ONLY output is a new file docs/spec52/AUDIT.md.

For EVERY numbered item 1..51 write a section:
### <n>. <short english title>
- Current state: what already exists (exact file paths + function/widget/route/model names, line numbers when useful). Be concrete; grep the code, do not guess.
- Gap: what is missing or broken vs the spec.
- Plan: the minimal, safe changes needed (backend files, prisma models/migration, socket events, Flutter files, admin dashboard files). Reuse existing systems (e.g. existing audit log service, VIP service, CP service, gift service, idempotency middleware, room seat state, LiveKit voice engine, notification service) instead of inventing parallel ones.
- Risk/notes: anything that touches money, prod data, or the native Android layer; anything that needs a device to verify.
- Size: S / M / L.

Also add at the top: (a) a short architecture map (where room state, seats, voice, gifts, CP, VIP, store/products, agencies, admin auth/roles/permissions, audit log, notifications, messages/DMs live), (b) the list of socket event names used for room/gift/seat, (c) how admin roles/permissions currently work, (d) how prisma migrations are written in backend/prisma/migrations (naming/format).

Be thorough but factual. Write in English.
