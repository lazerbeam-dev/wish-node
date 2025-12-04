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
  String summary;
  DateTime? createdAt;

  ItemOut({
    required this.id,
    required this.originWishId,
    required this.title,
    required this.summary,
    this.createdAt,
  });

  factory ItemOut.fromJson(Map<String, dynamic> j) {
    return ItemOut(
      id: j['id'],
      originWishId: j['origin_wish_id'],
      title: j['title'],
      summary: j['summary'] ?? '',
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
  final String baseUrl = 'http://localhost:8000';
  final Map<String, String> defaultHeaders;

  WishnodeApi({Map<String, String>? defaultHeaders})
    : defaultHeaders = defaultHeaders ?? {'Content-Type': 'application/json'};

  void _handleError(http.Response r) {
    String msg = r.reasonPhrase ?? '';
    try {
      final decoded = json.decode(r.body);
      if (decoded is Map && decoded['detail'] != null) {
        msg = decoded['detail'];
      }
    } catch (_) {}
    throw ApiException(r.statusCode, msg);
  }

  // -----------------------------
  // User
  // -----------------------------

  Future<String> createAnon() async {
    final r = await http.post(
      Uri.parse('$baseUrl/api/anon'),
      headers: defaultHeaders,
    );
    if (r.statusCode >= 200 && r.statusCode < 300) {
      return json.decode(r.body)['anon_user_id'];
    }
    _handleError(r);
    return '';
  }

  Future<String> claimUser(String anonId, String email, String pass) async {
    final r = await http.post(
      Uri.parse('$baseUrl/api/users/claim'),
      headers: defaultHeaders,
      body: json.encode({
        'anon_user_id': anonId,
        'email': email,
        'password_plain': pass,
      }),
    );
    if (r.statusCode >= 200 && r.statusCode < 300) {
      return json.decode(r.body)['user_id'];
    }
    _handleError(r);
    return '';
  }

  // -----------------------------
  // Wishes
  // -----------------------------

      Future<List<WishSummary>> listUserWishes(String userId) async {
    final r = await http.get(
      Uri.parse('$baseUrl/api/users/$userId/wishes'),
      headers: defaultHeaders,
    );
    if (r.statusCode >= 200 && r.statusCode < 300) {
      final list = json.decode(r.body)['wishes'] as List;
      return list.map<WishSummary>((e) => WishSummary.fromJson(e)).toList();
    }
    _handleError(r);
    return [];
  }

  Future<String> createWish(WishCreate wish) async {
    final r = await http.post(
      Uri.parse('$baseUrl/api/wishes'),
      headers: defaultHeaders,
      body: json.encode(wish.toJson()),
    );
    if (r.statusCode >= 200 && r.statusCode < 300) {
      return json.decode(r.body)['wish_id'];
    }
    _handleError(r);
    return '';
  }

  Future<List<Wish>> listActiveWishes(String userId) async {
    final r = await http.get(
      Uri.parse('$baseUrl/api/wishes?user_id=$userId'),
      headers: defaultHeaders,
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
      headers: defaultHeaders,
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
      headers: defaultHeaders,
      body: body,
    );
    if (r.statusCode >= 200 && r.statusCode < 300) {
      return json.decode(r.body) as Map<String, dynamic>;
    }
    _handleError(r);
    return {};
  }

  Future<void> deleteWish(String wishId) async {
    final r = await http.delete(
      Uri.parse('$baseUrl/api/wishes/$wishId'),
      headers: defaultHeaders,
    );
    if (r.statusCode >= 200 && r.statusCode < 300) return;
    _handleError(r);
  }

    /// Delete a task belonging to a wish.
  /// Endpoint: DELETE /api/wishes/{wishId}/tasks/{taskId}
  Future<void> deleteTask(String wishId, String taskId) async {
    final r = await http.delete(
      Uri.parse('$baseUrl/api/wishes/$wishId/tasks/$taskId'),
      headers: defaultHeaders,
    );
    if (r.statusCode >= 200 && r.statusCode < 300) return;
    _handleError(r);
  }

  /// Edit a task's title / repeat flag.
  /// Endpoint: PATCH /api/wishes/{wishId}/tasks/{taskId}
  /// Body: { "title": "...", "repeat": true/false }
  Future<void> editTask(String wishId, String taskId, String newTitle, bool newRepeat) async {
    final body = json.encode({
      'title': newTitle,
      'repeat': newRepeat,
    });

    // Use PATCH if the server supports partial updates; use PUT if it expects full replacement.
    final r = await http.patch(
      Uri.parse('$baseUrl/api/wishes/$wishId/tasks/$taskId'),
      headers: defaultHeaders,
      body: body,
    );

    if (r.statusCode >= 200 && r.statusCode < 300) return;
    _handleError(r);
  }

    Future<void> addTask(String wishId, String phaseId, String newTitle, bool newRepeat) async {
    final body = json.encode({
      'title': newTitle,
      'repeat': newRepeat,
    });

    final r = await http.post(
      Uri.parse('$baseUrl/api/wishes/$wishId/phases/$phaseId/tasks'),
      headers: defaultHeaders,
      body: body,
    );

    if (r.statusCode >= 200 && r.statusCode < 300) return;
    _handleError(r);
  }


  // -----------------------------
  // Vault
  // -----------------------------

  Future<List<ItemOut>> getVault(String userId) async {
    final r = await http.get(
      Uri.parse('$baseUrl/api/vault?user_id=$userId'),
      headers: defaultHeaders,
    );
    if (r.statusCode >= 200 && r.statusCode < 300) {
      final list = json.decode(r.body)['items'] as List;
      return list.map((e) => ItemOut.fromJson(e)).toList();
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
      headers: defaultHeaders,
    );
    if (r.statusCode >= 200 && r.statusCode < 300) {
      return json.decode(r.body)['should_nudge'] == true;
    }
    _handleError(r);
    return false;
  }

  // -----------------------------
  // AI / Plan
  // -----------------------------

  Future<Map<String, dynamic>> getPlan(String wish) async {
    final r = await http.post(
      Uri.parse('$baseUrl/api/wishes/plan'),
      headers: defaultHeaders,
      body: json.encode({'wish': wish}),
    );
    if (r.statusCode >= 200 && r.statusCode < 300) {
      return json.decode(r.body);
    }
    _handleError(r);
    return {};
  }

  Future<String> testChatgpt() async {
    final r = await http.get(
      Uri.parse('$baseUrl/api/test_chatgpt'),
      headers: defaultHeaders,
    );
    if (r.statusCode >= 200 && r.statusCode < 300) {
      final j = json.decode(r.body);
      return j['reply'] ?? json.encode(j);
    }
    _handleError(r);
    return '';
  }
}
