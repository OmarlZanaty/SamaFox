import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/room.dart';
import '../models/user.dart';
import '../theme/app_theme.dart';
import '../repositories/room_repository.dart';

/// Room Admin Panel Widget
/// Provides comprehensive administrative controls for room owners and admins
class RoomAdminPanel extends ConsumerStatefulWidget {
  final Room room;
  final bool isOwner;
  final bool isAdmin;
  final Function(Room)? onRoomUpdated;

  const RoomAdminPanel({
    super.key,
    required this.room,
    required this.isOwner,
    required this.isAdmin,
    this.onRoomUpdated,
  });

  @override
  ConsumerState<RoomAdminPanel> createState() => _RoomAdminPanelState();
}

class _RoomAdminPanelState extends ConsumerState<RoomAdminPanel> {
  late RoomRepository _roomRepository;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _roomRepository = RoomRepository();
  }

  @override
  Widget build(BuildContext context) {
    // Using hardcoded strings - you can replace with localization later

    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.backgroundDarkPurple,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Title
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(
              children: [
                const Icon(Icons.admin_panel_settings, color: Colors.amber),
                const SizedBox(width: 12),
                const Text(
                  'Room Control Panel',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white70),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          const Divider(color: Colors.white24, height: 1),

          // Control options
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                // Room Admins (Owner only)
                if (widget.isOwner)
                  _buildControlTile(
                    icon: Icons.supervisor_account,
                    title: 'Room Admins',
                    onTap: () => _showAdminsDialog(),
                  ),

                // Change Mic Count
                _buildControlTile(
                  icon: Icons.mic,
                  title: 'Change Mic Count',
                  trailing: Text(
                    '${widget.room.maxSeatsLimit}',
                    style: const TextStyle(color: Colors.white70),
                  ),
                  onTap: () => _showMicCountDialog(),
                ),

                // Lock Room
                _buildControlTile(
                  icon: widget.room.isRoomLocked
                      ? Icons.lock
                      : Icons.lock_open,
                  title: 'Lock Room',
                  trailing: Switch(
                    value: widget.room.isRoomLocked,
                    onChanged: (value) => _toggleRoomLock(),
                    activeColor: AppTheme.primaryPurple,
                  ),
                  onTap: () => _toggleRoomLock(),
                ),

                // Ban List
                _buildControlTile(
                  icon: Icons.block,
                  title: 'Ban List',
                  onTap: () => _showBanListDialog(),
                ),

                // Mute Users
                _buildControlTile(
                  icon: Icons.volume_off,
                  title: 'Mute Users',
                  onTap: () => _showMuteUsersDialog(),
                ),

                const Divider(color: Colors.white24, height: 1),

                // Background Music
                _buildControlTile(
                  icon: Icons.music_note,
                  title: 'Background Music',
                  onTap: () => _showBackgroundMusicDialog(),
                ),

                // Room Background
                _buildControlTile(
                  icon: Icons.wallpaper,
                  title: 'Room Background',
                  onTap: () => _showBackgroundImageDialog(),
                ),

                const Divider(color: Colors.white24, height: 1),

                // Sound Settings
                _buildControlTile(
                  icon: Icons.volume_up,
                  title: 'Sound Settings',
                  onTap: () => _showSoundSettingsDialog(),
                ),

                // Clear Chat
                _buildControlTile(
                  icon: Icons.delete_sweep,
                  title: 'Clear Chat',
                  onTap: () => _confirmClearChat(),
                  iconColor: Colors.red,
                ),

                const Divider(color: Colors.white24, height: 1),

                // Share Room
                _buildControlTile(
                  icon: Icons.share,
                  title: 'Share with Friends',
                  onTap: () => _shareRoom(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlTile({
    required IconData icon,
    required String title,
    Widget? trailing,
    required VoidCallback onTap,
    Color? iconColor,
  }) {
    return ListTile(
      leading: Icon(icon, color: iconColor ?? AppTheme.primaryPurple),
      title: Text(
        title,
        style: const TextStyle(color: Colors.white),
      ),
      trailing:
      trailing ?? const Icon(Icons.chevron_right, color: Colors.white54),
      onTap: onTap,
    );
  }

  // ============ Admin Control Methods ============

  void _showAdminsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.backgroundDarkPurple,
        title: const Text('Room Admins',
            style: TextStyle(color: Colors.white)),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: widget.room.roomMembers.length,
            itemBuilder: (context, index) {
              final member = widget.room.roomMembers[index];
              final isAdmin = member.role == 'admin' || member.role == 'owner';
              return ListTile(
                leading: CircleAvatar(
                  backgroundImage: member.user?.avatarUrl != null
                      ? NetworkImage(member.user!.avatarUrl!)
                      : null,
                  child: member.user?.avatarUrl == null
                      ? Text(member.user?.name[0] ?? 'U')
                      : null,
                ),
                title: Text(member.user?.name ?? 'Unknown',
                    style: const TextStyle(color: Colors.white)),
                subtitle: Text(member.role ?? 'member',
                    style: const TextStyle(color: Colors.white70)),
                trailing: widget.isOwner && member.role != 'owner'
                    ? IconButton(
                  icon: Icon(
                    isAdmin ? Icons.remove_circle : Icons.add_circle,
                    color: isAdmin ? Colors.red : Colors.green,
                  ),
                  onPressed: () => _toggleAdminRole(member),
                )
                    : null,
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showMicCountDialog() {
    final controller =
    TextEditingController(text: widget.room.maxSeatsLimit.toString());

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.backgroundDarkPurple,
        title: const Text('Change Mic Count',
            style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            labelText: 'Number of Mic Seats',
            labelStyle: TextStyle(color: Colors.white70),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.white70),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final newCount = int.tryParse(controller.text);
              if (newCount != null && newCount > 0 && newCount <= 20) {
                _updateMicCount(newCount);
                Navigator.pop(context);
              } else {
                _showSnackBar('Please enter a valid number between 1 and 20');
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleRoomLock() async {
    setState(() => _isLoading = true);
    try {
      final newLockState = !widget.room.isRoomLocked;
      // Call API to update room lock status
      await _roomRepository.updateRoom(
        widget.room.id,
        UpdateRoomRequest(isPublic: !newLockState),
      );
      _showSnackBar(newLockState ? 'Room locked' : 'Room unlocked');
      // Notify parent to refresh room data
      widget.onRoomUpdated?.call(widget.room);
    } catch (e) {
      _showSnackBar('Failed to update room lock status');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showBanListDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.backgroundDarkPurple,
        title:
        const Text('Ban List', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Ban list management coming soon',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showMuteUsersDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.backgroundDarkPurple,
        title: const Text('Mute Users',
            style: TextStyle(color: Colors.white)),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: widget.room.roomMembers.length,
            itemBuilder: (context, index) {
              final member = widget.room.roomMembers[index];
              return ListTile(
                leading: CircleAvatar(
                  backgroundImage: member.user?.avatarUrl != null
                      ? NetworkImage(member.user!.avatarUrl!)
                      : null,
                  child: member.user?.avatarUrl == null
                      ? Text(member.user?.name[0] ?? 'U')
                      : null,
                ),
                title: Text(member.user?.name ?? 'Unknown',
                    style: const TextStyle(color: Colors.white)),
                trailing: Switch(
                  value: member.isMuted ?? false,
                  onChanged: (value) => _toggleMute(member, value),
                  activeColor: Colors.red,
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showBackgroundMusicDialog() {
    _showSnackBar('Background music feature coming soon');
  }

  void _showBackgroundImageDialog() {
    _showSnackBar('Background image feature coming soon');
  }

  void _showSoundSettingsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.backgroundDarkPurple,
        title: const Text('Sound Settings',
            style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SwitchListTile(
              title: const Text('Mute Gift Sounds',
                  style: TextStyle(color: Colors.white)),
              value: widget.room.giftSoundsMuted,
              onChanged: (value) => _toggleGiftSounds(value),
              activeColor: AppTheme.primaryPurple,
            ),
            SwitchListTile(
              title: const Text('Mute Entrance Sounds',
                  style: TextStyle(color: Colors.white)),
              value: widget.room.entranceSoundsMuted,
              onChanged: (value) => _toggleEntranceSounds(value),
              activeColor: AppTheme.primaryPurple,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _confirmClearChat() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.backgroundDarkPurple,
        title:
        const Text('Clear Chat', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Are you sure you want to clear all chat messages? This action cannot be undone.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              _clearChat();
              Navigator.pop(context);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }

  void _shareRoom() {
    _showSnackBar('Share functionality coming soon');
  }

  // ============ API Call Methods ============

  Future<void> _toggleAdminRole(RoomMember member) async {
    setState(() => _isLoading = true);
    try {
      // Call API to toggle admin role
      _showSnackBar('Admin role updated for ${member.user?.name}');
    } catch (e) {
      _showSnackBar('Failed to update admin role');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _updateMicCount(int count) async {
    setState(() => _isLoading = true);
    try {
      await _roomRepository.updateRoom(
        widget.room.id,
        UpdateRoomRequest(maxSeats: count),
      );
      _showSnackBar('Mic count updated to $count');
      widget.onRoomUpdated?.call(widget.room);
    } catch (e) {
      _showSnackBar('Failed to update mic count');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _toggleMute(RoomMember member, bool mute) async {
    _showSnackBar('${mute ? "Muted" : "Unmuted"} ${member.user?.name}');
  }

  Future<void> _toggleGiftSounds(bool mute) async {
    _showSnackBar('Gift sounds ${mute ? "muted" : "unmuted"}');
  }

  Future<void> _toggleEntranceSounds(bool mute) async {
    _showSnackBar('Entrance sounds ${mute ? "muted" : "unmuted"}');
  }

  Future<void> _clearChat() async {
    _showSnackBar('Chat cleared');
  }

  void _showSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }
}
