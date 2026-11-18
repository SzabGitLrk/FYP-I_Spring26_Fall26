import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';
import '../theme/app_widgets.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final username = TextEditingController();
  final answer = TextEditingController();
  final newPassword = TextEditingController();
  bool _obscure = true;
  bool _loading = false;

  String message = "";
  Color messageColor = AppColors.textSecondary;

  void resetPassword() async {
    if (username.text.trim().isEmpty ||
        answer.text.trim().isEmpty ||
        newPassword.text.trim().isEmpty) {
      setState(() {
        message = "Please fill all fields!";
        messageColor = AppColors.warning;
      });
      return;
    }

    setState(() => _loading = true);
    final prefs = await SharedPreferences.getInstance();
    String savedUsername = prefs.getString('username') ?? "";
    String savedAnswer = prefs.getString('answer') ?? "";

    if (!mounted) return;

    if (username.text.trim() == savedUsername &&
        answer.text.trim() == savedAnswer) {
      await prefs.setString('password', newPassword.text.trim());
      if (!mounted) return;
      setState(() {
        _loading = false;
        message = "Password reset successfully!";
        messageColor = AppColors.success;
        username.clear();
        answer.clear();
        newPassword.clear();
      });
    } else {
      setState(() {
        _loading = false;
        message = "Wrong username or answer!";
        messageColor = AppColors.danger;
      });
    }
  }

  @override
  void dispose() {
    username.dispose();
    answer.dispose();
    newPassword.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text("Reset Password"),
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
              Center(
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: AppDecorations.pill(AppColors.primary),
                  child: const Icon(Icons.lock_reset_rounded,
                      color: AppColors.primary, size: 36),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              const Center(
                  child: Text("Forgot Password?", style: AppText.heading)),
              const SizedBox(height: 4),
              const Center(
                child: Text(
                  "Verify your identity to reset it",
                  style: AppText.bodySecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),

              _field("Username", username, Icons.person_outline,
                  hint: "Your username"),
              const SizedBox(height: AppSpacing.md),
              _field("Security Question: Your pet name?", answer,
                  Icons.shield_outlined,
                  hint: "Your answer"),
              const SizedBox(height: AppSpacing.md),

              const Text("New Password", style: AppText.label),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: newPassword,
                obscureText: _obscure,
                style: AppText.body,
                decoration: InputDecoration(
                  hintText: "Enter new password",
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

              if (message.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: messageColor, fontWeight: FontWeight.w600),
                ),
              ],
              const SizedBox(height: AppSpacing.xl),

              AppPrimaryButton(
                label: "Reset Password",
                loading: _loading,
                onPressed: resetPassword,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(String label, TextEditingController c, IconData icon,
      {String? hint}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppText.label),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          controller: c,
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
