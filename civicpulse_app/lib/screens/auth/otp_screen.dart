import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../core/constants/app_constants.dart';
import '../home/home_screen.dart';

class OtpScreen extends StatefulWidget {
  final String phoneNumber;
  const OtpScreen({super.key, required this.phoneNumber});

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final _otpController = TextEditingController();
  final _nameController = TextEditingController();
  final _otpFormKey = GlobalKey<FormState>();
  final _nameFormKey = GlobalKey<FormState>();

  bool _showNameField = false;
  String? _verifiedOtp; // stores otp after first verify attempt

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final otp = context.read<AuthProvider>().otpDev;
      if (otp != null) {
        _otpController.text = otp;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Dev mode: OTP auto-filled → $otp'),
          backgroundColor: AppColors.primary,
          duration: const Duration(seconds: 4),
        ));
      }
    });
  }

  @override
  void dispose() {
    _otpController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    if (_showNameField) {
      // Step 2 — new user submitted their name
      if (!_nameFormKey.currentState!.validate()) return;
      await _doLogin(_nameController.text.trim());
    } else {
      // Step 1 — verify OTP first
      if (!_otpFormKey.currentState!.validate()) return;
      final auth = context.read<AuthProvider>();
      final otp = _otpController.text.trim();

      // Try login without name first (works for existing users)
      final success = await auth.verifyOtp(
        widget.phoneNumber,
        otp,
        '', // empty name — backend handles existing users fine
      );

      if (!mounted) return;

      if (success) {
        // Existing user — go straight to home
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const HomeScreen()),
          (_) => false,
        );
      } else if (auth.error != null &&
          auth.error!.toLowerCase().contains('name is required')) {
        // New user — ask for name
        setState(() {
          _showNameField = true;
          _verifiedOtp = otp;
        });
      } else {
        // Wrong OTP or other error
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(auth.error ?? 'Invalid OTP'),
          backgroundColor: AppColors.critical,
        ));
      }
    }
  }

  Future<void> _doLogin(String name) async {
    final auth = context.read<AuthProvider>();
    final success = await auth.verifyOtp(
      widget.phoneNumber,
      _verifiedOtp ?? _otpController.text.trim(),
      name,
    );
    if (!mounted) return;
    if (success) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()),
        (_) => false,
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(auth.error ?? 'Something went wrong'),
        backgroundColor: AppColors.critical,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return Scaffold(
      appBar: AppBar(title: const Text('Verify OTP')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 24),
              Text(
                _showNameField
                    ? 'One last step!'
                    : 'OTP sent to\n${widget.phoneNumber}',
                style: const TextStyle(
                    fontSize: 22, fontWeight: FontWeight.w700, height: 1.3),
              ),
              const SizedBox(height: 8),
              Text(
                _showNameField
                    ? 'Looks like you\'re new here. What should we call you?'
                    : 'Enter the 6-digit code below.',
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 32),
              if (!_showNameField)
                Form(
                  key: _otpFormKey,
                  child: TextFormField(
                    controller: _otpController,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    style: const TextStyle(
                        fontSize: 24,
                        letterSpacing: 8,
                        fontWeight: FontWeight.w700),
                    textAlign: TextAlign.center,
                    decoration: const InputDecoration(
                      hintText: '------',
                      hintStyle:
                          TextStyle(letterSpacing: 8, color: AppColors.border),
                      counterText: '',
                    ),
                    validator: (v) => (v == null || v.length != 6)
                        ? 'Enter 6-digit OTP'
                        : null,
                  ),
                ),
              if (_showNameField)
                Form(
                  key: _nameFormKey,
                  child: TextFormField(
                    controller: _nameController,
                    textCapitalization: TextCapitalization.words,
                    autofocus: true,
                    decoration: const InputDecoration(
                      hintText: 'Your full name',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Please enter your name'
                        : null,
                  ),
                ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: auth.isLoading ? null : _verify,
                child: auth.isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : Text(_showNameField ? 'Get Started' : 'Verify OTP'),
              ),
              if (!_showNameField) ...[
                const SizedBox(height: 16),
                Center(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Change phone number'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
