import 'package:flutter/material.dart';
import '../services/auth_service.dart';

class LoginScreen extends StatefulWidget {
  final Function(String) onLoginSuccess;

  const LoginScreen({required this.onLoginSuccess, super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  late final AuthService authService;
  final emailController = TextEditingController();
  final codeController = TextEditingController();

  bool isLoading = false;
  bool otpSent = false;
  String? errorMessage;
  String? email;

  @override
  void initState() {
    super.initState();
    authService = AuthService();
  }

  @override
  void dispose() {
    emailController.dispose();
    codeController.dispose();
    super.dispose();
  }

  Future<void> requestOTP() async {
    final email = emailController.text.trim();
    if (email.isEmpty) {
      setState(() => errorMessage = 'Please enter your email');
      return;
    }

    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    final result = await authService.requestOTP(email);

    if (mounted) {
      setState(() {
        isLoading = false;
        if (result.success) {
          otpSent = true;
          this.email = email;
          errorMessage = null;
        } else {
          errorMessage = result.message ?? 'Failed to send OTP';
        }
      });
    }
  }

  Future<void> verifyOTP() async {
    final code = codeController.text.trim();
    if (code.isEmpty) {
      setState(() => errorMessage = 'Please enter the code');
      return;
    }

    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    final result = await authService.verifyOTP(email!, code);

    if (mounted) {
      setState(() => isLoading = false);

      if (result.success && result.token != null) {
        widget.onLoginSuccess(result.token!);
      } else {
        setState(() => errorMessage = result.message ?? 'Invalid code');
      }
    }
  }

  void resetLogin() {
    setState(() {
      otpSent = false;
      emailController.clear();
      codeController.clear();
      errorMessage = null;
      email = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Logo/Header
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: cs.primary,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.smart_toy, size: 40, color: cs.onPrimary),
                ),
                const SizedBox(height: 24),

                // Title
                Text(
                  'Voice Chat',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 8),

                // Subtitle
                Text(
                  otpSent ? 'Enter the code sent to your email' : 'Sign in to continue',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 32),

                // Email or OTP field
                if (!otpSent)
                  TextField(
                    controller: emailController,
                    enabled: !isLoading,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      hintText: 'Enter your email',
                      prefixIcon: const Icon(Icons.email_outlined),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  )
                else
                  Column(
                    children: [
                      Text(
                        'Code sent to $email',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: codeController,
                        enabled: !isLoading,
                        keyboardType: TextInputType.number,
                        maxLength: 6,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall,
                        decoration: InputDecoration(
                          hintText: '000000',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          counterText: '',
                        ),
                      ),
                    ],
                  ),

                const SizedBox(height: 12),

                // Error message
                if (errorMessage != null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: cs.errorContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      errorMessage!,
                      style: TextStyle(color: cs.error),
                    ),
                  ),

                const SizedBox(height: 24),

                // Submit button
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: isLoading
                        ? null
                        : (otpSent ? verifyOTP : requestOTP),
                    child: isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(otpSent ? 'Verify Code' : 'Send Code'),
                  ),
                ),

                // Back button (when OTP sent)
                if (otpSent)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: isLoading ? null : resetLogin,
                        child: const Text('Back'),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
