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
  bool _isLogin = true;
  bool _isLoading = false;
  String? _selectedRole = 'student';

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    super.dispose();
  }

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
    } else if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      error = 'Please enter a valid email address';
    } else if (password.isEmpty) {
      error = 'Please enter your password';
    } else if (!_isLogin && password.length < 6) {
      // Supabase rejects anything shorter anyway; say so before the round trip.
      error = 'Password must be at least 6 characters';
    } else if (!_isLogin && _nameController.text.trim().isEmpty) {
      error = 'Please enter your name';
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

    try {
      if (_isLogin) {
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
            'role': _selectedRole,
            'created_at': DateTime.now().toIso8601String(),
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
                'role': _selectedRole,
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
                  : 'Registration successful! Please login.',
            ),
            backgroundColor: Colors.green,
          ),
        );
        setState(() => _isLogin = true);
      }
    } on AuthException catch (e) {
      if (!mounted) return;
      String message;
      if (e.message.toLowerCase().contains('already registered')) {
        message = 'Already registered with this email';
      } else if (e.message.toLowerCase().contains(
        'database error saving new user',
      )) {
        message =
            'Database error creating profile. Run the SQL migration in Supabase SQL Editor to fix the trigger function.';
      } else {
        message = e.message;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.red),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _resetPassword() async {
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

    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Password reset link sent to $email'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
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
                          Expanded(child: _buildToggleButton('Login', true)),
                          Expanded(
                            child: _buildToggleButton('Register', false),
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
                      const SizedBox(height: 8),
                      if (_isLogin)
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: _resetPassword,
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
                              : Text(_isLogin ? 'Login' : 'Register'),
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
