# HANDOFF

Tool: codex. Brief: BRIEF.md. Scope: I18N_FILES.txt (67 files).

## Translation pass complete (final English-only and language-refresh review pending)
- app/lib/screens/room_screen.dart
- app/lib/screens/games/aetherfall_help.dart
- app/lib/screens/agency_branches_screen.dart
- app/lib/screens/games/greedy_cat_screen.dart
- app/lib/screens/games_hub_screen.dart
- app/lib/screens/games/lion_tiger_screen.dart
- app/lib/gifts/widgets/gift_picker_sheet.dart
- app/lib/screens/games/aetherfall_screen.dart
- app/lib/widgets/room/room_events.dart
- app/lib/screens/store_screen.dart
- app/lib/screens/games/asterion_help.dart
- app/lib/screens/relations_screen.dart
- app/lib/widgets/room/room_emoji.dart
- app/lib/screens/games/asterion_screen.dart
- app/lib/screens/staff/staff_panel_screen.dart
- app/lib/screens/games/fish_shooter_screen.dart
- app/lib/repositories/crash_repository.dart
- app/lib/screens/cp_list_screen.dart
- app/lib/widgets/room/room_chat_panel.dart
- app/lib/screens/supporters_board_screen.dart
- app/lib/widgets/vip_buy_sheet.dart
- app/lib/screens/games/crazy_wheel_bonus.dart
- app/lib/gifts/services/gift_repository.dart
- app/lib/screens/broadcast_time_screen.dart
- app/lib/widgets/cp_relationship.dart
- app/lib/screens/games/asterion_fairness.dart
- app/lib/screens/create_room_dialog.dart
- app/lib/screens/games_screen.dart
- app/lib/screens/games/asterion_art.dart
- app/lib/repositories/neon_fortune_repository.dart
- app/lib/dev/aetherfall_preview.dart
- app/lib/widgets/room/music_player_bar.dart
- app/lib/widgets/room/agency_bell.dart
- app/lib/screens/my_backgrounds_screen.dart
- app/lib/screens/home_screen.dart
- app/lib/dev/room_layout_preview.dart
- app/lib/screens/blocked_users_screen.dart
- app/lib/repositories/skill_dice_repository.dart
- app/lib/dev/asterion_preview.dart
- app/lib/screens/my_agencies_screen.dart
- app/lib/repositories/crazy_wheel_repository.dart
- app/lib/widgets/room/room_jump.dart
- app/lib/widgets/room/room_info_sheet.dart
- app/lib/widgets/force_update_gate.dart
- app/lib/services/agency_branch_service.dart
- app/lib/repositories/plinko_repository.dart
- app/lib/repositories/asterion_repository.dart
- app/lib/gifts/widgets/lucky_win_banner.dart
- app/lib/screens/games/fruit_jackpot_bonus.dart

## Remaining
- app/lib/gifts/widgets/gift_animation_overlay.dart
- app/lib/gifts/services/gift_socket_service.dart
- app/lib/widgets/room/room_game_win_strip.dart
- app/lib/widgets/chat/message_bubble.dart
- app/lib/services/room_share_service.dart
- app/lib/screens/room/pin_dialog.dart
- app/lib/screens/games/fruit_jackpot_celebration.dart
- app/lib/widgets/room/room_cp_top.dart
- app/lib/widgets/mic_perfect_badge.dart
- app/lib/services/music_service.dart
- app/lib/screens/games/yummy_screen.dart
- app/lib/screens/games/car_wheel_sheets.dart
- app/lib/screens/feature_screens.dart
- app/lib/models/product.dart
- app/lib/gifts/widgets/lucky_ticker.dart

## Reviewed exclusions
BRIEF.md explicitly says NEVER edit app/lib/providers/*. These listed files are protected:
- app/lib/providers/room_controller_provider.dart
- app/lib/providers/message_providers.dart
- app/lib/providers/auth_provider.dart

## Preserved values
- Games hub Arabic titles are navigation switch keys; preserved with an i18n comment.
- Gift picker Arabic general-category identifier is compared with server data; preserved with an i18n comment.
- Server payloads, comparisons, comments, logs, assets, and existing bilingual expressions are excluded.

## Validation
Dart parser runs on each edited file before saving. Final const, import, source-preservation and English-only review remains in progress.
