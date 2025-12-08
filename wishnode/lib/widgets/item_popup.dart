import 'dart:async';
import 'package:flutter/material.dart';
import 'item_card.dart';

/// A bottom popup that briefly shows an item using ItemCard.
/// Safer version — does NOT use Positioned (no ParentDataWidget issues).
class ItemPopup extends StatefulWidget {
  final Duration showDuration;
  const ItemPopup({super.key, this.showDuration = const Duration(milliseconds: 3200)});

  @override
  ItemPopupState createState() => ItemPopupState();
}

class ItemPopupState extends State<ItemPopup> {
  Map<String, dynamic>? _item;
  bool _visible = false;
  Timer? _hideTimer;

  /// Show the popup. Cancels any previous timer and restarts display.
  void show(Map<String, dynamic> item) {
    _hideTimer?.cancel();
    setState(() {
      _item = item;
      _visible = true;
    });
    _hideTimer = Timer(widget.showDuration, () {
      if (!mounted) return;
      setState(() => _visible = false);
      // clear data after the hide animation finishes
      Timer(const Duration(milliseconds: 320), () {
        if (mounted) setState(() => _item = null);
      });
    });
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Align bottom-center, slide from offscreen (y=0.9) to y=0.0
    final slideOffset = _visible ? Offset(0, 0) : const Offset(0, 0.9);

    return IgnorePointer(
      ignoring: !_visible,
      child: SafeArea(
        // Keep it visible above nav bars on phones
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
            child: AnimatedSlide(
              offset: slideOffset,
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 220),
                opacity: _visible ? 1.0 : 0.0,
                child: _item == null
                    ? const SizedBox.shrink()
                    : ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 720, minHeight: 90),
                        child: Material(
                          color: const Color.fromARGB(255, 0, 0, 0),
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            child: ItemCard(item: _item!),
                          ),
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
