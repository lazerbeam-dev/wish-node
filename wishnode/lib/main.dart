// lib/main.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart';
import 'widgets/wishpath_model.dart';
import 'widgets/goal_input.dart';
import 'widgets/sidebar.dart';
import 'ai_service.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'models/wish_models.dart';
// Add import for the API wrapper
import 'wishnode_api.dart';

// Add import for the popup widget
import 'widgets/item_popup.dart';

const String _kStoredUserIdKey = 'wishnode_anon_user_id';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  String? storedUserId;
  try {
    final prefs = await SharedPreferences.getInstance();
    storedUserId = prefs.getString(_kStoredUserIdKey);
    print('[main] loaded stored user id -> ${storedUserId ?? "<null>"}');
  } catch (e) {
    print('[main] error reading SharedPreferences: $e');
  }

  runApp(WishnodeApp(initialStoredUserId: storedUserId));
}

class WishnodeApp extends StatelessWidget {
  final String? initialStoredUserId;
  const WishnodeApp({Key? key, this.initialStoredUserId}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      // ...
      home: WishnodeHome(initialStoredUserId: initialStoredUserId),
    );
  }
}

class WishnodeHome extends StatefulWidget {
  final String? initialStoredUserId;
  const WishnodeHome({this.initialStoredUserId});

  @override
  _WishnodeHomeState createState() => _WishnodeHomeState();
}

class _WishnodeHomeState extends State<WishnodeHome> {
  // static instance for global show/hide calls
  final GlobalKey _sidebarKey = GlobalKey();
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _panelVisible = true;
  bool _loading = false;
  WishModel? _wish;

  // popup key
  final GlobalKey<ItemPopupState> _itemPopupKey = GlobalKey<ItemPopupState>();

  // API client + user id
  late final WishnodeApi _apiClient;
  String? _userId;
  bool _fetchingUser = true;
  String? _userFetchError;

  @override
  void initState() {
    super.initState();
    _apiClient = WishnodeApi();
    _fetchOrCreateAnonUser();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _showPanel() {
    _setPanelVisible(true);
  }

  void _hidePanel() {
    _setPanelVisible(false);
  }

  Future<void> _handleDeleteWish(String wishId) async {
    try {
      await _apiClient.deleteWish(wishId);
      // refresh sidebar after successful delete
      (_sidebarKey.currentState as dynamic)?.refresh();
    } catch (e, st) {
      print('[main] deleteWish failed: $e\n$st');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete wish.'))
      );
      rethrow;
    }
  }

  void _setPanelVisible(bool value) {
    setState(() {
      _panelVisible = value;
    });
    print("setpanelvisible_" + value.toString());
  }

  // ---- user id / anon logic ----

