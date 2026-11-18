import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';
import '../theme/app_widgets.dart';
import 'home_screen.dart';
import 'register_screen.dart';
import 'forgot_password.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final email = TextEditingController();
  final password = TextEditingController();
  bool _obscure = true;
  bool _loading = false;

  void login() async {
    if (email.text.trim().isEmpty || password.text.trim().isEmpty) {
      _snack("Please enter both email and password", AppColors.warning);
      return;
    }

    setState(() => _loading = true);
    final prefs = await SharedPreferences.getInstance();
    String savedEmail = prefs.getString('email') ?? "";
    String savedPassword = prefs.getString('password') ?? "";

    if (email.text.trim() == savedEmail &&
        password.text.trim() == savedPassword) {
      await prefs.setBool('login', true);
      if (!mounted) return;
      _snack("Login successful!", AppColors.success);
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    } else {
      if (!mounted) return;
      setState(() => _loading = false);
      _snack("Wrong email or password", AppColors.danger);
    }
  }

  void _snack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color),
    );
  }

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),

              // Logo (the artwork already carries the EYRIS name)
              const Center(child: EyrisLogo(size: 240)),
              const SizedBox(height: AppSpacing.md),
              const Center(
                child: Text("Sign in to continue",
                    style: AppText.bodySecondary),
              ),
              const SizedBox(height: AppSpacing.xl),

              // Email
              const Text("Email", style: AppText.label),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: email,
                keyboardType: TextInputType.emailAddress,
                style: AppText.body,
                decoration: const InputDecoration(
                  hintText: "you@example.com",
                  prefixIcon: Icon(Icons.email_outlined,
                      color: AppColors.textMuted),
                ),
              ),
              const SizedBox(height: AppSpacing.md),

              // Password
              const Text("Password", style: AppText.label),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: password,
                obscureText: _obscure,
                style: AppText.body,
                decoration: InputDecoration(
                  hintText: "Enter your password",
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

              // Forgot password
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => ForgotPasswordScreen()),
                    );
                  },
                  child: const Text("Forgot Password?",
                      style: TextStyle(color: AppColors.primary)),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),

              AppPrimaryButton(
                label: "Login",
                loading: _loading,
                onPressed: login,
              ),
              const SizedBox(height: AppSpacing.lg),

              // Create account
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text("Don't have an account? ",
                      style: AppText.bodySecondary),
                  GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const RegisterScreen()),
                      );
                    },
                    child: const Text(
                      "Create Account",
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
}
