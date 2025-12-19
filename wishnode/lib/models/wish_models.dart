// lib/models/wish_models.dart
import 'dart:convert';

class TaskModel {
	final String id;
	String text;
	bool repeat;
	bool completed;
	DateTime? completedAt;
  int? repeatedAmount;
  String phaseId;

	TaskModel({
		required this.id,
		required this.text,
		this.completed = false,
		this.repeat = false,
		this.completedAt,
    this.repeatedAmount,
    required this.phaseId
	});
}

class PhaseModel {
	final String id;
	final String title;
	final List<TaskModel> tasks;

	PhaseModel({required this.id, required this.title, required this.tasks});
}

class WishModel {
	final String id;
	final String title;
	final List<PhaseModel> phases;

	WishModel({required this.id, required this.title, required this.phases});

	static WishModel parsePlanStrict(String respBody, String fallbackTitle) {
  dynamic decoded;
  try {
    decoded = jsonDecode(respBody);
  } catch (e) {
    print('[parsePlanStrict] JSON decode error: $e');
    throw Exception('Invalid JSON from server.');
  }

  if (decoded is! Map) {
    print('[parsePlanStrict] Top-level JSON was not a Map.');
    throw Exception('Unexpected response shape.');
  }

  // --- locate plan-like object: prefer "plan", then "wish", then top-level ---
  Map<String, dynamic>? planObj;
  Map<String, dynamic>? wishObj;
  if (decoded.containsKey('plan') && decoded['plan'] is Map) {
    planObj = Map<String, dynamic>.from(decoded['plan']);
  } else if (decoded.containsKey('wish') && decoded['wish'] is Map) {
    wishObj = Map<String, dynamic>.from(decoded['wish']);
    // map wish -> plan shape for parsing convenience
    planObj = {
      'title': wishObj['title'],
      'phases': wishObj.containsKey('phases') ? wishObj['phases'] : []
    };
  } else if (decoded.containsKey('title') && decoded.containsKey('phases')) {
    planObj = {
      'title': decoded['title'],
      'phases': decoded['phases']
    };
  }

  if (planObj == null) {
    print('[parsePlanStrict] Missing or invalid "plan" / "wish" field.');
    throw Exception('No plan returned.');
  }

  // Title fallback
  final String title =
      (planObj['title'] is String && (planObj['title'] as String).trim().isNotEmpty)
          ? planObj['title']
          : fallbackTitle;

  // phases must be a list
  if (planObj['phases'] == null || planObj['phases'] is! List) {
    print('[parsePlanStrict] Missing "phases" array.');
    throw Exception('Plan missing phases array.');
  }

  final phasesJson = planObj['phases'] as List;
  final phases = <PhaseModel>[];
  int pid = 1;

  for (final pRaw in phasesJson) {
    if (pRaw is! Map) {
      print('[parsePlanStrict] Phase entry not an object: $pRaw');
      throw Exception('Invalid phase entry.');
    }
    final Map<String, dynamic> p = Map<String, dynamic>.from(pRaw);

    final String pTitle =
        (p['title'] is String && (p['title'] as String).trim().isNotEmpty)
            ? p['title']
            : 'Phase $pid';

    // phase id fallback
    final String pId = (p['id'] is String && (p['id'] as String).isNotEmpty)
        ? p['id']
        : 'phase_$pid';

    if (p['tasks'] == null || p['tasks'] is! List) {
      print('[parsePlanStrict] Missing tasks list in phase $pid');
      throw Exception('Phase missing tasks.');
    }

    final tasksJson = p['tasks'] as List;
    final tasks = <TaskModel>[];
    int tid = 1;
    for (final tRaw in tasksJson) {
      if (tRaw is! Map) {
        print('[parsePlanStrict] Task entry not an object: $tRaw');
        throw Exception('Invalid task entry.');
      }
      final Map<String, dynamic> t = Map<String, dynamic>.from(tRaw);

      final String text = ((t['title'] ?? t['text'] ?? '').toString()).trim();
      if (text.isEmpty) {
        print('[parsePlanStrict] Empty task title in phase $pid');
        throw Exception('Task missing title.');
      }

      final bool repeat = t['repeat'] == true;

      // task id fallback
      final String tId = (t['id'] is String && (t['id'] as String).isNotEmpty)
          ? t['id']
          : 'task_${pid}_$tid';

      // completed field safe parse
      final bool completed = t['completed'] == true;

      // completed_at parse (ISO string) -> DateTime?
      DateTime? completedAt;
      if (t['completed_at'] != null) {
        try {
          final cand = t['completed_at'];
          if (cand is String && cand.isNotEmpty) {
            completedAt = DateTime.parse(cand);
          } else if (cand is DateTime) {
            completedAt = cand;
          }
        } catch (e) {
          // ignore parse error; leave null
          completedAt = null;
        }
      }

      // repeated_amount parse -> int (safe)
      int repeatedAmount = 0;
      if (t.containsKey('repeated_amount')) {
        final ra = t['repeated_amount'];
        if (ra is int) {
          repeatedAmount = ra;
        } else if (ra is String) {
          try {
            repeatedAmount = int.parse(ra);
          } catch (_) {
            repeatedAmount = 0;
          }
        }
      } else if (t.containsKey('repeatedAmount')) {
        // sometimes data may be camelCase
        final ra = t['repeatedAmount'];
        if (ra is int) repeatedAmount = ra;
      }

      tasks.add(TaskModel(
        id: tId,
        text: text,
        repeat: repeat,
        completed: completed,
        completedAt: completedAt,
        repeatedAmount: repeatedAmount,
        phaseId: p["id"]
      ));

      tid++;
    } // tasks

    phases.add(PhaseModel(id: pId, title: pTitle, tasks: tasks));
    pid++;
  } // phases loop

  // choose wish id: prefer wrapped wish object id when available
  String wishId = '';
  if (wishObj != null && wishObj.containsKey('id') && wishObj['id'] is String) {
    wishId = wishObj['id'];
  } else if (decoded.containsKey('id') && decoded['id'] is String) {
    wishId = decoded['id'];
  } else if (planObj.containsKey('id') && planObj['id'] is String) {
    wishId = planObj['id'];
  } else {
    // fallback: empty string (caller may not rely on id), or you can generate one
    wishId = '';
  }

  return WishModel(id: wishId, title: title, phases: phases);
}

}

class WishSummary {
	String id;
	String title;
	String? status;
	bool deleted;

	WishSummary({
		required this.id,
		required this.title,
		this.status,
		this.deleted = false,
	});

	factory WishSummary.fromJson(Map<String, dynamic> j) {
		return WishSummary(
			id: j['id'],
			title: j['title'] ?? '',
			status: j['status'],
			deleted: j['deleted'] == true,
		);
	}
}

