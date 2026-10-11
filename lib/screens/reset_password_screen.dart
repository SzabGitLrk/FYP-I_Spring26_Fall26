import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Destination for the password-recovery deep link
/// (`uplreset://reset-password` - registered in AndroidManifest.xml and set
/// as `redirectTo` on `resetPasswordForEmail`).
///
/// Without this screen the PKCE recovery code landed in the app and went
/// nowhere: the email link opened the browser, the browser dead-ended at
/// the Supabase Site URL, and "Password reset link sent" was the last the
/// user ever heard of it. RoleRouter routes here on the `passwordRecovery`
/// auth event instead of rendering a dashboard.
class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final password = _passwordController.text;
    if (password.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Password must be at least 6 characters'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    if (_confirmController.text != password) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Passwords do not match'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Captured before the awaits: this State's `context` must not be read
    // after them (the sign-out below unmounts this screen).
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _isSubmitting = true);
    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: password),
      );
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Password updated - sign in with your new password'),
          backgroundColor: Colors.green,
        ),
      );
      // The recovery session ends here on purpose: the next screen is the
      // login form, and the new password is the one just set. The snackbar
      // survives the swap - it was captured from the root messenger.
      await Supabase.instance.client.auth.signOut();
    } catch (e) {
      // Raw exception text stays in the log; the user gets actionable copy.
      debugPrint('[reset] password update failed: $e');
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Could not update the password. Open the reset link again and '
            'retry.',
          ),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Set a new password')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.lock_reset, size: 64, color: Colors.blue),
              const SizedBox(height: 16),
              const Text(
                'Choose a new password for your account.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'New password',
                  prefixIcon: Icon(Icons.lock),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _confirmController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Confirm new password',
                  prefixIcon: Icon(Icons.lock_outline),
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _isSubmitting ? null : _submit,
                child: _isSubmitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Update password'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
