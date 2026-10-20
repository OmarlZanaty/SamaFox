# Batch A1 — Room layout + audio (noise suppression, auto routing, room mute, retain/leave, header, info popup, left rail, compact tabs, agency bell)
Spec items: 2, 3, 13, 14, 15, 18, 19, 27, 31. Read `docs/spec52/RULES.md` first, then the
AUDIT.md sections for these items. Main files: `app/lib/screens/room_screen.dart` (7k lines — edit
surgically; extracting new widgets into `app/lib/widgets/room/` is encouraged),
`app/lib/services/livekit_voice_engine.dart`, `app/lib/services/webrtc_audio_service.dart`,
`app/lib/services/audio_route.dart`, `app/lib/services/voice_engine.dart`,
`app/lib/widgets/room/room_chat_panel.dart`, `room_seats_chat_layout.dart`, `seats_grid.dart`,
Android `MainActivity.kt` / `AndroidManifest.xml` only if needed. Do not change VIP name colours
or gifts here. Inspect package sources in the pub cache
(`C:/Users/user/AppData/Local/Pub/Cache/hosted/pub.dev/livekit_client-*`, `flutter_webrtc-*`) to
use the real APIs of the pinned versions.

## 2 — Real noise suppression
- Apply on the live audio track: use LiveKit `AudioCaptureOptions(noiseSuppression, echoCancellation:
  true, autoGainControl: true, highPassFilter: true, typingNoiseDetection: true,
  voiceIsolation: <same as NS>)` and change it with `LocalAudioTrack.restartTrack(options)` (or
  the pinned version's equivalent) instead of unpublish/republish (goListenOnly→goLive), so speech
  is not cut and the seat/publish state is untouched. New tracks and reconnects must use the saved
  preference. Do the equivalent constraints (`googNoiseSuppression`, `googEchoCancellation`,
  `googAutoGainControl`, `googHighpassFilter`) in the mesh `webrtc_audio_service.dart` path.
- Settings toggle "تقليل الضوضاء" ON/OFF stays, default ON, persisted.

## 3 — Automatic audio routing, remove speaker button
- Remove every speaker/earpiece toggle from the room UI (header + menu). Keep the code path that
  others may call, but nothing in the room toggles speaker manually any more.
- Routing policy: no headset → loudspeaker; wired headset or Bluetooth connected → audio out AND
  mic switch to the headset automatically; on disconnect → back to loudspeaker + phone mic. BT
  with HFP/SCO uses the headset mic; output-only BT (A2DP) → keep phone mic, output to the best
  available route. Never leave/rejoin the room or republish because of a route change.
- Implementation hint: flutter_webrtc's Android AudioSwitch already prefers BT > wired > earpiece
  > speaker; use `Helper.setSpeakerphoneOnButPreferBluetooth()` / stop forcing
  `setSpeakerphoneOn(true)` from `AudioRoute`/`reapplyAudioRoute`, and listen to device changes
  (`Hardware.instance.onDeviceChange` / navigator.mediaDevices.ondevicechange) to re-apply the
  policy. Add a small native `AudioDeviceCallback` in `MainActivity.kt` only if needed to detect
  wired/BT plug events (emit on an existing method/event channel). Make music/gift players follow
  the same route (no separate speaker forcing). Add `BLUETOOTH_CONNECT` permission handling for
  Android 12+ if not present (request at room join, non-blocking).

## 13 — Leave / Retain on X, Back = retain
- Remove the standalone retain (PiP) button next to X.
- X opens a compact dialog "ماذا تريد أن تفعل؟" with [مغادرة] and [احتفاظ]. مغادرة = existing
  full leave (seat/audio cleanup). احتفاظ = existing PiP/retain handoff (`_handedOffToPip`,
  `pipProvider`, `active_room.dart`).
- System Back (and back gesture) inside the room = retain automatically (wrap in `PopScope`),
  except when a dialog/sheet/keyboard is open (then just close it).

## 14 — Bigger glass header
- After removing the speaker and retain buttons, give the name/ID more width. Build
  `app/lib/widgets/room/room_header_glass.dart`: rounded translucent "glass" rectangle (subtle
  gradient + 1px light border + light blur via BackdropFilter only inside the small rect) holding
  room name (MarqueeText if long) and `ID: <room display id>` (keep the ID source currently
  shown). Responsive, RTL, long Arabic names, 360px wide screens.

## 15 — Room info popup
- Tapping the room image opens a read-only Room Info sheet for EVERYONE: room image (large),
  name, Room ID, owner (avatar + name + display ID, tappable to profile), online users count, used
  mics count / total seats (from live `room_seats_state`). Owners/admins keep their edit/close
  actions as buttons inside this sheet (still server-authorized as today). Hidden entrants must not
  be counted/exposed. Premium dark glass style like pro voice-room apps.

## 18 — Local room mute 🔇
- Add a 🔇 icon in the room controls. Toggling mutes ALL incoming room audio for this user only
  (remote voice tracks via the engine's remote volume path, plus room music player and gift
  video/entrance sounds), does NOT touch the user's microphone or `toggle_mute`. Persist through
  track changes/new speakers/reconnect/PiP (re-apply on TrackSubscribed). Second tap restores the
  previous volume. Clear visual state.

## 19 — Games icon to top-left rail
- Create `app/lib/widgets/room/room_left_rail.dart`: a vertical column anchored at the physical
  top-LEFT of the room (use `Positioned(left: …)`, not start/end, so it is left in RTL too), just
  below the header, ABOVE the room settings squares. Order top→bottom: [PK slot] [Rocket slot]
  [Games button]. PK/Rocket slots are empty placeholders now (`SizedBox.shrink()` parameters) —
  another batch fills them. Remove the games button from the bottom bar and reclaim that space.
  Keep `_openGamesSheet` behaviour.

## 27 — Compact tabs, seats never covered
- Make the chat filter tabs (الكل / الهدايا / الرسائل) compact (small pill segmented control,
  ~26–28px tall). Raise the seats area; budget header + top strip + seats + tabs + chat + bottom
  bar with SafeArea and MediaQuery padding (status/nav bar) inside `RoomSeatsChatLayout`, so no
  element ever overlaps the seats for any seat count (5/8/10/12/15/20) at 360x640, 393x873,
  412x915. Extend `app/test/seats_grid_layout_test.dart` (or add a test) to assert no overlap.
  Leave a reserved zero-height slot right under the header (`RoomTopStripSlot`) for CP Top 3 and
  the game-win ticker that another batch adds; its height must be included in the layout budget
  when non-empty.

## 31 — Agency commission bell instead of in-room bar
- Remove the agency commission/percentage notification bar from inside the room (the global
  banner for AGENCY_COMMISSION / agency target types — see `main.dart` classification and
  `global_notification_bar.dart`): don't show those as banners while the user is in a room.
- Add a 🔔 icon positioned just above the room messages/chat area with a badge = unread count of
  agency-type notifications (from the existing notification API + `notification:new` socket).
  Tap → bottom sheet styled like the messages list showing those notifications: date, time,
  agency name, percentage, period, related production, commission amount.
- Backend (`notification.service.ts` / gift commission path in `giftService.ts`): store in the
  notification data at accrual time: agencyId, agencyName, ratePercent, periodStart/periodEnd (or
  period label), productionCoins (the gift/support value it derives from), commissionCoins.
  `notification.controller.ts` list endpoint must redact `commissionCoins`/financial fields unless
  the requester is the agency owner (or has an agency finance scope today) — server side.
  Add `GET /api/v1/notifications?category=agency` filter + unread count for that category.

Batch name for notes: `A1` → `docs/spec52/notes-A1.md`.
