import 'package:supabase_flutter/supabase_flutter.dart';

class OTPService {
  final SupabaseClient _client = Supabase.instance.client;

  Future<bool> sendOTP(String phoneNumber) async {
    try {
      final otpCode = (100000 + DateTime.now().millisecondsSinceEpoch % 900000)
          .toString();

      await _client.from('otp_verification').insert({
        'phone_number': phoneNumber,
        'otp_code': otpCode,
        'expires_at': DateTime.now()
            .add(const Duration(minutes: 5))
            .toIso8601String(),
        'is_verified': false,
      });

      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> verifyOTP(String phoneNumber, String otpCode) async {
    try {
      final response = await _client
          .from('otp_verification')
          .select()
          .eq('phone_number', phoneNumber)
          .eq('otp_code', otpCode)
          .eq('is_verified', false)
          .gt('expires_at', DateTime.now().toIso8601String())
          .order('created_at', ascending: false)
          .limit(1);

      if (response.isNotEmpty) {
        await _client
            .from('otp_verification')
            .update({'is_verified': true})
            .eq('id', response[0]['id']);

        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }
}
