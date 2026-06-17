import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key}); // Added super.key

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final username = TextEditingController();
  final answer = TextEditingController();
  final newPassword = TextEditingController();

  String message = "";
  Color messageColor = Colors.white;

  void resetPassword() async {
    // 1. Validation Check
    if (username.text.trim().isEmpty || 
        answer.text.trim().isEmpty || 
        newPassword.text.trim().isEmpty) {
      setState(() {
        message = "Please fill all fields!";
        messageColor = Colors.orangeAccent;
      });
      return;
    }

    final prefs = await SharedPreferences.getInstance();

    String savedUsername = prefs.getString('username') ?? "";
    String savedAnswer = prefs.getString('answer') ?? "";

    // 2. Async Gap Guard: Check if widget is still mounted
    if (!mounted) return;

    if (username.text.trim() == savedUsername && answer.text.trim() == savedAnswer) {
      await prefs.setString('password', newPassword.text.trim());

      // ✅ 3. Async Gap Guard after another await
      if (!mounted) return;

      setState(() {
        message = "Password Reset Successfully!";
        messageColor = Colors.green;
        // Fields clear karna reset ke baad
        username.clear();
        answer.clear();
        newPassword.clear();
      });

    } else {
      setState(() {
        message = "Wrong Username or Answer!";
        messageColor = Colors.redAccent;
      });
    }
  }

  // Memory free karne ke liye controllers dispose karein
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
      backgroundColor: const Color(0xFF0A0F1E),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 40),

              const Text(
                "Reset Password",
                style: TextStyle(
                  color: Colors.white, 
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 30),

              TextField(
                controller: username,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  hintText: "Username",
                  hintStyle: TextStyle(color: Colors.grey),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.grey),
                  ),
                  focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.white),
                  ),
                ),
              ),

              const SizedBox(height: 15),

              TextField(
                controller: answer,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  hintText: "Your pet name?",
                  hintStyle: TextStyle(color: Colors.grey),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.grey),
                  ),
                  focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.white),
                  ),
                ),
              ),

              const SizedBox(height: 15),

              TextField(
                controller: newPassword,
                obscureText: true,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  hintText: "New Password",
                  hintStyle: TextStyle(color: Colors.grey),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.grey),
                  ),
                  focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.white),
                  ),
                ),
              ),

              const SizedBox(height: 35),

              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: resetPassword,
                  child: const Text(
                    "Reset Password",
                    style: TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ),
              ),

              const SizedBox(height: 25),

              Text(
                message,
                style: TextStyle(
                  color: messageColor, 
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}