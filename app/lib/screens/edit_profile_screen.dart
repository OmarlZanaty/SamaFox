import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:dio/dio.dart';
import 'dart:io';
import '../providers/auth_provider.dart';
import '../models/user.dart';
import '../services/dio_client.dart';
import '../services/level_catalog_service.dart';

class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _bioController;
  late TextEditingController _phoneController;
  late TextEditingController _countryCodeController;
  late TextEditingController _ageController;
  File? _avatarImage;
  Uint8List? _avatarBytes; // web-compatible preview
  bool _isUploadingAvatar = false;
  bool _isSaving = false;
  bool _isPicking = false;

  @override
  void initState() {
    super.initState();
    final user = ref.read(authStateProvider).user;
    _nameController = TextEditingController(text: user?.name ?? '');
    _bioController = TextEditingController(text: user?.bio ?? '');
    _phoneController = TextEditingController(text: user?.phone ?? '');
    _countryCodeController = TextEditingController(text: user?.countryCode ?? '');
    _ageController = TextEditingController(text: user?.age?.toString() ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _bioController.dispose();
    _phoneController.dispose();
    _countryCodeController.dispose();
    _ageController.dispose();
    super.dispose();
  }

  /// A16 — formats that carry animation. A still `.webp` is treated as animated
  /// too: skipping the crop for one is harmless, while cropping a moving one
  /// silently destroys exactly what the user paid a VIP tier for.
  static bool _looksAnimated(String filename) {
    final name = filename.toLowerCase().split('?').first;
    return name.endsWith('.gif') || name.endsWith('.webp') || name.endsWith('.apng');
  }

  /// Pick an image from the gallery and upload it as avatar
  bool _picking = false;

  Future<void> _pickImage() async {
    if (_picking) return;
    _picking = true;
    try {
      final pickedFile = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (pickedFile == null) return;

      // A16 — "الصوره المتحركه تكون خاصية لفئة معينة من الـ VIP".
      //
      // Cropping rasterises a GIF to a single still frame, so an animated
      // avatar can only survive by skipping the crop step entirely. That is
      // only offered to a tier the dashboard has entitled; everyone else keeps
      // the normal crop-and-upload path and gets told why, instead of
      // discovering it when the server rejects the upload.
      final bool animated = _looksAnimated(pickedFile.name);
      bool keepAnimation = false;
      if (animated) {
        await LevelCatalogService.ensureLoaded();
        final myVip = ref.read(authStateProvider).user?.vipLevel ?? 0;
        keepAnimation = LevelCatalogService.canUseAnimatedAvatar(myVip);
        if (!keepAnimation && mounted) {
          final minLevel = LevelCatalogService.animatedAvatarMinVipLevel();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                minLevel == null
                    ? 'الصورة المتحركة غير متاحة حالياً — سيتم استخدام صورة ثابتة'
                    : 'الصورة المتحركة متاحة لأعضاء VIP $minLevel فما فوق — سيتم استخدام صورة ثابتة',
              ),
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }

      // Crop tool: let the user pick exactly the region to use before upload
      // (drag/resize the box themselves). Native crop UI isn't wired for web
      // here, so web keeps the previous direct-upload behavior.
      XFile fileToUpload = pickedFile;
      if (!kIsWeb && !keepAnimation) {
        final cropped = await ImageCropper().cropImage(
          sourcePath: pickedFile.path,
          aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
          compressQuality: 90,
          uiSettings: [
            AndroidUiSettings(
              toolbarTitle: 'تحديد الصورة',
              toolbarColor: const Color(0xFF1A0E3E),
              toolbarWidgetColor: Colors.white,
              lockAspectRatio: false,
            ),
            IOSUiSettings(title: 'تحديد الصورة'),
          ],
        );
        if (cropped == null) return; // user cancelled the crop step
        fileToUpload = XFile(cropped.path);
      }

      final bytes = await fileToUpload.readAsBytes();
      if (!kIsWeb) setState(() => _avatarImage = File(fileToUpload.path));
      setState(() => _avatarBytes = bytes);
      await _uploadAvatar(fileToUpload);
    } finally {
      _picking = false;
    }
  }



  /// Upload the selected avatar to the backend
  Future<void> _uploadAvatar(XFile xfile) async {
    setState(() => _isUploadingAvatar = true);

    try {
      final bytes = await xfile.readAsBytes();
      final filename = xfile.name.isNotEmpty ? xfile.name : 'avatar.jpg';
      final formData = FormData.fromMap({
        'avatar': MultipartFile.fromBytes(bytes, filename: filename),
      });

      final response = await DioClient.dio.post(
        '/upload/avatar',
        data: formData,
        options: Options(
          contentType: 'multipart/form-data',
        ),
      );

      if (response.statusCode == 200) {
        final data = response.data;
        final avatarUrl = data['avatarUrl'] ?? data['url'];

        final authNotifier = ref.read(authStateProvider.notifier);
        final currentUser = authNotifier.state.user;
        if (currentUser != null) {
          authNotifier.state = authNotifier.state.copyWith(
            user: currentUser.copyWith(avatarUrl: avatarUrl),
          );
        }

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Avatar updated successfully!'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Failed to upload avatar: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      setState(() => _isUploadingAvatar = false);
    }
  }

  // ── خلفية الصفحة الشخصية ──────────────────────────────────────────────
  // A still image, an animated GIF, or a video clip. Whatever is picked
  // REPLACES the current background; "إزالة" puts the default gradient back.
  bool _bgBusy = false;

  Future<void> _pickProfileBackground({required bool video}) async {
    if (_bgBusy) return;
    setState(() => _bgBusy = true);
    try {
      final picker = ImagePicker();
      final picked = video
          ? await picker.pickVideo(source: ImageSource.gallery)
          // GIFs come through pickImage and stay animated — no crop step here,
          // the background is free-form.
          : await picker.pickImage(source: ImageSource.gallery);
      if (picked == null) return;

      final bytes = await picked.readAsBytes();
      final name = picked.name.isNotEmpty ? picked.name : (video ? 'bg.mp4' : 'bg.jpg');
      final resp = await DioClient.dio.post(
        video ? '/upload/background-video' : '/upload/image',
        data: FormData.fromMap({
          if (video)
            'video': MultipartFile.fromBytes(bytes, filename: name)
          else
            'image': MultipartFile.fromBytes(bytes, filename: name),
        }),
        options: Options(contentType: 'multipart/form-data'),
      );

      final data = resp.data;
      final url = (data is Map ? (data['url'] ?? data['imageUrl']) : null)?.toString();
      if (url == null || url.isEmpty) throw Exception('no url');

      await _saveProfileBackground(url, video ? 'video' : 'image');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ تم تغيير خلفية الصفحة')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ تعذّر تغيير الخلفية: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _bgBusy = false);
    }
  }

  Future<void> _saveProfileBackground(String url, String type) async {
    await DioClient.dio.put('/users/me', data: {
      'profileBgUrl': url,
      'profileBgType': type,
      // The endpoint validates gender on every call, so echo the current one.
      'gender': ref.read(authStateProvider).user?.gender ?? 'male',
    });
    final notifier = ref.read(authStateProvider.notifier);
    final me = notifier.state.user;
    if (me != null) {
      notifier.state = notifier.state.copyWith(
        user: me.copyWith(profileBgUrl: url, profileBgType: type),
      );
    }
  }

  Future<void> _clearProfileBackground() async {
    if (_bgBusy) return;
    setState(() => _bgBusy = true);
    try {
      await DioClient.dio.put('/users/me', data: {
        'profileBgUrl': '',
        'gender': ref.read(authStateProvider).user?.gender ?? 'male',
      });
      final notifier = ref.read(authStateProvider.notifier);
      final me = notifier.state.user;
      if (me != null) {
        // copyWith can't null a field out, so rebuild the user without it.
        notifier.state = notifier.state.copyWith(
          user: User(
            id: me.id,
            displayId: me.displayId,
            name: me.name,
            email: me.email,
            phone: me.phone,
            avatarUrl: me.avatarUrl,
            countryCode: me.countryCode,
            country: me.country,
            gender: me.gender,
            birthday: me.birthday,
            age: me.age,
            liveRoomId: me.liveRoomId,
            ownedRoomId: me.ownedRoomId,
            bio: me.bio,
            level: me.level,
            xp: me.xp,
            coins: me.coins,
            coinsBalance: me.coinsBalance,
            vipLevel: me.vipLevel,
            vipExpiresAt: me.vipExpiresAt,
            isAdmin: me.isAdmin,
            isOnline: me.isOnline,
            followersCount: me.followersCount,
            followingCount: me.followingCount,
            createdAt: me.createdAt,
            updatedAt: me.updatedAt,
            avatarFrameUrl: me.avatarFrameUrl,
            agencyRole: me.agencyRole,
            agencyName: me.agencyName,
            familyName: me.familyName,
            achievements: me.achievements,
          ),
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تمت إعادة الخلفية الافتراضية')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ فشل: $e')));
      }
    } finally {
      if (mounted) setState(() => _bgBusy = false);
    }
  }

  Widget _buildBackgroundPicker() {
    final me = ref.watch(authStateProvider).user;
    final has = (me?.profileBgUrl ?? '').isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Align(
          alignment: Alignment.centerRight,
          child: Text('خلفية الصفحة الشخصية',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(height: 4),
        const Align(
          alignment: Alignment.centerRight,
          child: Text('صورة ثابتة أو متحركة أو فيديو — تحل مكان الخلفية الحالية',
              style: TextStyle(color: Colors.white54, fontSize: 12)),
        ),
        const SizedBox(height: 10),
        if (_bgBusy)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Center(child: CircularProgressIndicator()),
          )
        else
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickProfileBackground(video: false),
                  icon: const Icon(Icons.image, size: 18),
                  label: const Text('صورة / متحركة'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickProfileBackground(video: true),
                  icon: const Icon(Icons.movie, size: 18),
                  label: const Text('فيديو'),
                ),
              ),
              if (has) ...[
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'إزالة',
                  onPressed: _clearProfileBackground,
                  icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                ),
              ],
            ],
          ),
      ],
    );
  }

  /// Save the profile changes to the backend
  /// Uses the correct API endpoint: PUT /api/v1/users/profile
  /// Sends: name, bio, phone, countryCode (NOT country or gender)
  Future<void> _saveProfile() async {
    if (_formKey.currentState!.validate()) {
      _formKey.currentState!.save();

      setState(() {
        _isSaving = true;
      });

      try {
        // Call the updateProfile endpoint with correct field names
        final response = await DioClient.dio.put(
          '/users/me',
          data: {
            'name': _nameController.text,
            'bio': _bioController.text,
            'phone': _phoneController.text,
            'countryCode': _countryCodeController.text,
            if (int.tryParse(_ageController.text.trim()) != null)
              'age': int.parse(_ageController.text.trim()),
          },
        );



        if (response.statusCode == 200) {
          final data = response.data;

          // Update the user in auth state
          final authNotifier = ref.read(authStateProvider.notifier);
          final currentUser = authNotifier.state.user;
          if (currentUser != null) {
            final updatedUser = currentUser.copyWith(
              name: data['name'],
              bio: data['bio'],
              phone: data['phone'],
              countryCode: data['countryCode'],
            );
            authNotifier.state = authNotifier.state.copyWith(user: updatedUser);
          }

          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('✅ Profile updated successfully!'),
                backgroundColor: Colors.green,
                duration: Duration(seconds: 2),
              ),
            );
            Navigator.pop(context);
          }
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('❌ Failed to update profile: $e'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      } finally {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authStateProvider).user;

    return Scaffold(
      backgroundColor: const Color(0xFF1A0E3E),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0xFF2A1A5E),
              const Color(0xFF1A0E3E),
              const Color(0xFF0D0620),
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // App bar
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const Expanded(
                      child: Text(
                        'تعديل الملف الشخصي',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: _isSaving ? null : _saveProfile,
                      child: _isSaving
                          ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.amber,
                        ),
                      )
                          : const Text(
                        'حفظ',
                        style: TextStyle(
                          color: Colors.amber,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Form content
              Expanded(
                child: Form(
                  key: _formKey,
                  child: ListView(
                    padding: const EdgeInsets.all(24),
                    children: [
                      // Avatar section with upload functionality
                      Center(
                        child: Stack(
                          children: [
                            GestureDetector(
                              onTap: _isUploadingAvatar ? null : _pickImage,
                              child: Container(
                                width: 120,
                                height: 120,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: LinearGradient(
                                    colors: [
                                      const Color(0xFF8E24AA),
                                      const Color(0xFFD81B60),
                                    ],
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFF8E24AA).withOpacity(0.5),
                                      blurRadius: 20,
                                      spreadRadius: 2,
                                    ),
                                  ],
                                ),
                                child: _isUploadingAvatar
                                    ? const Center(
                                  child: CircularProgressIndicator(color: Colors.white),
                                )
                                    : _avatarBytes != null
                                    ? ClipOval(
                                  child: Image.memory(
                                    _avatarBytes!,
                                    fit: BoxFit.cover,
                                  ),
                                )
                                    : (user?.avatarUrl != null && user!.avatarUrl!.isNotEmpty
                                    ? ClipOval(
                                  child: Image.network(
                                    user.avatarUrl!,
                                    fit: BoxFit.cover,
                                  ),
                                )
                                    : const Icon(
                                  Icons.person,
                                  size: 60,
                                  color: Colors.white,
                                )),
                              ),
                            ),
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: const Color(0xFF4ECDC4),
                                  shape: BoxShape.circle,
                                  border: Border.all(color: const Color(0xFF1A0E3E), width: 2),
                                ),
                                child: const Padding(
                                  padding: EdgeInsets.all(8.0),
                                  child: Icon(
                                    Icons.camera_alt,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 32),

                      // Name field
                      _buildTextField(
                        controller: _nameController,
                        label: 'الاسم',
                        icon: Icons.person,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'الرجاء إدخال اسمك';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // Bio field
                      _buildTextField(
                        controller: _bioController,
                        label: 'السيرة الذاتية',
                        icon: Icons.description,
                        maxLines: 3,
                      ),
                      const SizedBox(height: 16),

                      // Age field (#3)
                      _buildTextField(
                        controller: _ageController,
                        label: 'العمر',
                        icon: Icons.cake,
                        keyboardType: TextInputType.number,
                        maxLength: 3,
                      ),
                      const SizedBox(height: 16),

                      // Phone field
                      _buildTextField(
                        controller: _phoneController,
                        label: 'رقم الهاتف',
                        icon: Icons.phone,
                        keyboardType: TextInputType.phone,
                      ),
                      const SizedBox(height: 16),

                      // Country Code field (e.g., EG, US, SA)
                      _buildTextField(
                        controller: _countryCodeController,
                        label: 'رمز الدولة (مثال: EG, US, SA)',
                        icon: Icons.flag,
                        maxLength: 2,
                      ),
                      const SizedBox(height: 20),

                      _buildBackgroundPicker(),
                      const SizedBox(height: 32),

                      // Info text
                      Text(
                        'ملاحظة: رمز الدولة يجب أن يكون حرفين (مثل: EG للمصر، US لأمريكا)',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.6),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Build a text field with consistent styling
  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    int maxLines = 1,
    int? maxLength,
    String? Function(String?)? validator,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF2A1A5E).withOpacity(0.6),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: const Color(0xFF5E35B1).withOpacity(0.3),
          width: 1,
        ),
      ),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        maxLines: maxLines,
        maxLength: maxLength,
        validator: validator,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
          prefixIcon: Icon(icon, color: const Color(0xFF4ECDC4)),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.all(16),
          counterStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
        ),
      ),
    );
  }
}
