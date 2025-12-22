// lib/widgets/sidebar.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:wishnode/main.dart';
import 'package:wishnode/widgets/wishpath_model.dart';
import '../wishnode_api.dart';
import '../models/wish_models.dart';
import '../api_singleton.dart' as api_singleton;
import 'vault.dart';
import '../ui/pallet.dart';
class SidebarDrawer extends StatefulWidget {
  final bool initiallyOpen;
  final String userId; // required: anon or real user id

  // optional callback: if the parent wants the parsed WishModel when a plan is opened,
  // pass a ValueChanged<WishModel>. If omitted, the sidebar will still fetch & parse
  // but won't try to inject it into the parent.
  final ValueChanged<WishModel>? onOpenWish;
  final VoidCallback onShowWishInput;
  final VoidCallback onHideWishInput;
  final Future<void> Function(String wishId) onDeleteWish;
  const SidebarDrawer({
    Key? key,
    this.initiallyOpen = true,
    required this.userId,
    required this.onOpenWish,
    required this.onShowWishInput,
    required this.onHideWishInput,
    required this.onDeleteWish
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

  // public helper for parents to request a refresh
  void refresh() => _fetchWishes();
   @override
  void initState() {
    super.initState();
    _open = widget.initiallyOpen;
    _client = api_singleton.wishnodeApi;

    // Only try to fetch if we have a non-empty userId.
    // This avoids hitting the network during early app startup if main()
    // hasn't provided a stored id yet.
    if (widget.userId.isNotEmpty) {
      _fetchWishes();
    } else {
      print('[SidebarDrawer] initState: userId empty, deferring _fetchWishes');
    }
  }

    @override
  void didUpdateWidget(covariant SidebarDrawer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId) {
      _client = api_singleton.wishnodeApi;
      // Only fetch if new userId is non-empty
      if (widget.userId.isNotEmpty) {
        _fetchWishes();
      } else {
        print('[SidebarDrawer] didUpdateWidget: new userId is empty, skipping _fetchWishes');
        setState(() {
          _wishes = [];
          _error = null;
          _loading = false;
        });
      }
    }
  }

  void _toggle() => setState(() => _open = !_open);

  Future<void> _fetchWishes() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    print('[SidebarDrawer] _fetchWishes: starting for userId=${widget.userId}');
    try {
      final wishes = await _client.listUserWishes(widget.userId);
      print('[SidebarDrawer] _fetchWishes: fetched ${wishes.length} wishes');

      setState(() {
        _wishes = wishes;
      });
    } catch (e, st) {
      print('[SidebarDrawer] _fetchWishes: caught exception -> $e');
      print('[SidebarDrawer] _fetchWishes: stacktrace -> ${st.toString()}');

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
      print('[SidebarDrawer] _fetchWishes: finished (loading=false)');
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
      // fetch the wish DTO from the API wrapper
      final parsedModel = await _client.getWish(wishId);
      print("in here though: " + wishId);

      widget.onHideWishInput();
      // If parent provided a callback, invoke it so main can set _wish
      if (widget.onOpenWish != null) {
        widget.onOpenWish!(parsedModel);
      } else {
        // no callback provided — inform developer via console + snackbar
        print('[SidebarDrawer] onOpenWish not provided. Parsed WishModel ready but not delivered.');
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final scaffold = ScaffoldMessenger.maybeOf(context);
          if (scaffold != null) {
            scaffold.showSnackBar(SnackBar(content: Text('Opened plan "${parsedModel.title}" (no handler attached).')));
          }
        });
      }
    } catch (e, st) {
      print('[SidebarDrawer] _openWishById error: $e\n$st');
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

    // Convert to List<Map<String, dynamic>> expected by Vault()
    
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
      print(l['name']);
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Vault(items: vaultItems),
        fullscreenDialog: true,
      ),
    );
  } catch (e, st) {
    print('[SidebarDrawer] _showVault error: $e\n$st');
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
              
// WITH THIS:
child: LayoutBuilder(
  builder: (context, constraints) {
    return SingleChildScrollView(
      physics: BouncingScrollPhysics(),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 28,
        // Respect system/UI insets to avoid bottom overflow:
        bottom: 28 + MediaQuery.of(context).viewInsets.bottom + MediaQuery.of(context).padding.bottom,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: constraints.maxHeight),
        child: IntrinsicHeight(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // --- keep all the same children you already had ---
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
                      // Show wish input in main content
                      widget.onShowWishInput();

                      // If we're inside a Drawer (mobile), close it
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

              // This pushes content to the top when there is extra space.
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
      // Mobile: close the drawer
      Navigator.of(context).pop();
    } else {
      // Desktop: collapse/expand sidebar
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

        // three-dot menu
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

