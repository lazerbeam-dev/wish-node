// lib/widgets/sidebar.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:wishnode/main.dart';
import 'package:wishnode/utils/log.dart';
import 'package:wishnode/widgets/wishpath_model.dart';
import '../wishnode_api.dart';
import '../models/wish_models.dart';
import '../api_singleton.dart' as api_singleton;
import 'vault.dart';
import '../ui/pallet.dart';

class SidebarDrawer extends StatefulWidget {
  final bool initiallyOpen;
  final String userId;
  final ValueChanged<WishModel>? onOpenWish;
  final VoidCallback onShowWishInput;
  final VoidCallback onHideWishInput;
  final Future<void> Function(String wishId) onDeleteWish;
  final VoidCallback? onLogout; // callback for logout
  final VoidCallback? onShowLogin; // NEW: callback for showing login
  
  const SidebarDrawer({
    Key? key,
    this.initiallyOpen = true,
    required this.userId,
    required this.onOpenWish,
    required this.onShowWishInput,
    required this.onHideWishInput,
    required this.onDeleteWish,
    this.onLogout,
    this.onShowLogin, // NEW
  }) : super(key: key);

  @override
  _SidebarDrawerState createState() => _SidebarDrawerState();
}

class _SidebarDrawerState extends State<SidebarDrawer> {
  late bool _open;
  late WishnodeApi _client;
  List<WishSummary> _wishes = [];
  bool _loading = false;
  String? _error;
  
  // NEW: user profile state
  Map<String, dynamic>? _userProfile;
  bool _loadingProfile = false;

  void refresh() => _fetchWishes();
  
  @override
  void initState() {
    super.initState();
    _open = widget.initiallyOpen;
    _client = api_singleton.wishnodeApi;

    if (widget.userId.isNotEmpty) {
      _fetchWishes();
      _fetchUserProfile(); // NEW
    } else {
      Log.d('[SidebarDrawer] initState: userId empty, deferring _fetchWishes');
    }
  }

