import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';
import '../theme/app_widgets.dart';
import 'login_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final username = TextEditingController();
  final email = TextEditingController();
  final password = TextEditingController();
  final answer = TextEditingController();
  bool _obscure = true;
  bool _loading = false;

  void register() async {
    if (username.text.trim().isEmpty ||
        email.text.trim().isEmpty ||
        password.text.trim().isEmpty ||
        answer.text.trim().isEmpty) {
      _snack("Please fill all fields", AppColors.danger);
      return;
    }

    setState(() => _loading = true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('username', username.text.trim());
    await prefs.setString('email', email.text.trim());
    await prefs.setString('password', password.text.trim());
    await prefs.setString('answer', answer.text.trim());

    if (!mounted) return;
    _snack("Account created successfully!", AppColors.success);
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  void _snack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color),
    );
  }

  @override
  void dispose() {
    username.dispose();
    email.dispose();
    password.dispose();
    answer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text("Create Account"),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: AppSpacing.md),
              const Text("Join EYRIS", style: AppText.heading),
              const SizedBox(height: 4),
              const Text("Create an account to get started",
                  style: AppText.bodySecondary),
              const SizedBox(height: AppSpacing.xl),

              _field("Username", username, Icons.person_outline,
                  hint: "Choose a username"),
              const SizedBox(height: AppSpacing.md),
              _field("Email", email, Icons.email_outlined,
                  hint: "you@example.com",
                  keyboard: TextInputType.emailAddress),
              const SizedBox(height: AppSpacing.md),

              const Text("Password", style: AppText.label),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: password,
                obscureText: _obscure,
                style: AppText.body,
                decoration: InputDecoration(
                  hintText: "Choose a password",
                  prefixIcon: const Icon(Icons.lock_outline,
                      color: AppColors.textMuted),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscure
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      color: AppColors.textMuted,
                    ),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),

              _field("Security Question: Your pet name?", answer,
                  Icons.shield_outlined,
                  hint: "Used to recover your password"),
              const SizedBox(height: AppSpacing.xl),

              AppPrimaryButton(
                label: "Create Account",
                loading: _loading,
                onPressed: register,
              ),
              const SizedBox(height: AppSpacing.md),

              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text("Already have an account? ",
                      style: AppText.bodySecondary),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Text(
                      "Login",
                      style: TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(String label, TextEditingController c, IconData icon,
      {String? hint, TextInputType? keyboard}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppText.label),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          controller: c,
          keyboardType: keyboard,
          style: AppText.body,
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: Icon(icon, color: AppColors.textMuted),
          ),
        ),
      ],
    );
  }
}
