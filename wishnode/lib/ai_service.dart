// lib/ai_service.dart
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

/// Simple AI / backend service wrapper.
/// Replace `_base` with your deployed backend URL.
class AiService {
  static const String _base = 'http://localhost:8000';

  // Temporary local stub plan generator (keeps previous sample)
   // Calls backend plan-generation endpoint. Returns the assistant "raw" text (same shape as previous stub).
  // Falls back to the local stub plan if the backend is unreachable or returns an error.
  static Future<String> generatePlan(String wish, String ownerId, {String model = "gpt-4o-mini"}) async {
  if (ownerId == ""){
    throw Exception("need a user ID");
  }
  final uri = Uri.parse('$_base/api/wishes/plan');
  final body = jsonEncode({
    'wish': wish,
    'model': model,
    'owner_id': ownerId
  });

  // lightweight debug logging — visible in Flutter debug console
  print('[AiService] generatePlan -> POST $uri');
  print('[AiService] request body: $body');

  try {
    final resp = await http
        .post(
          uri,
          headers: {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
          },
          body: body,
        )
        .timeout(Duration(seconds: 45));

    print('[AiService] response status: ${resp.statusCode}');
    print('[AiService] response body: ${resp.body}');

    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      // Return exactly what the server returned (no transformation).
      return resp.body;
    } else {
      // Try to extract a helpful message from the backend JSON
      String detail = 'Plan generation failed (${resp.statusCode})';
      try {
        final Map<String, dynamic> j = jsonDecode(resp.body);
        detail = j['detail'] ?? j['error'] ?? detail;
      } catch (_) {
        // fallback to raw body if not JSON
        detail = resp.body.isNotEmpty ? resp.body : detail;
      }
      throw Exception(detail);
    }
  } catch (e) {
    // Log and rethrow so caller can decide what to do (no local fallback).
    print('[AiService] generatePlan ERROR: $e');
    rethrow;
  }
}

  /// Optional: check whether to show nudge (calls backend endpoint).
  /// Returns true if backend suggests a nudge.
  static Future<bool> shouldNudge(String userId) async {
    final uri = Uri.parse('$_base/api/users/$userId/should_nudge');
    final resp = await http.get(uri, headers: {'Accept': 'application/json'});
    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      try {
        final Map<String, dynamic> j = jsonDecode(resp.body);
        return j['should_nudge'] == true;
      } catch (_) {
        return false;
      }
    } else {
      return false;
    }
  }
}
