import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

/// Biometrics are a local unlock only — never the second factor.
/// The design was written iOS-first ("Face ID"); Android copy adapts.
class Biometrics {
  static final _auth = LocalAuthentication();

  static Future<bool> available() async {
    try {
      return await _auth.isDeviceSupported() &&
          await _auth.canCheckBiometrics;
    } on PlatformException {
      return false;
    }
  }

  /// Platform-appropriate label for buttons and copy.
  static Future<String> label() async {
    try {
      final types = await _auth.getAvailableBiometrics();
      if (types.contains(BiometricType.face)) return 'face unlock';
      if (types.contains(BiometricType.fingerprint)) return 'fingerprint';
      if (types.contains(BiometricType.strong) ||
          types.contains(BiometricType.weak)) {
        return 'screen lock';
      }
    } on PlatformException {
      // fall through
    }
    return 'screen lock';
  }

  static Future<bool> prompt(String reason) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: false, // device credential is an acceptable gate
          stickyAuth: true,
        ),
      );
    } on PlatformException {
      return false;
    }
  }
}
