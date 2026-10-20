# Batch C5 — Real room sharing (DM card + HTTPS App Links + deferred install) and screen recording with sound saved to the gallery
Spec items: 1, 32. Read `docs/spec52/RULES.md`, then AUDIT.md sections 1, 32.
Migration dir: `backend/prisma/migrations/20261020000060_room_share_tokens/`.
Domain: `https://samafox.almobarmg.com` (Caddy → node :3000 serves everything except /livekit).
Android package: check `app/android/app/build.gradle*` (applicationId). No Firebase Dynamic Links.

## 1 — Room sharing
- `RoomShareToken` (table `room_share_tokens`): id, token (unique, 22+ chars url-safe random),
  roomId, inviterId, roomName, roomImageUrl (snapshot), createdAt, expiresAt (default 7 days),
  revokedAt?, useCount, lastUsedAt.
- `POST /api/v1/rooms/:roomId/share {channel:'dm'|'external', recipientIds?}` → token + url
  `https://samafox.almobarmg.com/room/<token>`. channel 'dm': for each recipient create a DM
  (existing conversation/`DirectMessage` path, respecting `dmAccess.service.ts`) with
  `type:'room_invite'` and structured metadata `{token, roomId, roomName, roomImageUrl,
  roomDisplayId, inviterId, inviterName}` (add nullable `metadata Json` to DirectMessage if
  missing). `GET /api/v1/rooms/share/:token` (auth) → resolve: 404/expired →
  `{ok:false, code:'ROOM_UNAVAILABLE', message:'الغرفة غير متاحة حالياً'}`; room inactive/closed
  → same; banned (RoomBan / room_user_banned logic) → `{code:'BANNED', message:<reason>}`; full
  (online users ≥ room capacity if a capacity exists; otherwise treat as not full) →
  `{code:'ROOM_FULL', message:'الغرفة ممتلئة'}`; else `{ok:true, roomId, inviterId}`. Record the
  use (useCount, lastUsedAt) and remember inviterId on the RoomEntryLog / join (`invitedBy`).
  Locked rooms still require the PIN on join (token never bypasses PIN/bans).
- Landing page `GET /room/:token` (Express, public HTML, Arabic, room name/image preview from the
  token, buttons: "فتح في SamaFox" (intent URL + https link) and "تحميل من Google Play" →
  `https://play.google.com/store/apps/details?id=<package>&referrer=room_token%3D<token>`).
  `GET /.well-known/assetlinks.json` served from env `ANDROID_APP_SHA256` (comma list) +
  package name (document in notes that the Play App Signing SHA-256 must be set on the server).
- Android: intent-filter with `android:autoVerify="true"` for https host samafox.almobarmg.com
  pathPrefix `/room/` on MainActivity. Deep link handling in Flutter with the `app_links` package
  (add it to pubspec dependencies; pick a version compatible with Flutter 3.41 / Dart 3.x) for
  cold start + while running. Deferred install: Play Install Referrer — add Gradle dependency
  `com.android.installreferrer:installreferrer:2.2` and a small Kotlin method on the existing
  MainActivity method channel returning the referrer string once (first launch only, store a
  flag); parse `room_token`. Keep a pending token through login/registration, then resolve and
  open the room.
- Flutter UI: room ⋮ menu "مشاركة الغرفة" → share sheet: list of friends/recent conversations to
  send the card in SamaFox messages (multi-select, send), + "WhatsApp" (open
  `whatsapp://send?text=<encoded text + url>` with fallback to share_plus), + "نسخ الرابط", +
  "مشاركة…" (system share). Replace the old fake share in room settings.
- DM card in `app/lib/widgets/chat/message_bubble.dart`: "<inviter> يدعوك للانضمام إلى غرفة:" +
  room image + name + ID + [دخول الغرفة] → resolve token → navigate (existing room route) or show
  the server message.

## 32 — Screen recording with sound, saved to the gallery
- Existing: `ScreenRecordService.kt` (MediaProjection + MediaRecorder H.264/AAC with
  VOICE_COMMUNICATION mic), `MainActivity.kt` channel, `app/lib/services/screen_record_service.dart`.
- Goal: MP4 with screen video + microphone + the room's audio, saved to MediaStore
  (`Movies/SamaFox`, visible in Gallery), name `SAMAFOX_YYYYMMDD_HHMMSS.mp4`.
- Audio: room voice is played by WebRTC with USAGE_VOICE_COMMUNICATION, which Android's
  AudioPlaybackCapture cannot capture. Implement an in-app mixer: tap the flutter_webrtc
  JavaAudioDeviceModule callbacks — look in the pub cache
  (`C:/Users/user/AppData/Local/Pub/Cache/hosted/pub.dev/flutter_webrtc-1.3.0/android/...`) for
  the samples interceptors it already uses for its own MediaRecorder
  (`AudioSamplesInterceptor` / `OutputAudioSamplesInterceptor`, `setSamplesReadyCallback`,
  playback samples) and register a recorder interceptor for BOTH local mic samples and remote
  playback samples while recording; mix (sum with clipping, resample to 48 kHz mono/stereo) →
  `MediaCodec` AAC encoder; video from MediaProjection → `MediaCodec` H.264 surface encoder
  (VirtualDisplay on the encoder input surface, size = screen scaled to ≤ 720p width, 30 fps,
  ~4 Mbps); mux with `MediaMuxer` with proper timestamps. Fallback when the interceptors are not
  reachable: AudioPlaybackCapture (API 29+, USAGE_MEDIA/GAME/UNKNOWN — music/gift/game sounds) +
  mic AudioRecord mixed, and tell the user room voices may not be included.
- Saving: Android 10+ → MediaStore.Video insert with IS_PENDING=1, write, IS_PENDING=0 after the
  muxer is finalized; Android 9- → app-specific then MediaScannerConnection (WRITE_EXTERNAL_STORAGE
  maxSdk 28). Return the content URI to Flutter; snackbar "تم حفظ التسجيل في الاستوديو".
- Permissions per Android version (RECORD_AUDIO already; POST_NOTIFICATIONS for the foreground
  service notification on 13+; FOREGROUND_SERVICE_MEDIA_PROJECTION on 14+ already declared).
  Handle projection cancellation/revocation, screen off, leaving the room (stop + save).
- Must not disturb the room's voice: never open a second competing mic capture when the samples
  interceptor path is available.

Notes file: `docs/spec52/notes-C5.md`. Mark clearly what needs a device test.
