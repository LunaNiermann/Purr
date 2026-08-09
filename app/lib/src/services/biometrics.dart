import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

/// Biometrics are a local unlock only — never the second factor.
/// The design was written iOS-first ("Face ID"); Android copy adapts.
class Biometrics {
  static final _auth = LocalAuthentication();

  /// True if the device has *any* secure way to authenticate — a biometric OR
  /// a device credential (PIN/pattern/password). This is what our
  /// `biometricOnly: false` unlock actually needs; if it's false there is no
  /// point offering "unlock without typing" at all, so we skip that screen.
  static Future<bool> canAuthenticate() async {
    try {
      return await _auth.isDeviceSupported();
    } on PlatformException {
      return false;
    }
  }

  /// True if dedicated biometric hardware is enrolled (face/fingerprint).
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

  /// Gate a sensitive action, but don't dead-end on a device with no lock at
  /// all: there's nothing to authenticate against, and the whole app already
  /// opened without one, so proceed. Returns false only when a lock exists and
  /// the person failed/cancelled it.
  static Future<bool> confirmOrBypass(String reason) async {
    if (!await canAuthenticate()) return true;
    return prompt(reason);
  }
}
