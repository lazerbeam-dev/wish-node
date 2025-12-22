// lib/main.dart
import 'dart:async';
import 'dart:js_interop';
import 'package:flutter/material.dart';
import 'package:http/http.dart';
import 'package:wishnode/ui/pallet.dart';
import 'widgets/wishpath_model.dart';
import 'widgets/goal_input.dart';
import 'widgets/sidebar.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'models/wish_models.dart';
import 'api_singleton.dart' as api_singleton;
// Add import for the API wrapper
import 'wishnode_api.dart';
import 'widgets/stateless_widgets.dart';
// Add import for the popup widget
import 'widgets/item_popup.dart';

const String _kStoredUserIdKey = 'wishnode_anon_user_id';
const String _kStoredTokenKey = 'wishnode_token';

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
    _apiClient = api_singleton.wishnodeApi;
    _fetchOrCreateAnonUser();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

 Widget _buildMobileLayout() {
  return Scaffold(
    backgroundColor: Palette.darkest,
    drawer: Drawer(
      child: SidebarDrawer(
        key: _sidebarKey,
        userId: _userId ?? '',
        initiallyOpen: true,
        onOpenWish: (parsed) {
          setState(() => _wish = parsed);
          Navigator.of(context).pop(); // close drawer
        },
        onShowWishInput: _showPanel,
        onHideWishInput: _hidePanel,
        onDeleteWish: _handleDeleteWish,
      ),
    ),
    body: SafeArea(
      child: Stack(
        children: [
          // --- Background (map or empty state) ---
          Positioned.fill(
            child: (_wish == null)
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.explore_outlined,
                          size: 64,
                          color: Palette.dampTitles.withOpacity(0.5),
                        ),
                        SizedBox(height: 16),
                        Text(
                          'Ask for something\nand see the path appear',
                          style: TextStyle(
                            color: Palette.dampTitles,
                            fontSize: 16,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
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
                    onWishCompleted: () => _handleWishComplete(),
                    onAddTaskCommitted: (task) {
                      setState(() {
                        final phase = _wish?.phases
                            .firstWhere((p) => p.id == task.phaseId);
                        if (phase == null) return;
                        phase.tasks.add(task);
                      });
                    },
                  ),
          ),

          // --- Wish input panel (full screen) ---
          if (_panelVisible)
            Positioned.fill(
              child: Container(
                color: Palette.darkest,
                padding: EdgeInsets.fromLTRB(16, 72, 16, 16),
                child: Column(
                  children: [
                    SizedBox(height: 24),
                    Expanded(
                      child: GoalInputSection(
                        controller: _controller,
                        focusNode: _focusNode,
                        loading: _loading,
                        onSubmitted: _onPlanPressed,
                        onClose: _hidePanel,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // --- Top bar (ALWAYS ON TOP) ---
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Palette.darkest.withOpacity(0.95),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 8,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Builder(
                    builder: (scaffoldContext) => IconButton(
                      icon: Icon(Icons.menu, color: Palette.ourWhite),
                      onPressed: () {
                        Scaffold.of(scaffoldContext).openDrawer();
                      },
                    ),
                  ),
                  if (!_panelVisible)
  Expanded(
    child: Text(
      _wish?.title ?? '',
      style: TextStyle(
        color: Palette.ourWhite,
        fontSize: 16,
        fontWeight: FontWeight.w600,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    ),
  ),

                ],
              ),
            ),
          ),

          // --- Item popup (bottom center) ---
          ItemPopup(key: _itemPopupKey),
        ],
      ),
    ),

    // Floating action button (only when wish input hidden)
    floatingActionButton: !_panelVisible
        ? FloatingActionButton.extended(
            onPressed: _showPanel,
            backgroundColor: Palette.signatureGreen,
            icon: Icon(Icons.add, color: Colors.black),
            label: Text(
              'New Wish',
              style: TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.w600,
              ),
            ),
          )
        : null,
  );
}


  Widget _buildDesktopLayout() {
    return Scaffold(
      body: Stack(
        children: [
          // --- Fullscreen map background ---
          Positioned.fill(
            child: Container(
              color: Palette.darkest,
              child: (_wish == null)
                  ? Center(
                      child: Text(
                        'Ask for something and see the path appear',
                        style: TextStyle(color: Palette.dampTitles),
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
                      onWishCompleted: () => _handleWishComplete(),
                      onAddTaskCommitted: (task) {
                      setState(() {
                        final phase = _wish?.phases.firstWhere((p) => p.id == task.phaseId);
                        if (phase == null) return;
                        phase.tasks.add(task);
                      });
},
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
                    color: Palette.card,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation(Palette.ourWhite),
                            ),
                          ),
                          SizedBox(height: 12),
                          Text(
                            'Connecting...',
                            style: TextStyle(color: Palette.dampTitles),
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
                          //print(parsed.phases.singleWhere((p) => p.tasks.firstWhere((t) => t.repeatedAmount !> 0).repeatedAmount != 0));
                          setState(() {
                            _wish = parsed;
                          });
                        },
                        onShowWishInput: _showPanel,
                        onHideWishInput: _hidePanel,
                        onDeleteWish: (wishId) => _handleDeleteWish(wishId),
                      )
                    : Container(
                        color: Palette.card,
                        padding: EdgeInsets.all(12),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'Sidebar failed to initialize',
                              style: TextStyle(color: Palette.ourWhite),
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
                  color: Palette.card,
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


  void _showPanel() {
    _setPanelVisible(true);
  }

  void _hidePanel() {
    _setPanelVisible(false);
  }

  Future<void> _handleDeleteWish(String wishId) async {
	try {
		await _apiClient.deleteWish(wishId);

		setState(() {
			// 🔑 If the currently open wish was deleted, clear the map
			if (_wish?.id == wishId) {
				_wish = null;
			}
		});

		// Refresh sidebar after successful delete
		(_sidebarKey.currentState as dynamic)?.refresh();
	} catch (e, st) {
		print('[main] deleteWish failed: $e\n$st');
		ScaffoldMessenger.of(context).showSnackBar(
			const SnackBar(content: Text('Failed to delete wish.')),
		);
		rethrow;
	}
}

    Future<void> _clearStoredCredentials() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kStoredUserIdKey);
      await prefs.remove(_kStoredTokenKey);
    } catch (e) {
      // ignore
    }
    _apiClient.setToken('');
    // update in-memory
    setState(() {
      _userId = null;
    });
  }

  void _setPanelVisible(bool value) {
    setState(() {
      _panelVisible = value;
      _loading = false;

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

  Future<String?> _getStoredToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_kStoredTokenKey);
    } catch (e) {
      return null;
    }
  }

  Future<void> _storeToken(String token) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kStoredTokenKey, token);
    } catch (e) {
      // ignore failures
    }
  }

    Future<void> _fetchOrCreateAnonUser() async {
    setState(() {
      _fetchingUser = true;
      _userFetchError = null;
    });

    try {
      final storedToken = await _getStoredToken();
      final storedId = await _getStoredUserId();

      // If we have a token, attempt to validate it regardless of storedId.
      if (storedToken != null && storedToken.isNotEmpty) {
        _apiClient.setToken(storedToken);

        try {
          // Always ask server who this token belongs to
          final who = await _apiClient.whoAmI();
          final uid = who['user_id'];
          if (uid != null && uid is String && uid.isNotEmpty) {
            // valid token: persist canonical id (if different) and use it
            await _storeUserId(uid);
            setState(() => _userId = uid);

            // Make sure sidebar fetches wishes now we have valid auth
            (_sidebarKey.currentState as dynamic)?.refresh();
            return;
          } else {
            // unexpected response — clear stored creds and fallthrough
            print('[main] whoAmI returned no user_id; clearing stored credentials');
            await _clearStoredCredentials();
          }
        } catch (e, st) {
          // whoAmI failed (likely 401). Clear stored creds and continue to createAnon.
          print('[main] whoAmI validation failed: $e\n$st — clearing stored cred');
          await _clearStoredCredentials();
        }
      }

      // No valid token — request a new anon identity from server.
      final createResp = await _apiClient.createAnon();
      final anonId = createResp['anon_user_id']?.toString();
      final token = createResp['token']?.toString();

      if (token == null || token.isEmpty) {
        throw Exception("Server returned no token when creating anon user");
      }
      if (anonId == null || anonId.isEmpty) {
        throw Exception("Server returned no anon_user_id when creating anon user");
      }

      await _storeToken(token);
      await _storeUserId(anonId);
      _apiClient.setToken(token);

      setState(() => _userId = anonId);

      // Ensure sidebar fetches newly-available wishes
      (_sidebarKey.currentState as dynamic)?.refresh();
    } catch (e, st) {
      print('[main] _fetchOrCreateAnonUser error: $e\n$st');
      setState(() {
        _userId = null;
        _userFetchError = e.toString();
      });
    } finally {
      if (mounted) setState(() => _fetchingUser = false);
    }
  }


  // ---- wish / plan logic ----

  Future<void> _onPlanPressed(String? wish_context) async {
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

      final raw = await _apiClient.generatePlan(
        wishText,
        context: wish_context ?? "",
      );

      if(raw == "MAXED_OUT"){
        _showWishLimitModal();
        return;
      }

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
            _controller.clear();
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
      _hidePanel();
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

  void _showWishLimitModal() {
	showDialog(
		context: context,
		barrierDismissible: true,
		builder: (_) => WishLimitModal(
			onDismiss: () => Navigator.of(context).pop(),
			onSubmit: (email) async {
				final trimmed = email.trim();

				final emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
				if (!emailRegex.hasMatch(trimmed)) {
					ScaffoldMessenger.of(context).showSnackBar(
						SnackBar(content: Text('Please enter a valid email address')),
					);
					return;
				}

				try {
					await _apiClient.attachEmail(trimmed);

					Navigator.of(context).pop();

					ScaffoldMessenger.of(context).showSnackBar(
						SnackBar(content: Text('Thanks!')),
					);
				} catch (e) {
					String msg = 'Something went wrong';
					if (e is ApiException && e.message.isNotEmpty) {
						msg = e.message;
					}
					ScaffoldMessenger.of(context).showSnackBar(
						SnackBar(content: Text(msg)),
					);
				}
			},
		),
	).then((_) {
		// 🔑 THIS is the important part
		if (!mounted) return;
		setState(() {
			_loading = false;
		});
	});
}


  Future<void> _handleUncompleteTask(String wishId, String taskId) async {
    try {
      print("UNCOMPLETE HERE");
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

  Future<void> _handleWishComplete() async {
	// Sidebar owns wish categorisation, so just tell it to refresh
  print("WE REFRESH");
	(_sidebarKey.currentState as dynamic)?.refresh();
}

  Future<void> _handleRemoveTask(String wishId, String taskId) async {
	try {
		await _apiClient.deleteTask(wishId, taskId);

		setState(() {
			for (final phase in _wish?.phases ?? []) {
				phase.tasks.removeWhere((t) => t.id == taskId);
			}
		});
	} catch (e) {
		ScaffoldMessenger.of(context).showSnackBar(
			const SnackBar(content: Text('Failed to remove task')),
		);
	}
}


  Future<void> _handleEditTask(
	String wishId,
	String taskId,
	String newTitle,
	bool newRepeat,
) async {
	await _apiClient.editTask(wishId, taskId, newTitle, newRepeat);

	setState(() {
		final phase = _wish?.phases.firstWhere(
			(p) => p.tasks.any((t) => t.id == taskId),
			orElse: () => throw Exception('Phase not found'),
		);
		final task = phase!.tasks.firstWhere((t) => t.id == taskId);
		task.text = newTitle;
		task.repeat = newRepeat;
	});
}


  Future<String> _handleAddTask(
	String wishId,
	String phaseId,
	String newTitle,
	bool newRepeat,
) async {
	final created = await _apiClient.addTask(
		wishId,
		phaseId,
		newTitle,
		newRepeat,
	);
  print("CREATED: " + json.encode(created));
  return created["task"]["id"];
}


  @override
Widget build(BuildContext context) {
  return LayoutBuilder(
    builder: (context, constraints) {
      final isMobile = constraints.maxWidth < 768;

      if (isMobile) {
        return _buildMobileLayout();
      } else {
        return _buildDesktopLayout();
      }
    },
  );
}

}
