import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SecureStorageHelper {
  static final SecureStorageHelper instance = SecureStorageHelper._internal();
  SecureStorageHelper._internal();

  static const String _storageKey = 'phonecam_secure_salt_v1';

  List<int> _deriveKey(String salt) {
    return sha256.convert(utf8.encode('phonecam_secure_key_$salt')).bytes;
  }

  String _xorEncrypt(String text, List<int> keyBytes) {
    final textBytes = utf8.encode(text);
    final encrypted = List<int>.generate(textBytes.length, (i) {
      return textBytes[i] ^ keyBytes[i % keyBytes.length];
    });
    return base64.encode(encrypted);
  }

  String _xorDecrypt(String base64Text, List<int> keyBytes) {
    try {
      final encryptedBytes = base64.decode(base64Text);
      final decrypted = List<int>.generate(encryptedBytes.length, (i) {
        return encryptedBytes[i] ^ keyBytes[i % keyBytes.length];
      });
      return utf8.decode(decrypted);
    } catch (_) {
      return '';
    }
  }

  Future<void> write({required String key, required String value}) async {
    final prefs = await SharedPreferences.getInstance();
    final keyBytes = _deriveKey(key);
    final encrypted = _xorEncrypt(value, keyBytes);
    await prefs.setString('${_storageKey}_$key', encrypted);
  }

  Future<String?> read({required String key}) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('${_storageKey}_$key');
    if (raw == null || raw.isEmpty) return null;
    final keyBytes = _deriveKey(key);
    final decrypted = _xorDecrypt(raw, keyBytes);
    return decrypted.isNotEmpty ? decrypted : null;
  }

  Future<void> delete({required String key}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('${_storageKey}_$key');
  }
}
