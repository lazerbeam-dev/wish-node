// lib/widgets/task_edit_sheet.dart
import 'package:flutter/material.dart';
import 'package:wishnode/ui/pallet.dart';

/// Shows a modal bottom sheet for editing a task.
/// Returns a Map<String, dynamic>? with keys:
///   { "title": String, "repeat": bool }
/// or null if cancelled.
Future<Map<String, dynamic>?> showTaskEditSheet(
  BuildContext context, {
  required String initialTitle,
  required bool initialRepeat,
}) {
  return showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Palette.card,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(12))),
    builder: (ctx) {
      // Use a StatefulBuilder so we can mutate local state inside the sheet without a full widget
      String title = initialTitle;
      bool repeat = initialRepeat;
      final TextEditingController controller = TextEditingController(text: initialTitle);

      return Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
        ),
        child: StatefulBuilder(
          builder: (BuildContext innerCtx, StateSetter setInner) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Edit task', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
                SizedBox(height: 12),
                TextField(
                  controller: controller,
                  autofocus: true,
                  style: TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Task title',
                    hintStyle: TextStyle(color: Palette.muted.withOpacity(0.7)),
                    filled: true,
                    fillColor: Palette.bg.withOpacity(0.02),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                    contentPadding: EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                  ),
                  onChanged: (v) => title = v,
                ),
                SizedBox(height: 12),
                Row(
                  children: [
                    Checkbox(
                      value: repeat,
                      onChanged: (v) => setInner(() => repeat = v ?? false),
                      activeColor: Palette.accent,
                    ),
                    SizedBox(width: 8),
                    Text('Repeat (habit)', style: TextStyle(color: Palette.muted)),
                  ],
                ),
                SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Palette.accent,
                      foregroundColor: Colors.black,
                      padding: EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: () {
                      final trimmed = controller.text.trim();
                      Navigator.of(innerCtx).pop({
                        'title': trimmed,
                        'repeat': repeat,
                      });
                    },
                    child: Text('Save'),
                  ),
                ),
                SizedBox(height: 8),
              ],
            );
          },
        ),
      );
    },
  );
}

/// Shows a modal bottom sheet for adding a task.
/// Returns a Map<String, dynamic>? with keys:
///   { "title": String, "repeat": bool }
/// or null if cancelled.
Future<Map<String, dynamic>?> showTaskAddSheet(
  BuildContext context,
) {
  return showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Palette.card,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(12))),
    builder: (ctx) {
      String title = '';
      bool repeat = false;
      final TextEditingController controller = TextEditingController(text: '');

      return Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
        ),
        child: StatefulBuilder(
          builder: (BuildContext innerCtx, StateSetter setInner) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Add task', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
                SizedBox(height: 12),
                TextField(
                  controller: controller,
                  autofocus: true,
                  style: TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Task title',
                    hintStyle: TextStyle(color: Palette.muted.withOpacity(0.7)),
                    filled: true,
                    fillColor: Palette.bg.withOpacity(0.02),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                    contentPadding: EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                  ),
                  onChanged: (v) => title = v,
                ),
                SizedBox(height: 12),
                Row(
                  children: [
                    Checkbox(
                      value: repeat,
                      onChanged: (v) => setInner(() => repeat = v ?? false),
                      activeColor: Palette.accent,
                    ),
                    SizedBox(width: 8),
                    Text('Repeat (habit)', style: TextStyle(color: Palette.muted)),
                  ],
                ),
                SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Palette.good,
                      foregroundColor: Colors.black,
                      padding: EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: () {
                      final trimmed = controller.text.trim();
                      Navigator.of(innerCtx).pop({
                        'title': trimmed,
                        'repeat': repeat,
                      });
                    },
                    child: Text('Add'),
                  ),
                ),
                SizedBox(height: 8),
              ],
            );
          },
        ),
      );
    },
  );
}