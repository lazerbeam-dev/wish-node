// lib/wishnode_api.dart
import 'dart:convert';
import 'package:http/http.dart' as http;

import 'widgets/wishpath_model.dart';
import 'models/wish_models.dart';

// -------------------------------------------------------------
// Models
// -------------------------------------------------------------

class Task {
  String id;
  String title;
  bool completed;
  String? completedAt;
  bool repeat;
  int repeatedAmount;

  Task({
    required this.id,
    required this.title,
    this.completed = false,
    this.completedAt,
    this.repeat = false,
    this.repeatedAmount = 0,
  });

  factory Task.fromJson(Map<String, dynamic> j) {
    return Task(
      id: j['id'],
      title: j['title'] ?? '',
      completed: j['completed'] == true,
      completedAt: j['completed_at'],
      repeat: j['repeat'] == true,
      repeatedAmount: j['repeated_amount'] != null ? (j['repeated_amount'] as int) : 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'completed': completed,
      if (completedAt != null) 'completed_at': completedAt,
      if (repeat) 'repeat': true,
      if (repeatedAmount != 0) 'repeated_amount': repeatedAmount,
    };
  }
}

class Phase {
  String id;
  String title;
  List<Task> tasks;

  Phase({required this.id, required this.title, required this.tasks});

  factory Phase.fromJson(Map<String, dynamic> j) {
    return Phase(
      id: j['id'],
      title: j['title'],
      tasks: (j['tasks'] ?? []).map<Task>((t) => Task.fromJson(t)).toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'tasks': tasks.map((t) => t.toJson()).toList(),
    };
  }
}

class WishCreate {
  String id;
  String ownerId;
  String title;
  List<Phase> phases;

  WishCreate({
    required this.id,
    required this.ownerId,
    required this.title,
    required this.phases,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'owner_id': ownerId,
      'title': title,
      'phases': phases.map((p) => p.toJson()).toList(),
    };
  }
}

class Wish {
  String id;
  String title;
  List<Phase> phases;
  String? status;
  DateTime? createdAt;

  Wish({
    required this.id,
    required this.title,
    required this.phases,
    this.status,
    this.createdAt,
  });

  factory Wish.fromJson(Map<String, dynamic> j) {
    return Wish(
      id: j['id'],
      title: j['title'],
      phases: (j['phases'] ?? []).map<Phase>((p) => Phase.fromJson(p)).toList(),
      status: j['status'],
      createdAt: j['created_at'] != null
          ? DateTime.tryParse(j['created_at'])
          : null,
    );
  }
}

class ItemOut {
  String id;
  String originWishId;
  String title;
  String emoji;
  String emojiAccent;
  String description;
  int legendariness;
  DateTime? createdAt;

  ItemOut({
    required this.id,
    required this.originWishId,
    required this.title,
    required this.emoji,
    required this.emojiAccent,
    required this.description,
    required this.legendariness,
    this.createdAt,
  });

  factory ItemOut.fromJson(Map<String, dynamic> j) {
    return ItemOut(
      id: j['id'],
      originWishId: j['origin_wish_id'],
      title: j['title'],
      emoji: j['emoji'],
      emojiAccent: j['emoji_accent'] ?? '',
      legendariness: j['legendariness'] ?? 0,
      description: j['description'] ?? '',
      createdAt: j['created_at'] != null
          ? DateTime.tryParse(j['created_at'])
          : null,
    );
  }
}


// -------------------------------------------------------------
// API Exception
// -------------------------------------------------------------

class ApiException implements Exception {
  final int status;
  final String message;
  ApiException(this.status, this.message);
  @override
  String toString() => 'ApiException($status): $message';
}


// -------------------------------------------------------------
// Wishnode API Client
// -------------------------------------------------------------

class WishnodeApi {
  final String baseUrl = 'http://localhost:8000';//'https://api.wishnode.com';//;
  final Map<String, String> defaultHeaders;

  // token (JWT) that will be appended to Authorization header when present
  String? _token;

  WishnodeApi({Map<String, String>? defaultHeaders})
      : defaultHeaders = defaultHeaders ?? {'Content-Type': 'application/json'} {
    print('WishnodeApi created: baseUrl=$baseUrl');
  }

  void setToken(String token) {
    _token = token;
    if (token.isNotEmpty) {
      defaultHeaders['Authorization'] = 'Bearer $token';
    } else {
      defaultHeaders.remove('Authorization');
    }
    print('WishnodeApi.setToken: token length=${token.length}');
  }

  /// Build headers per-request so we can add Authorization dynamically
  Map<String, String> _buildHeaders([Map<String, String>? extra]) {
    final Map<String, String> headers = Map<String, String>.from(defaultHeaders);
    if (_token != null && _token!.isNotEmpty) {
      headers['Authorization'] = 'Bearer $_token';
    }
    if (extra != null) headers.addAll(extra);
    return headers;
  }

