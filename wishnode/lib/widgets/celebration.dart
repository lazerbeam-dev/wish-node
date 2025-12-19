// lib/widgets/wish_node_map/celebration.dart
import 'package:flutter/material.dart';
import 'package:confetti/confetti.dart';
import 'dart:math';
import '../ui/pallet.dart';

/// Lightweight celebration orchestration that runs:
/// - per-phase animation controllers (owned by caller)
/// - global confetti overlay (owned here)
class CelebrationService {
  final Map<String, AnimationController> phaseControllers; // owned by WishNodeMap
  final ConfettiController confettiController;
  final Duration perPhaseHold;
  final Duration phaseStagger;

  CelebrationService({
    required this.phaseControllers,
    required this.confettiController,
    this.perPhaseHold = const Duration(milliseconds: 500),
    this.phaseStagger = const Duration(milliseconds: 120),
  });

  /// Play the celebration for a single phase (forward -> hold -> reverse)
  Future<void> celebratePhase(String phaseId) async {
    final pc = phaseControllers[phaseId];
    if (pc == null) return;
    try {
      await pc.forward(from: 0.0);
      await Future.delayed(perPhaseHold);
      await pc.reverse();
    } catch (e) {
      // ignore animation errors (e.g. disposed)
      debugPrint('celebratePhase error for $phaseId: $e');
    }
  }

  /// Celebrate all phases left-to-right, but optionally play first the final-phase moment
  /// `finalPhaseFirst` = true will play the last phase first (dramatic final moment), then sweep L->R.
  Future<void> celebrateAllPhasesSequential(List<String> phaseOrder, {bool finalPhaseFirst = true}) async {
    if (phaseOrder.isEmpty) return;
    // final-phase dramatic beat
    if (finalPhaseFirst) {
      final last = phaseOrder.last;
      await celebratePhase(last);
    }

    // start confetti slightly after the final-phase (so it overlaps)
    confettiController.play();

    // sweep through phases left->right (including last again if you want — here we run all)
    for (final pid in phaseOrder) {
      await Future.delayed(phaseStagger);
      await celebratePhase(pid);
    }

    // leave confetti for a short tail (controller duration should be long enough)
    await Future.delayed(const Duration(milliseconds: 350));
  }
}

/// A full-screen confetti overlay you can drop in the widget tree.
/// Keeps configuration centralised so you can tune particle counts/forces in one place.
class ConfettiOverlay extends StatelessWidget {
  final ConfettiController controller;
  final Path Function(Size)? createParticlePath;

  const ConfettiOverlay({super.key, required this.controller, this.createParticlePath});

  Path _starPath(Size size) {
    // fallback star path if none supplied
    final Path path = Path();
    const int points = 5;
    final double outerRadius = size.width / 2;
    final double innerRadius = outerRadius / 2.5;
    final double step = pi / points;
    double rotation = -pi / 2;
    for (int i = 0; i < points * 2; i++) {
      final double radius = i.isEven ? outerRadius : innerRadius;
      final double x = radius * cos(rotation) + outerRadius;
      final double y = radius * sin(rotation) + outerRadius;
      if (i == 0) path.moveTo(x, y);
      else path.lineTo(x, y);
      rotation += step;
    }
    path.close();
    return path;
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConfettiWidget(
          confettiController: controller,
          blastDirectionality: BlastDirectionality.explosive,
          shouldLoop: false,
          emissionFrequency: 0.4, // tuned to be lively but not insane
          numberOfParticles: 12,
          gravity: 0.25,
          minBlastForce: 6,
          maxBlastForce: 14,
          colors: [Palette.brightCta, Palette.accent, Palette.card],
          createParticlePath: createParticlePath ?? _starPath,
        ),
      ),
    );
  }
}