  Future<String?> _getStoredUserId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_kStoredUserIdKey);
    } catch (e) {
      // ignore prefs errors — we'll fall back to asking server
      return null;
    }
  }

  Future<void> _storeUserId(String id) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kStoredUserIdKey, id);
    } catch (e) {
      // ignore failures silently; we'll still keep in memory for this session
    }
  }

  Future<void> _fetchOrCreateAnonUser() async {
    setState(() {
      _fetchingUser = true;
      _userFetchError = null;
    });

    try {
      final stored = await _getStoredUserId();
      if (stored != null && stored.isNotEmpty) {
        setState(() {
          _userId = stored;
        });
        return;
      }

      final anonId = await _apiClient.createAnon();
      await _storeUserId(anonId);
      setState(() {
        _userId = anonId;
      });
    } catch (e) {
      setState(() {
        _userFetchError = e.toString();
        _userId = null;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to get anon user id: ${_userFetchError ?? 'unknown'}',
            ),
          ),
        );
      });
    } finally {
      setState(() {
        _fetchingUser = false;
      });
    }
  }

  // ---- wish / plan logic ----

  Future<void> _onPlanPressed() async {
    final wishText = _controller.text.trim();
    if (wishText.isEmpty) return;
    setState(() {
      _loading = true;
      _wish = null;
    });

    try {
      if (_userId == null) {
        await _fetchOrCreateAnonUser();
        if (_userId == null) throw Exception('No user id available');
      }

      final raw = await AiService.generatePlan(wishText, _userId ?? "");

      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map && decoded.containsKey('owner_id')) {
          final returned = decoded['owner_id'];
          if (returned is String &&
              returned.isNotEmpty &&
              returned != _userId) {
            await _storeUserId(returned);
            setState(() {
              _userId = returned;
            });
          }
        }
      } catch (e) {
        // ignore parse errors — raw may be a plain plan text
      }

      final parsed = WishModel.parsePlanStrict(raw, wishText);
      setState(() {
        _wish = parsed;
        _loading = false;
      });
      (_sidebarKey.currentState as dynamic)?.refresh();
    } catch (e) {
      setState(() {
        _wish = null;
        _loading = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not generate plan.')));
    }
  }

  Future<void> _handleCompleteTask(String wishId, String taskId) async {
    // Fire-and-forget style as before — but show item popup if returned.
    _apiClient.completeTask(wishId, taskId).then((ret) {
      try {
        if (ret == null) return;
        // Expecting ret to be a Map-like object with 'item'
        final dynamic itemDataRaw = ret['item'];
        if (itemDataRaw == null) return;

        // Ensure we have a Map<String, dynamic>
        final Map<String, dynamic> itemData = itemDataRaw is Map
            ? Map<String, dynamic>.from(itemDataRaw as Map)
            : {};

        if (itemData.isNotEmpty && _itemPopupKey.currentState != null) {
          _itemPopupKey.currentState!.show(itemData);
        }

        // Optionally print for debugging
        print('[main] completeTask returned item: $itemData');
      } catch (e, st) {
        print('[main] error handling completeTask response: $e\n$st');
      }
    }).catchError((error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to mark task complete.')));
      }
    });
    // function returns instantly (fire-and-forget)
  }

  Future<void> _handleUncompleteTask(String wishId, String taskId) async {
    try {
      // ask backend to mark the task incomplete (server will clear completed/completed_at)
      await _apiClient.completeTask(wishId, taskId, markIncomplete: true);
      // success -> nothing else to do (keep optimistic UI)
    } catch (e) {
      // bubble error up so WishNodeMap can rollback its optimistic change
      print('[main] _handleUncompleteTask error: $e');
      // Re-throw so the caller (WishNodeMap) catches and handles rollback / snackbar.
      rethrow;
    }
  }

  Future<void> _handleRemoveTask(String wishId, String taskId) async {
    try {
      await _apiClient.deleteTask(wishId, taskId);
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to mark task complete.')));
    }
  }

  Future<void> _handleEditTask(String wishId, String taskId, String newTitle, bool newRepeat) async {
    try {
      await _apiClient.editTask(wishId, taskId, newTitle, newRepeat);
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to mark task complete.')));
    }
  }

  Future<void> _handleAddTask(String wishId, String phaseId, String newTitle, bool newRepeat) async {
    try {
      await _apiClient.addTask(wishId, phaseId, newTitle, newRepeat);
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to mark task complete.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // --- Fullscreen map background ---
          Positioned.fill(
            child: Container(
              color: Color(0xFF2F3138),
              child: (_wish == null)
                  ? Center(
                      child: Text(
                        'Ask for something and see the path appear',
                        style: TextStyle(color: Color(0xFF9AA0A8)),
                      ),
                    )
                  : WishNodeMap(
                      key: ValueKey(_wish!.id),
                      wish: _wish!,
                      userId: _userId ?? '',
                      onCompleteTask: (wishId, taskId) =>
                          _handleCompleteTask(wishId, taskId),
                      onRemoveTask: (wishId, taskId) =>
                          _handleRemoveTask(wishId, taskId),
                      onEditTask: (wishId, taskId, newTitle, newRepeat) =>
                          _handleEditTask(wishId, taskId, newTitle, newRepeat),
                      onAddTask: (wishId, phaseId, newTitle, newRepeat) =>
                          _handleAddTask(wishId, phaseId, newTitle, newRepeat),
                      onUncompleteTask: (wishId, taskId) =>
                          _handleUncompleteTask(wishId, taskId),
                    ),
            ),
          ),

          // --- Sidebar overlay (left) ---
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: 260,
            child: _fetchingUser
                ? Container(
                    color: Color(0xFF2A2A2F),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation(Colors.white),
                            ),
                          ),
                          SizedBox(height: 12),
                          Text(
                            'Connecting...',
                            style: TextStyle(color: Color(0xFFD6D8E1)),
                          ),
                        ],
                      ),
                    ),
                  )
                : (_userId != null
                    ? SidebarDrawer(
                        key: _sidebarKey,
                        userId: _userId!,
                        initiallyOpen: true,
                        onOpenWish: (WishModel parsed) {
                          print("SET WISH:" + parsed.title);
                          setState(() {
                            _wish = parsed;
                          });
                        },
                        onShowWishInput: _showPanel,
                        onHideWishInput: _hidePanel,
                        onDeleteWish: (wishId) => _handleDeleteWish(wishId),
                      )
                    : Container(
                        color: Color(0xFF2A2A2F),
                        padding: EdgeInsets.all(12),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'Sidebar failed to initialize',
                              style: TextStyle(color: Colors.redAccent),
                              textAlign: TextAlign.center,
                            ),
                            SizedBox(height: 8),
                            ElevatedButton(
                              onPressed: _fetchOrCreateAnonUser,
                              child: Text('Retry'),
                            ),
                          ],
                        ),
                      )),
          ),

          // --- Centered control panel (card + inner section) ---
          Positioned(
            left: 260 + 12,
            right: 28,
            top: 28,
            child: Visibility(
              visible: _panelVisible,
              child: Container(
                decoration: BoxDecoration(
                  color: Color(0xFF424452),
                  borderRadius: BorderRadius.circular(18),
                ),
                padding: EdgeInsets.all(18),
                child: GoalInputSection(
                  controller: _controller,
                  focusNode: _focusNode,
                  loading: _loading,
                  onSubmitted: _onPlanPressed,
                  onClose: _hidePanel,
                ),
              ),
            ),
          ),

          // --- Item popup (bottom center) ---
          // NOTE: ItemPopup contains AnimatedPositioned so it must be a direct child of this Stack.
          ItemPopup(key: _itemPopupKey),
        ],
      ),
    );
  }
}

// --- Separated inner content: text + GoalInput, no card container ---
class GoalInputSection extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool loading;
  final Future<void> Function() onSubmitted;
  final VoidCallback? onClose;
  const GoalInputSection({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.loading,
    required this.onSubmitted,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'What do you want to achieve?',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            if (onClose != null)
              IconButton(
                onPressed: onClose,
                icon: Icon(Icons.close, size: 18, color: Color(0xFF9AA0A8)),
                padding: EdgeInsets.zero,
                constraints: BoxConstraints(),
                tooltip: 'Hide',
              ),
          ],
        ),
        SizedBox(height: 12),
        GoalInput(
          controller: controller,
          focusNode: focusNode,
          loading: loading,
          onSubmitted: onSubmitted,
          width: 640,
        ),
      ],
    );
  }
}
