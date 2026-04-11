import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../providers/auth_provider.dart';
import '../providers/room_provider.dart';
import '../models/room.dart';
import '../services/image_upload_service.dart';
import '../utils/storage_service.dart';

/// Enhanced Create Room Dialog with all required fields
class CreateRoomDialog extends ConsumerStatefulWidget {
  const CreateRoomDialog({super.key});

  @override
  ConsumerState<CreateRoomDialog> createState() => _CreateRoomDialogState();
}

class _CreateRoomDialogState extends ConsumerState<CreateRoomDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _numberController = TextEditingController();
  final _descriptionController = TextEditingController();

  File? _selectedImage;
  int _selectedMicCount = 8; // Default mic count
  bool _isLoading = false;

  final List<int> _micCountOptions = [2, 5, 8, 9, 10, 12, 15, 20, 30];
  final String _pkMode = 'PK';

  @override
  void dispose() {
    _nameController.dispose();
    _numberController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );

    if (image != null) {
      setState(() {
        _selectedImage = File(image.path);
      });
    }
  }

  Future<void> _createRoom() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // Upload image first if selected
      String? imageUrl;
      if (_selectedImage != null) {
        final token = await StorageService.getAccessToken();

        if (token != null && token.isNotEmpty) {
          final imageUploadService = ImageUploadService();
          try {
            imageUrl = await imageUploadService.uploadRoomCoverImage(
              _selectedImage!,
              token,
            );
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('فشل رفع الصورة: $e'),
                  backgroundColor: Colors.orange,
                ),
              );
            }
            // Continue without image
          }
        }
      }

      final request = CreateRoomRequest(
        name: _nameController.text.trim(),
        roomNumber: _numberController.text.trim().isEmpty
            ? null
            : _numberController.text.trim(),
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
        coverImage: imageUrl,
        isPublic: true,
        maxSeats: _selectedMicCount,
        maxMembers: 50,
      );

      // ✅ DEBUG: confirm what will be sent to backend
      debugPrint("=================================");
      debugPrint("CREATE ROOM DEBUG:");
      debugPrint("Selected mic count (_selectedMicCount) = $_selectedMicCount");
      debugPrint("Request maxSeats = ${request.maxSeats}");
      debugPrint("Request maxMembers = ${request.maxMembers}");
      debugPrint("Request name = ${request.name}");
      debugPrint("Request JSON = ${request.toJson()}");
      debugPrint("=================================");

      final userId = ref.read(authStateProvider).user!.id;

      final success = await ref
          .read(roomsProvider.notifier)
          .createRoom(request, userId);

      if (!success) {
        final error = ref.read(roomsProvider).error;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error ?? 'Failed')),
        );
        return;
      }

      if (mounted) {
        final newRoomId = ref.read(roomsProvider).rooms.last.id;

        Navigator.of(context).pop();

        await ref.read(roomsProvider.notifier).loadRooms();

        Navigator.pushNamed(context, '/room', arguments: newRoomId);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل إنشاء الغرفة: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }


  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 700),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF2A1A5E),
              Color(0xFF1A0E3E),
            ],
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: const Color(0xFFFFD700).withOpacity(0.3),
            width: 2,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            _buildHeader(),

            // Content
            Expanded(
              child: Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    // Image Upload Section
                    _buildImageUploadSection(),
                    const SizedBox(height: 20),

                    // Room Name
                    _buildTextField(
                      controller: _nameController,
                      label: 'اسم الغرفة',
                      icon: Icons.meeting_room,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'الرجاء إدخال اسم الغرفة';
                        }
                        if (value.trim().length < 3) {
                          return 'اسم الغرفة يجب أن يكون 3 أحرف على الأقل';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // Room Number
                    _buildTextField(
                      controller: _numberController,
                      label: 'رقم الغرفة (اختياري)',
                      icon: Icons.numbers,
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 16),

                    // Description
                    _buildTextField(
                      controller: _descriptionController,
                      label: 'وصف الغرفة (اختياري)',
                      icon: Icons.description,
                      maxLines: 3,
                    ),
                    const SizedBox(height: 20),

                    // Microphone Count Selection
                    _buildMicCountSection(),
                    const SizedBox(height: 24),

                    // Create Button
                    _buildCreateButton(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            Color(0xFF8E24AA),
            Color(0xFFD81B60),
          ],
        ),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(22),
          topRight: Radius.circular(22),
        ),
      ),
      child: Row(
        children: [
          // Close button
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close, color: Colors.white),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          const SizedBox(width: 12),

          // Title
          const Expanded(
            child: Text(
              'إنشاء غرفة جديدة',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
          ),

          // Icon
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.add_circle_outline,
              color: Color(0xFFFFD700),
              size: 24,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImageUploadSection() {
    return GestureDetector(
      onTap: _pickImage,
      child: Container(
        height: 150,
        decoration: BoxDecoration(
          color: const Color(0xFF2A1A5E),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: const Color(0xFFFFD700).withOpacity(0.3),
            width: 2,
            style: BorderStyle.solid,
          ),
        ),
        child: _selectedImage != null
            ? ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.file(
                _selectedImage!,
                fit: BoxFit.cover,
              ),
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.edit,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
            ],
          ),
        )
            : Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFFFD700).withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.add_photo_alternate,
                color: Color(0xFFFFD700),
                size: 40,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'اضغط لإضافة صورة الغرفة',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? Function(String?)? validator,
    int maxLines = 1,
    TextInputType? keyboardType,
  }) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      style: const TextStyle(color: Colors.white),
      textAlign: TextAlign.right,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(
          color: Colors.white70,
          fontSize: 14,
        ),
        prefixIcon: Icon(icon, color: const Color(0xFFFFD700)),
        filled: true,
        fillColor: const Color(0xFF2A1A5E),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: const Color(0xFFFFD700).withOpacity(0.2),
            width: 1,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
            color: Color(0xFFFFD700),
            width: 2,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
            color: Colors.red,
            width: 1,
          ),
        ),
      ),
      validator: validator,
    );
  }

  Widget _buildMicCountSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.mic,
              color: Color(0xFFFFD700),
              size: 20,
            ),
            const SizedBox(width: 8),
            const Text(
              'عدد المايكات',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            // Regular mic count options
            ..._micCountOptions.map((count) => _buildMicCountChip(count)),
            // PK Mode option
            _buildMicCountChip(-1, isPK: true),
          ],
        ),
      ],
    );
  }

  Widget _buildMicCountChip(int count, {bool isPK = false}) {
    final isSelected = isPK
        ? _selectedMicCount == -1
        : _selectedMicCount == count;

    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedMicCount = isPK ? -1 : count;
        });
      },
      child: Container(
        width: 70,
        height: 70,
        decoration: BoxDecoration(
          gradient: isSelected
              ? const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF8E24AA),
              Color(0xFFD81B60),
            ],
          )
              : null,
          color: isSelected ? null : const Color(0xFF2A1A5E),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? const Color(0xFFFFD700)
                : const Color(0xFFFFD700).withOpacity(0.2),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
            BoxShadow(
              color: const Color(0xFFD81B60).withOpacity(0.4),
              blurRadius: 12,
              spreadRadius: 2,
            ),
          ]
              : null,
        ),
        child: Center(
          child: Text(
            isPK ? _pkMode : count.toString(),
            style: TextStyle(
              color: Colors.white,
              fontSize: isPK ? 18 : 20,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCreateButton() {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _createRoom,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFFFD700),
          foregroundColor: Colors.black,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 8,
          shadowColor: const Color(0xFFFFD700).withOpacity(0.5),
        ),
        child: _isLoading
            ? const SizedBox(
          height: 24,
          width: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(Colors.black),
          ),
        )
            : const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_circle, size: 24),
            SizedBox(width: 12),
            Text(
              'إنشاء الغرفة',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
