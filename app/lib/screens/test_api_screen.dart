import 'package:flutter/material.dart';
import '../repositories/auth_repository.dart';
import '../config/app_config.dart';

/// Simple API Test Screen
/// Tests connection to backend using existing repositories
class TestApiScreen extends StatefulWidget {
  const TestApiScreen({super.key});

  @override
  State<TestApiScreen> createState() => _TestApiScreenState();
}

class _TestApiScreenState extends State<TestApiScreen> {
  final AuthRepository _authRepo = AuthRepository();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  String _result = '';
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // Pre-fill with test credentials
    _emailController.text = 'ahmed@example.com';
    _passwordController.text = 'password123';
  }

  Future<void> _testLogin() async {
    setState(() {
      _isLoading = true;
      _result = 'Testing login...';
    });

    try {
      final result = await _authRepo.login(
        _emailController.text,
        _passwordController.text,
      );

      setState(() {
        _isLoading = false;
        if (result.isSuccess) {
          final user = result.data!.user;
          _result = '✅ SUCCESS!\n\n'
              'User: ${user.name}\n'
              'Email: ${user.email}\n'
              'ID: ${user.id}\n'
              'Level: ${user.level}\n'
              'Coins: ${user.coinsBalance}\n'
              'VIP: ${user.vipLevel}\n\n'
              'Backend connection working!';
        } else {
          _result = '❌ FAILED\n\n${result.error}';
        }
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _result = '❌ ERROR\n\n$e';
      });
    }
  }

  Future<void> _testGuestLogin() async {
    setState(() {
      _isLoading = true;
      _result = 'Testing guest login...';
    });

    try {
      final deviceId = await _authRepo.getDeviceId();
      final result = await _authRepo.guestLogin(deviceId);

      setState(() {
        _isLoading = false;
        if (result.isSuccess) {
          final user = result.data!.user;
          _result = '✅ GUEST LOGIN SUCCESS!\n\n'
              'User: ${user.name}\n'
              'ID: ${user.id}\n'
              'Device: $deviceId\n\n'
              'Backend connection working!';
        } else {
          _result = '❌ FAILED\n\n${result.error}';
        }
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _result = '❌ ERROR\n\n$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('API Connection Test'),
        backgroundColor: const Color(0xFF6B4CE6),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Backend info
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '🔗 Backend Server',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text('API: ${AppConfig.apiBaseUrl}'),
                  Text('Socket: ${AppConfig.socketUrl}'),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Test credentials
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green.shade200),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '👤 Test Credentials',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text('Email: ahmed@example.com'),
                  Text('Password: password123'),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Login form
            TextField(
              controller: _emailController,
              decoration: InputDecoration(
                labelText: 'Email',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                prefixIcon: const Icon(Icons.email),
              ),
            ),

            const SizedBox(height: 12),

            TextField(
              controller: _passwordController,
              obscureText: true,
              decoration: InputDecoration(
                labelText: 'Password',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                prefixIcon: const Icon(Icons.lock),
              ),
            ),

            const SizedBox(height: 20),

            // Test buttons
            ElevatedButton(
              onPressed: _isLoading ? null : _testLogin,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6B4CE6),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _isLoading
                  ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
                  : const Text(
                'Test Login',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),

            const SizedBox(height: 12),

            OutlinedButton(
              onPressed: _isLoading ? null : _testGuestLogin,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                side: const BorderSide(color: Color(0xFF6B4CE6)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Test Guest Login',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF6B4CE6),
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Result
            if (_result.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _result.contains('✅')
                      ? Colors.green.shade50
                      : Colors.red.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _result.contains('✅')
                        ? Colors.green.shade200
                        : Colors.red.shade200,
                  ),
                ),
                child: Text(
                  _result,
                  style: const TextStyle(
                    fontSize: 14,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
}