  void _handleError(http.Response r) {
    String msg = r.reasonPhrase ?? '';
    try {
      final decoded = json.decode(r.body);
      if (decoded is Map && decoded['detail'] != null) {
        msg = decoded['detail'].toString();
      }
    } catch (_) {}
    throw ApiException(r.statusCode, msg);
  }

  // -----------------------------
  // User
  // -----------------------------

  Future<Map<String, dynamic>> createAnon() async {
    final r = await http.post(
      Uri.parse('$baseUrl/api/anon'),
      headers: _buildHeaders(),
    );
    if (r.statusCode >= 200 && r.statusCode < 300) {
      final j = json.decode(r.body) as Map<String, dynamic>;
      // Expecting { "anon_user_id": "...", "token": "..." }
      print("resp_from_create_anon: ${r.body}");
      // convenience: if token present, set it on this client
      final token = j['token'] as String?;
      if (token != null && token.isNotEmpty) {
        setToken(token);
      }
      return j;
    }
    _handleError(r);
    return {};
  }

  Future<Map<String, dynamic>> attachEmail(String email) async {
    final body = json.encode({
      'email': email,
    });

    final r = await http.post(
      Uri.parse('$baseUrl/api/users/email'),
      headers: _buildHeaders(),
      body: body,
    );

    if (r.statusCode >= 200 && r.statusCode < 300) {
      return json.decode(r.body) as Map<String, dynamic>;
    }

    _handleError(r);
    return {};
  }

  Future<Map<String, dynamic>> whoAmI() async {
    final r = await http.get(
      Uri.parse('$baseUrl/api/whoami'),
      headers: _buildHeaders(),
    );
    if (r.statusCode >= 200 && r.statusCode < 300) {
      print("resp_from_whoami: ${r.body}");
      return json.decode(r.body) as Map<String, dynamic>;
    }
    _handleError(r);
    return {};
  }

  // -----------------------------
  // Wishes
  // -----------------------------

  Future<List<WishSummary>> listUserWishes(String userId) async {
    final r = await http.get(
      Uri.parse('$baseUrl/api/users/$userId/wishes'),
      headers: _buildHeaders(),
    );
    if (r.statusCode >= 200 && r.statusCode < 300) {
      final list = json.decode(r.body)['wishes'] as List;
      return list.map<WishSummary>((e) => WishSummary.fromJson(e)).toList();
    }
    _handleError(r);
    return [];
  }

