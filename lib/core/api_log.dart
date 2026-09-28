import 'dart:convert';

import 'package:flutter/foundation.dart';

// Diagnostics for the API/session lifecycle. These stay on in release builds
// (visible via `adb logcat`) because the bug we're chasing — being logged out
// immediately after a successful login — only reproduces against the real
// backend on a real device.
//
// Grep the device log for `[api]` and `[session]`:
//   adb logcat -s flutter:V | grep -E '\[api\]|\[session\]'

void apiLog(String message) => debugPrint('[api] $message');

void sessionLog(String message) => debugPrint('[session] $message');

/// Decodes the *unverified* payload half of our HS256 token. The signature is
/// what protects the token; the payload is plain base64url, so reading it
/// client-side to report role/expiry is safe and tells us instantly whether a
/// 401 is an expiry problem, a role problem, or neither.
Map<String, dynamic>? decodeTokenPayload(String token) {
  try {
    final parts = token.split('.');
    if (parts.length != 3) return null;
    var payload = parts[1].replaceAll('-', '+').replaceAll('_', '/');
    while (payload.length % 4 != 0) {
      payload += '=';
    }
    final decoded = jsonDecode(utf8.decode(base64.decode(payload)));
    return decoded is Map<String, dynamic> ? decoded : null;
  } catch (_) {
    return null;
  }
}

/// Never logs the token itself. `id` is a stable non-reversible handle so the
/// same token can be correlated across log lines (minted here, used there).
String describeToken(String? token) {
  if (token == null) return 'none';
  if (token.isEmpty) return 'empty';

  final id = 'id=${token.hashCode.toRadixString(16)} len=${token.length}';
  final payload = decodeTokenPayload(token);
  if (payload == null) return '$id <payload not decodable>';

  final exp = payload['exp'];
  var expText = 'n/a';
  var expired = false;
  if (exp is int) {
    final expiresAt = DateTime.fromMillisecondsSinceEpoch(exp * 1000);
    expired = expiresAt.isBefore(DateTime.now());
    expText = expiresAt.toIso8601String();
  }

  return '$id role=${payload['role']} phone=${maskPhone(payload['phone']?.toString())} '
      'exp=$expText${expired ? ' *** EXPIRED ***' : ''}';
}

/// Masks the middle of a phone number but keeps the leading `+91` (if present)
/// and the last 4 digits, so an E.164 vs bare-10-digit mismatch is still
/// obvious in the log without writing a full number to it.
String maskPhone(String? phone) {
  final value = phone ?? '';
  if (value.isEmpty) return 'none';
  if (value.length <= 4) return value;
  final keepHead = value.startsWith('+') ? 3 : 0;
  final masked = '*' * (value.length - keepHead - 4);
  return '${value.substring(0, keepHead)}$masked${value.substring(value.length - 4)}';
}

/// Response bodies are small here, but truncate anyway so a stray HTML error
/// page doesn't flood the log.
String shortBody(String body) {
  final collapsed = body.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (collapsed.isEmpty) return '<empty>';
  return collapsed.length <= 200 ? collapsed : '${collapsed.substring(0, 200)}…';
}