  @override
  void didUpdateWidget(covariant SidebarDrawer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId) {
      _client = api_singleton.wishnodeApi;
      if (widget.userId.isNotEmpty) {
        _fetchWishes();
        _fetchUserProfile(); // NEW
      } else {
        Log.d('[SidebarDrawer] didUpdateWidget: new userId is empty, skipping _fetchWishes');
        setState(() {
          _wishes = [];
          _error = null;
          _loading = false;
          _userProfile = null; // NEW
        });
      }
    }
  }

  // NEW: Fetch user profile to check if authenticated
  Future<void> _fetchUserProfile() async {
    setState(() => _loadingProfile = true);
    
    try {
      final profile = await _client.getCurrentUserProfile();
      setState(() {
        _userProfile = profile;
        _loadingProfile = false;
      });
    } catch (e) {
      Log.d('[SidebarDrawer] _fetchUserProfile error: $e');
      setState(() {
        _userProfile = null;
        _loadingProfile = false;
      });
    }
  }

  void _toggle() => setState(() => _open = !_open);

  Future<void> _fetchWishes() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    Log.d('[SidebarDrawer] _fetchWishes: starting for userId=${widget.userId}');
    try {
      final wishes = await _client.listUserWishes(widget.userId);
      Log.d('[SidebarDrawer] _fetchWishes: fetched ${wishes.length} wishes');

      setState(() {
        _wishes = wishes;
      });
    } catch (e, st) {
      Log.d('[SidebarDrawer] _fetchWishes: caught exception -> $e');
      Log.d('[SidebarDrawer] _fetchWishes: stacktrace -> ${st.toString()}');

      setState(() {
        _error = e.toString();
        _wishes = [];
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        final scaffold = ScaffoldMessenger.maybeOf(context);
        if (scaffold != null) {
          scaffold.showSnackBar(SnackBar(content: Text('Error loading goals: ${_error ?? 'unknown'}')));
        }
      });
    } finally {
      setState(() {
        _loading = false;
      });
      Log.d('[SidebarDrawer] _fetchWishes: finished (loading=false)');
    }
  }

  bool _isCompleted(WishSummary w) {
    final s = (w.status ?? '').toLowerCase();
    return s.contains('completed') || s.contains('done');
  }

  Future<void> _openWishById(String wishId, String fallbackTitle) async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final parsedModel = await _client.getWish(wishId);
      Log.d("in here though: " + wishId);

      widget.onHideWishInput();
      if (widget.onOpenWish != null) {
        widget.onOpenWish!(parsedModel);
      } else {
        Log.d('[SidebarDrawer] onOpenWish not provided. Parsed WishModel ready but not delivered.');
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final scaffold = ScaffoldMessenger.maybeOf(context);
          if (scaffold != null) {
            scaffold.showSnackBar(SnackBar(content: Text('Opened plan "${parsedModel.title}" (no handler attached).')));
          }
        });
      }
    } catch (e, st) {
      Log.d('[SidebarDrawer] _openWishById error: $e\n$st');
      setState(() {
        _error = e.toString();
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final scaffold = ScaffoldMessenger.maybeOf(context);
        if (scaffold != null) {
          scaffold.showSnackBar(SnackBar(content: Text('Failed to open plan: ${_error ?? 'unknown'}')));
        }
      });
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _showVault() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final List<ItemOut> itemsOut = await _client.getVault();
      
      final vaultItems = itemsOut.map((it) => {
        'id': it.id,
        'origin_wish_id': it.originWishId,
        'name': it.title,
        'description': it.description,
        'created_at': it.createdAt?.toIso8601String(),
        'legendariness' : it.legendariness,
        'emoji': it.emoji,
        'emoji_accent': it.emojiAccent
      }).toList();

      for (final l in vaultItems){
        Log.d(l['name']);
      }

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => Vault(items: vaultItems),
          fullscreenDialog: true,
        ),
      );
    } catch (e, st) {
      Log.d('[SidebarDrawer] _showVault error: $e\n$st');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final sm = ScaffoldMessenger.maybeOf(context);
        sm?.showSnackBar(SnackBar(content: Text('Failed to load vault: $e')));
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  // NEW: Build account widget
  Widget _buildAccountWidget() {
    if (_loadingProfile) {
      return Container(
        padding: EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Palette.card.withOpacity(0.5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation(Palette.dampTitles),
              ),
            ),
            SizedBox(width: 12),
            Text(
              'Loading...',
              style: TextStyle(color: Palette.dampTitles, fontSize: 12),
            ),
          ],
        ),
      );
    }

    final email = _userProfile?['email']?.toString();
    final isAuthenticated = email != null && email.isNotEmpty;

    if (!isAuthenticated) {
      // Anonymous user - show login button
      return Container(
        padding: EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Palette.card.withOpacity(0.5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.person_outline, color: Palette.dampTitles, size: 18),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Anonymous User',
                    style: TextStyle(
                      color: Palette.dampTitles,
                      fontSize: 13,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () {
                  if (widget.onShowLogin != null) {
                    widget.onShowLogin!();
                  }
                },
                style: TextButton.styleFrom(
                  backgroundColor: Palette.signatureGreen.withOpacity(0.2),
                  padding: EdgeInsets.symmetric(vertical: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Text(
                  'Login',
                  style: TextStyle(
                    color: Palette.signatureGreen,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Authenticated user - show profile and logout
    return Container(
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Palette.card.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: Palette.signatureGreen,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    email[0].toUpperCase(),
                    style: TextStyle(
                      color: Palette.darkest,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
              SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      email,
                      style: TextStyle(
                        color: Palette.ourWhite,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      (_userProfile?['tier']?.toString() ?? 'free').toUpperCase(),
                      style: TextStyle(
                        color: Palette.dampTitles,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () {
                if (widget.onLogout != null) {
                  widget.onLogout!();
                }
              },
              style: TextButton.styleFrom(
                backgroundColor: Palette.darkest.withOpacity(0.3),
                padding: EdgeInsets.symmetric(vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(
                'Logout',
                style: TextStyle(
                  color: Palette.dampTitles,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const fullWidth = 260.0;
    const compactWidth = 56.0;

    final completed = _wishes.where((w) => _isCompleted(w)).toList();
    final inProgress = _wishes.where((w) => !_isCompleted(w)).toList();

    return AnimatedContainer(
      duration: Duration(milliseconds: 240),
      width: _open ? fullWidth : compactWidth,
      decoration: BoxDecoration(
        color: _open ? Palette.darkest : Colors.transparent,
        borderRadius: BorderRadius.only(
          topRight: Radius.circular(18),
          bottomRight: Radius.circular(18),
        ),
      ),
      child: Stack(
        children: [
          Opacity(
            opacity: _open ? 1.0 : 0.0,
            child: IgnorePointer(
              ignoring: !_open,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    physics: BouncingScrollPhysics(),
                    padding: EdgeInsets.only(
                      left: 20,
                      right: 20,
                      top: 28,
                      bottom: 28 + MediaQuery.of(context).viewInsets.bottom + MediaQuery.of(context).padding.bottom,
                    ),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: constraints.maxHeight),
                      child: IntrinsicHeight(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'WISHNODE',
                              style: TextStyle(
                                color: Palette.signatureGreen,
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            SizedBox(height: 18),
                            Text(
                              'CURRENT GOALS',
                              style: TextStyle(color: Palette.dampTitles, fontSize: 12),
                            ),
                            SizedBox(height: 8),

                            if (_loading)
                              Padding(
                                padding: EdgeInsets.symmetric(vertical: 12),
                                child: Row(
                                  children: [
                                    SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    ),
                                    SizedBox(width: 12),
                                    Text('Loading...', style: TextStyle(color:Palette.ourWhite)),
                                  ],
                                ),
                              )
                            else if (_error != null)
                              Padding(
                                padding: EdgeInsets.symmetric(vertical: 8),
                                child: Text('Error loading goals: $_error',
                                    style: TextStyle(color: Palette.ourWhite, fontSize: 13)),
                              )
                            else
                              ConstrainedBox(
                                constraints: BoxConstraints(maxHeight: 220),
                                child: SingleChildScrollView(
                                  child: Column(
                                    children: inProgress.isNotEmpty
                                        ? inProgress
                                            .map((w) => GestureDetector(
                                                  onTap: () => _openWishById(w.id, w.title),
                                                  child: _goalTile(
                                                    icon: Icons.brightness_1,
                                                    label: w.title,
                                                    active: true,
                                                    onTap: () => _openWishById(w.id, w.title),
                                                    onDelete: () => widget.onDeleteWish(w.id),
                                                  ),
                                                ))
                                            .toList()
                                        : [
                                            Padding(
                                              padding: EdgeInsets.symmetric(vertical: 8),
                                              child: Text('No active goals', style: TextStyle(color: Palette.dampTitles)),
                                            )
                                          ],
                                  ),
                                ),
                              ),

                            SizedBox(height: 12),

                            Align(
                              alignment: Alignment.centerLeft,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Palette.brightCta,
                                  borderRadius: BorderRadius.circular(26),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Palette.darkest,
                                      blurRadius: 6,
                                      offset: Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: TextButton(
                                  onPressed: _showVault,
                                  child: Padding(
                                    padding: EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                                    child: Text('VAULT',
                                        style: TextStyle(
                                          color: Palette.darkest,
                                          fontWeight: FontWeight.bold,
                                        )),
                                  ),
                                ),
                              ),
                            ),

                            SizedBox(height: 16),

                            Text('ACHIEVED GOALS', style: TextStyle(color: Palette.dampTitles, fontSize: 12)),
                            SizedBox(height: 8),
                            ConstrainedBox(
                              constraints: BoxConstraints(maxHeight: 160),
                              child: SingleChildScrollView(
                                child: Column(
                                  children: completed.isNotEmpty
                                      ? completed
                                          .map((w) => GestureDetector(
                                                onTap: () => _openWishById(w.id, w.title),
                                                child: _goalTile(
                                                  icon: Icons.brightness_1,
                                                  label: w.title,
                                                  active: true,
                                                  onTap: () => _openWishById(w.id, w.title),
                                                  onDelete: () => widget.onDeleteWish(w.id),
                                                ),
                                              ))
                                          .toList()
                                      : [
                                          Padding(
                                            padding: EdgeInsets.symmetric(vertical: 8),
                                            child: Text('No achieved goals yet', style: TextStyle(color: Palette.dampTitles)),
                                          )
                                        ],
                                ),
                              ),
                            ),

                            SizedBox(height: 18),

                            Align(
                              alignment: Alignment.centerLeft,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Palette.signatureGreen,
                                  borderRadius: BorderRadius.circular(26),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Palette.darkest,
                                      blurRadius: 6,
                                      offset: Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: TextButton(
                                  onPressed: () {
                                    widget.onShowWishInput();

                                    final scaffold = Scaffold.maybeOf(context);
                                    if (scaffold != null && scaffold.hasDrawer) {
                                      Navigator.of(context).pop();
                                    }
                                  },
                                  child: Padding(
                                    padding: EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                                    child: Text('MAKE A WISH',
                                        style: TextStyle(
                                          color: Palette.darkest,
                                          fontWeight: FontWeight.bold,
                                        )),
                                  ),
                                ),
                              ),
                            ),

                            SizedBox(height: 18),

                            // NEW: Account widget
                            _buildAccountWidget(),

                            Expanded(child: SizedBox.shrink()),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),

          // handle
          Positioned(
            right: 0,
            top: 12,
            child: GestureDetector(
              onTap: () {
                final scaffold = Scaffold.maybeOf(context);

                if (scaffold != null && scaffold.hasDrawer) {
                  Navigator.of(context).pop();
                } else {
                  _toggle();
                }
              },
              child: Container(
                width: compactWidth,
                height: 44,
                decoration: BoxDecoration(
                  color: Palette.darkest,
                  borderRadius: BorderRadius.only(
                    topRight: Radius.circular(18),
                    bottomRight: Radius.circular(18),
                    topLeft: Radius.circular(_open ? 12 : 18),
                    bottomLeft: Radius.circular(_open ? 12 : 18),
                  ),
                ),
                child: Center(
                  child: Icon(
                    _open ? Icons.chevron_left : Icons.chevron_right,
                    color: Palette.dampTitles,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Widget _goalTile({
  required IconData icon,
  required String label,
  required bool active,
  required VoidCallback onTap,
  required VoidCallback onDelete,
}) {
  return Padding(
    padding: EdgeInsets.symmetric(vertical: 8),
    child: Row(
      children: [
        GestureDetector(
          onTap: onTap,
          child: Icon(
            icon,
            color: active ? Palette.ourWhite : Palette.dampTitles,
            size: 20,
          ),
        ),
        SizedBox(width: 12),

        Expanded(
          child: GestureDetector(
            onTap: onTap,
            child: Text(
              label,
              style: TextStyle(
                color: active ? Palette.ourWhite: Palette.dampTitles,
                fontSize: 16,
              ),
            ),
          ),
        ),

        PopupMenuButton<int>(
          color: Palette.darkest,
          icon: Icon(Icons.more_vert,
              color: active ? Palette.ourWhite : Palette.dampTitles),
          onSelected: (v) {
            if (v == 0) onDelete();
          },
          itemBuilder: (context) => [
            PopupMenuItem(
              value: 0,
              child: Text('Delete', style: TextStyle(color: Palette.ourWhite)),
            ),
          ],
        ),
      ],
    ),
  );
}