  /// Generate a plan on the backend. Sends Authorization header automatically.
  Future<String> generatePlan(String wish, {String context = "", String model = "gpt-4o-mini"}) async {
    if (_token == null || _token!.isEmpty) {
      throw Exception("Authentication token not set. Call setToken(...) or createAnon() first.");
    }

    final uri = Uri.parse('$baseUrl/api/wishes/plan');
    final body = jsonEncode({
      'wish': wish,
      'model': model,
      'context' : context
      // note: server currently requires token auth; no owner_id needed
    });

    // debug: show headers being sent
    final headers = _buildHeaders({'Accept': 'application/json', 'Content-Type': 'application/json'});
    print('[WishnodeApi] generatePlan -> POST $uri');
    print('[WishnodeApi] headers: $headers');
    print('[WishnodeApi] body: $body');

    try {
      final resp = await http
          .post(
            uri,
            headers: headers,
            body: body,
          )
          .timeout(Duration(seconds: 45));

      print('[WishnodeApi] response status: ${resp.statusCode}');
      print('[WishnodeApi] response body: ${resp.body}');

      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        return resp.body;
      } 
        else if(resp.statusCode == 403){
          return "MAXED_OUT";
        }
      else {
        String detail = 'Plan generation failed (${resp.statusCode})';
        try {
          final Map<String, dynamic> j = jsonDecode(resp.body);
          detail = j['detail'] ?? j['error'] ?? detail;
        } catch (_) {
          detail = resp.body.isNotEmpty ? resp.body : detail;
        }
        throw Exception(detail);
      }
    } catch (e) {
      print('[WishnodeApi] generatePlan ERROR: $e');
      rethrow;
    }
  }

  Future<String> createWish(WishCreate wish) async {
    final r = await http.post(
      Uri.parse('$baseUrl/api/wishes'),
      headers: _buildHeaders(),
      body: json.encode(wish.toJson()),
    );
    if (r.statusCode >= 200 && r.statusCode < 300) {
      final body = json.decode(r.body);
      return body['wish_id']?.toString() ?? '';
    }
    _handleError(r);
    return '';
  }

  Future<List<Wish>> listActiveWishes(String userId) async {
    final r = await http.get(
      Uri.parse('$baseUrl/api/wishes?user_id=$userId'),
      headers: _buildHeaders(),
    );
    if (r.statusCode >= 200 && r.statusCode < 300) {
      final list = json.decode(r.body)['wishes'] as List;
      return list.map((e) => Wish.fromJson(e)).toList();
    }
    _handleError(r);
    return [];
  }

  Future<WishModel> getWish(String id) async {
    final r = await http.get(
      Uri.parse('$baseUrl/api/wishes/$id'),
      headers: _buildHeaders(),
    );
    if (r.statusCode >= 200 && r.statusCode < 300) {
      return WishModel.parsePlanStrict(r.body, "");
    }
    _handleError(r);
    throw Exception('Unreachable');
  }

  Future<Map<String, dynamic>> completeTask(
    String wishId,
    String taskId, {
    bool markIncomplete = false,
  }) async {
    final body = json.encode({
      'mark_incomplete': markIncomplete,
    });

    final r = await http.post(
      Uri.parse('$baseUrl/api/wishes/$wishId/tasks/$taskId/complete'),
      headers: _buildHeaders(),
      body: body,
    );
    if (r.statusCode >= 200 && r.statusCode < 300) {
      if (r.body.trim().isEmpty) return {};
      return json.decode(r.body) as Map<String, dynamic>;
    }
    _handleError(r);
    return {};
  }

  Future<void> deleteWish(String wishId) async {
    final r = await http.delete(
      Uri.parse('$baseUrl/api/wishes/$wishId'),
      headers: _buildHeaders(),
    );
    if (r.statusCode >= 200 && r.statusCode < 300) return;
    _handleError(r);
  }

  Future<void> deleteTask(String wishId, String taskId) async {
    final r = await http.delete(
      Uri.parse('$baseUrl/api/wishes/$wishId/tasks/$taskId'),
      headers: _buildHeaders(),
    );
    if (r.statusCode >= 200 && r.statusCode < 300) return;
    _handleError(r);
  }

  Future<void> editTask(String wishId, String taskId, String newTitle, bool newRepeat) async {
    final body = json.encode({
      'title': newTitle,
      'repeat': newRepeat,
    });

    final r = await http.patch(
      Uri.parse('$baseUrl/api/wishes/$wishId/tasks/$taskId'),
      headers: _buildHeaders(),
      body: body,
    );

    if (r.statusCode >= 200 && r.statusCode < 300) return;
    _handleError(r);
  }

  Future<Map<String, dynamic>> addTask(
	String wishId,
	String phaseId,
	String newTitle,
	bool newRepeat,
) async {
	final body = json.encode({
		'title': newTitle,
		'repeat': newRepeat,
	});

	final r = await http.post(
		Uri.parse('$baseUrl/api/wishes/$wishId/phases/$phaseId/tasks'),
		headers: _buildHeaders(),
		body: body,
	);

	if (r.statusCode >= 200 && r.statusCode < 300) {
		return json.decode(r.body) as Map<String, dynamic>;
	}

	_handleError(r);
	throw Exception('addTask failed');
}


  // -----------------------------
  // Vault
  // -----------------------------

    Future<List<ItemOut>> getVault() async {
    final uri = Uri.parse('$baseUrl/api/vault');   // no query param
    final headers = _buildHeaders({'Accept': 'application/json'});
    //print('[WishnodeApi] getVault -> GET $uri headers: $headers');

    final r = await http.get(uri, headers: headers);
    if (r.statusCode >= 200 && r.statusCode < 300) {
      final body = json.decode(r.body);
      final list = (body['items'] as List?) ?? [];
      //print('[WishnodeApi] getVault: ITEMS RAW: ${json.encode(list)}');
      return list.map<ItemOut>((e) {
        // defensively handle missing keys
        final map = e as Map<String, dynamic>;
        return ItemOut.fromJson(map);
      }).toList();
    }
    _handleError(r);
    return [];
  }

  // -----------------------------
  // Nudging
  // -----------------------------

  Future<bool> shouldNudge(String userId) async {
    final r = await http.get(
      Uri.parse('$baseUrl/api/users/$userId/should_nudge'),
      headers: _buildHeaders(),
    );
    if (r.statusCode >= 200 && r.statusCode < 300) {
      return json.decode(r.body)['should_nudge'] == true;
    }
    _handleError(r);
    return false;
  }

  Future<String> testChatgpt() async {
    final r = await http.get(
      Uri.parse('$baseUrl/api/test_chatgpt'),
      headers: _buildHeaders(),
    );
    if (r.statusCode >= 200 && r.statusCode < 300) {
      final j = json.decode(r.body);
      return j['reply'] ?? json.encode(j);
    }
    _handleError(r);
    return '';
  }
}
