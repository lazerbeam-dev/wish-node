import 'package:flutter/material.dart';

class RepeatTaskService {
	final Duration defaultCooldown;
	final Map<String, int> _counts = {};
	final Map<String, DateTime?> _nextAvailable = {};

	RepeatTaskService({required this.defaultCooldown});

	void initForTask(String taskId, {int initialCount = 0}) {
		_counts.putIfAbsent(taskId, () => initialCount);
		_nextAvailable.putIfAbsent(taskId, () => null);
	}

	void removeTask(String taskId) {
		_counts.remove(taskId);
		_nextAvailable.remove(taskId);
	}

	bool isDue(String taskId) {
		final next = _nextAvailable[taskId];
		if (next == null) return true;
		return DateTime.now().isAfter(next) || DateTime.now().isAtSameMomentAs(next);
	}

	void applyCompletion(String taskId) {
		_counts[taskId] = (_counts[taskId] ?? 0) + 1;
		_nextAvailable[taskId] = DateTime.now().add(defaultCooldown);
	}

	int repeatCount(String taskId) => _counts[taskId] ?? 0;

	DateTime? nextAvailableAt(String taskId) => _nextAvailable[taskId];

	void reset(String taskId) {
		_counts[taskId] = 0;
		_nextAvailable[taskId] = null;
	}
}
