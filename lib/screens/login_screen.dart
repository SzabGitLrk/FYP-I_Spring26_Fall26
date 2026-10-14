import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isLogin = true;
  bool _isLoading = false;
  bool _isSendingReset = false;
  String? _selectedRole = 'student';

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  /// Shared email-shape check. The forgot-password path used to skip it, so
  /// a malformed address like `abc@` paid a network round trip for a
  /// guaranteed server rejection instead of an instant local message.
  static final RegExp _emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  /// Client-side checks before anything goes over the network.
  ///
  /// The fields are plain [TextField]s (no [Form]/[validator] anywhere), so
  /// an empty email produced Supabase's cryptic "Invalid login credentials"
  /// and a short password a raw Auth error - and untrimmed copy-pasted
  /// addresses failed for the same reason.
  bool _validate() {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    String? error;
    if (email.isEmpty) {
      error = 'Please enter your email';
    } else if (!_emailRegex.hasMatch(email)) {
      error = 'Please enter a valid email address';
    } else if (password.isEmpty) {
      error = 'Please enter your password';
    } else if (!_isLogin && password.length < 6) {
      // Supabase rejects anything shorter anyway; say so before the round trip.
      error = 'Password must be at least 6 characters';
    } else if (!_isLogin && _nameController.text.trim().isEmpty) {
      error = 'Please enter your name';
    } else if (!_isLogin &&
        _confirmPasswordController.text != _passwordController.text) {
      // A typo'd first password used to become an account nobody can sign
      // into - there is no self-service recovery for a password the user
      // never knew they set.
      error = 'Passwords do not match';
    }

    if (error == null) return true;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error), backgroundColor: Colors.orange),
    );
    return false;
  }

  Future<void> _submit() async {
    if (!_validate()) return;
    setState(() => _isLoading = true);

    // Captured before the first await, so what was validated is exactly what
    // is sent even if the fields are edited while the request is in flight.
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final name = _nameController.text.trim();
    // Also captured: the error copy below must describe the action that was
    // actually running, not a toggle the user may have flipped mid-request.
    final isLogin = _isLogin;
    // Same reasoning for the role: read AFTER the awaits, it would report -
    // and write - whatever the dropdown was flipped to mid-request, making
    // profiles.role disagree with the signup metadata.
    final selectedRole = _selectedRole ?? 'student';

    try {
      if (isLogin) {
        await Supabase.instance.client.auth.signInWithPassword(
          email: email,
          password: password,
        );
      } else {
        final response = await Supabase.instance.client.auth.signUp(
          email: email,
          password: password,
          data: {
            'name': name,
            'role': selectedRole,
            'created_at': DateTime.now().toUtc().toIso8601String(),
          },
        );

        // If user is auto-logged in (email confirm disabled), create profile as fallback
        if (response.session != null && response.user != null) {
          try {
            final existing = await Supabase.instance.client
                .from('profiles')
                .select('id')
                .eq('id', response.user!.id)
                .maybeSingle();
            if (existing == null) {
              await Supabase.instance.client.from('profiles').insert({
                'id': response.user!.id,
                'name': name,
                'email': email,
                // Only 'student' / 'driver' are selectable above, and the
                // database guard re-validates this regardless: a client can
                // never self-assign 'admin' or self-approve.
                'role': selectedRole,
                'is_approved': false,
              });
            }
          } catch (_) {
            // Profile creation fallback failed; trigger should handle it
          }
        }

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              response.session != null
                  ? 'Registration successful!'
                  : 'Registration successful! Please sign in.',
            ),
            backgroundColor: Colors.green,
          ),
        );
        setState(() => _isLogin = true);
      }
    } on AuthException catch (e) {
      if (!mounted) return;
      final lower = e.message.toLowerCase();
      final String message;
      if (lower.contains('already registered')) {
        message = 'Already registered with this email';
      } else if (lower.contains(
        'database error saving new user',
      )) {
        // Detail goes to the log, not to the student: nobody in the app can
        // run SQL migrations.
        debugPrint('[login] profile trigger failed: ${e.message}');
        message =
            'Registration could not save your profile. Please contact your administrator.';
      } else if (lower.contains('invalid login credentials')) {
        // Supabase deliberately does not say which of the two was wrong.
        message = 'Email or password is incorrect.';
      } else if (lower.contains('email not confirmed')) {
        message = 'Please confirm your email before signing in.';
      } else if (lower.contains('rate limit') || lower.contains('too many')) {
        message = 'Too many attempts - wait a minute and try again.';
      } else {
        // Raw auth detail (SQL states, internals) is for the log only.
        debugPrint('[login] auth error: ${e.message}');
        message = isLogin
            ? 'Could not sign in. Please try again.'
            : 'Could not create your account. Please try again.';
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.red),
      );
    } catch (e) {
      if (!mounted) return;
      // Raw exception text is for the log, not the UI.
      debugPrint('[login] unexpected error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Something went wrong. Please try again.'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _resetPassword() async {
    if (_isSendingReset) return; // double tap = duplicate mail + rate limit
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter your email first'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    if (!_emailRegex.hasMatch(email)) {
      // Same local check as sign-in: a malformed address can never receive
      // the link, so say so before the round trip.
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid email address'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isSendingReset = true);
    try {
      // redirectTo delivers the PKCE code INTO the app (custom scheme
      // registered in AndroidManifest, handled by ResetPasswordScreen via
      // RoleRouter). Without it the link opened the browser and dead-ended
      // at the Supabase Site URL - the app never saw the recovery while
      // the UI claimed the reset was underway.
      await Supabase.instance.client.auth.resetPasswordForEmail(
        email,
        redirectTo: 'uplreset://reset-password',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Password reset link sent to $email'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      // Raw auth exception text (rate limits, internals) goes to the log;
      // the two cases a user actually acts on get their own copy.
      final raw = e.toString().toLowerCase();
      debugPrint('[login] password reset failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            raw.contains('rate limit') || raw.contains('too many')
                ? 'Too many reset requests - wait a minute and try again.'
                : 'Could not send the reset link. Check the email address '
                    'and your connection, then try again.',
          ),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSendingReset = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.blue.shade800, Colors.blue.shade400],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Card(
                elevation: 8,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Logo
                      Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.directions_bus,
                          size: 50,
                          color: Colors.blue.shade800,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'University Point Locator',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue.shade800,
                        ),
                      ),
                      Text(
                        'Larkana',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 32),

                      // Login/Signup Toggle
                      Row(
                        children: [
                          Expanded(
                            child: _buildToggleButton('Sign in', true),
                          ),
                          Expanded(
                            child: _buildToggleButton('Create account', false),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // Form Fields
                      if (!_isLogin) ...[
                        TextField(
                          controller: _nameController,
                          decoration: InputDecoration(
                            labelText: 'Full Name',
                            prefixIcon: const Icon(Icons.person),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Role Selection for Registration
                        DropdownButtonFormField<String>(
                          initialValue: _selectedRole,
                          decoration: InputDecoration(
                            labelText: 'I am a',
                            prefixIcon: const Icon(Icons.people),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'student',
                              child: Text('Student'),
                            ),
                            DropdownMenuItem(
                              value: 'driver',
                              child: Text('Bus Driver'),
                            ),
                          ],
                          onChanged: (value) {
                            setState(() => _selectedRole = value);
                          },
                        ),
                        const SizedBox(height: 16),
                      ],

                      TextField(
                        controller: _emailController,
                        decoration: InputDecoration(
                          labelText: 'Email',
                          prefixIcon: const Icon(Icons.email),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      TextField(
                        controller: _passwordController,
                        obscureText: true,
                        decoration: InputDecoration(
                          labelText: 'Password',
                          prefixIcon: const Icon(Icons.lock),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      if (!_isLogin) ...[
                        const SizedBox(height: 16),
                        // A typo'd first password used to become an account
                        // nobody can sign into.
                        TextField(
                          controller: _confirmPasswordController,
                          obscureText: true,
                          decoration: InputDecoration(
                            labelText: 'Confirm password',
                            prefixIcon: const Icon(Icons.lock_outline),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      if (_isLogin)
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: _isSendingReset ? null : _resetPassword,
                            child: const Text(
                              'Forgot Password?',
                              style: TextStyle(color: Colors.blue),
                            ),
                          ),
                        ),
                      const SizedBox(height: 16),

                      // Submit Button
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _submit,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue.shade800,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: _isLoading
                              ? const CircularProgressIndicator(
                                  color: Colors.white,
                                )
                              : Text(
                                  _isLogin ? 'Sign in' : 'Create account',
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildToggleButton(String text, bool isLogin) {
    return GestureDetector(
      onTap: () => setState(() => _isLogin = isLogin),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: _isLogin == isLogin
              ? Colors.blue.shade800
              : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _isLogin == isLogin ? Colors.white : Colors.black,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
