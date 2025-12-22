import 'package:flutter/material.dart';

class RepeatTaskService {
	final Duration defaultCooldown;
	final Map<String, int> _counts = {};
	final Map<String, DateTime?> _nextAvailable = {};

	RepeatTaskService({required this.defaultCooldown});

	// ─────────────────────────────────────────────
	// Logging helper (single switch)
	// ─────────────────────────────────────────────
	void _log(String msg) {
		const bool enabled = false; // set to false to silence logs
		if (enabled) {
			// ignore: avoid_print
			print('[RepeatTaskService] $msg');
		}
	}

	// ─────────────────────────────────────────────
	// Lifecycle
	// ─────────────────────────────────────────────
	void initForTask(String taskId, {int initialCount = 0}) {
		final existed = _counts.containsKey(taskId);

		_counts.putIfAbsent(taskId, () => initialCount);
		_nextAvailable.putIfAbsent(taskId, () => null);

		_log(
			'initForTask($taskId) '
			'existed=$existed '
			'count=${_counts[taskId]} '
			'next=${_nextAvailable[taskId]}'
		);
	}

	void removeTask(String taskId) {
		_log('removeTask($taskId)');
		_counts.remove(taskId);
		_nextAvailable.remove(taskId);
	}

	void reset(String taskId) {
		_log('reset($taskId)');
		_counts[taskId] = 0;
		_nextAvailable[taskId] = null;
	}

	// ─────────────────────────────────────────────
	// Core logic
	// ─────────────────────────────────────────────
	bool isDue(String taskId) {
		final now = DateTime.now();
		final next = _nextAvailable[taskId];

		final due = next == null ||
			now.isAfter(next) ||
			now.isAtSameMomentAs(next);

		_log(
			'isDue($taskId) '
			'now=$now '
			'next=$next '
			'due=$due'
		);

		return due;
	}

	void applyCompletion(String taskId) {
		final now = DateTime.now();
		final next = now.add(defaultCooldown);

		_counts[taskId] = (_counts[taskId] ?? 0) + 1;
		_nextAvailable[taskId] = next;

		_log(
			'applyCompletion($taskId) '
			'count=${_counts[taskId]} '
			'nextAvailable=$next'
		);
	}

	// ─────────────────────────────────────────────
	// Accessors
	// ─────────────────────────────────────────────
	int repeatCount(String taskId) => _counts[taskId] ?? 0;

	DateTime? nextAvailableAt(String taskId) => _nextAvailable[taskId];
}
