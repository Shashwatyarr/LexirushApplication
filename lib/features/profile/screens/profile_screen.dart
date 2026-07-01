// ============================================================
// FILE: lib/features/profile/screens/profile_screen.dart
// (Naya folder banana padega: lib/features/profile/screens/)
// ============================================================

import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import '../../../core/constants/app_colors.dart';
import '../../../core/network/api_client.dart';
import '../../game/lexirush/game_screen.dart';
import '../../../routes/app_routes.dart';

class ProfileScreen extends StatefulWidget {
  final VoidCallback? onBack;
  const ProfileScreen({super.key, this.onBack});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with TickerProviderStateMixin {

  late AnimationController _particleCtrl;
  IO.Socket? _socket;

  // ── User state ───────────────────────────────────────────
  bool   _isLoading = true;
  String _userId    = '';
  String _token     = '';
  String _role      = 'student';

  String _name   = 'Challenger';
  String _avatar = '';
  int    _level  = 1;
  int    _xp     = 0;

  String _selectedAvatarImg = '';
  String _selectedAvatarId  = '';
  bool   _isSaving          = false;

  List<Map<String, dynamic>> _availableAvatars = [];

  // ── History state ────────────────────────────────────────
  bool _isHistoryLoading = true;
  List<Map<String, dynamic>> _history = [];
  int? _expandedMatchIndex;

  static const int _xpMax = 10000;

  @override
  void initState() {
    super.initState();
    _particleCtrl = AnimationController(
      duration: const Duration(seconds: 6), vsync: this,
    )..repeat();
    _loadProfile();
  }

  @override
  void dispose() {
    _socket?.disconnect();
    _socket?.dispose();
    _particleCtrl.dispose();
    super.dispose();
  }

  // ── Load user + avatars + history ────────────────────────
  Future<void> _loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    _userId = prefs.getString('userId') ?? '';
    _token  = prefs.getString('token')  ?? '';
    _role   = prefs.getString('role')   ?? 'student';

    String fetchedName   = 'Challenger';
    String savedAvatar   = prefs.getString('userAvatar') ?? '';
    int    level         = 1;
    int    xp            = 0;

    try {
      if (!_userId.startsWith('admin_')) {
        final res = await ApiClient.get('/auth/$_userId');
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          fetchedName = data['name'] ?? data['user']?['name'] ?? fetchedName;
          savedAvatar = data['avatar'] ?? data['user']?['avatar'] ?? savedAvatar;
          level       = (data['level'] ?? data['user']?['level'] ?? level) as int;
          xp          = (data['xp']    ?? data['user']?['xp']    ?? xp)    as int;
          if (savedAvatar.isNotEmpty) {
            await prefs.setString('userAvatar', savedAvatar);
          }
        }
      } else {
        fetchedName = prefs.getString('userName') ?? 'Super Admin';
      }
    } catch (e) {
      debugPrint('Profile fetch error: $e');
    }

    setState(() {
      _name   = fetchedName;
      _avatar = savedAvatar;
      _level  = level;
      _xp     = xp;
      _selectedAvatarImg = savedAvatar;
    });

    // ── Fetch avatars ──
    try {
      final avRes = await ApiClient.get('/user/avatars');
      if (avRes.statusCode == 200) {
        final avData = jsonDecode(avRes.body);
        final list = avData is List ? avData : (avData['avatars'] ?? []);
        final avatars = List<Map<String, dynamic>>.from(
          (list as List).map((e) => Map<String, dynamic>.from(e as Map)),
        );
        setState(() => _availableAvatars = avatars);

        final current = avatars.where((a) => a['image'] == savedAvatar).toList();
        if (current.isNotEmpty) {
          setState(() => _selectedAvatarId = current.first['id'].toString());
        } else if (avatars.isNotEmpty && savedAvatar.isEmpty) {
          setState(() {
            _selectedAvatarImg = avatars.first['image'] as String;
            _selectedAvatarId  = avatars.first['id'].toString();
          });
        }
      }
    } catch (e) {
      debugPrint('Avatar fetch error: $e');
    }

    setState(() => _isLoading = false);

    _fetchHistory();
    _connectSocket();
  }

  Future<void> _fetchHistory() async {
    if (_userId.isEmpty || _userId.startsWith('admin_')) {
      setState(() => _isHistoryLoading = false);
      return;
    }
    try {
      final res = await ApiClient.get('/auth/history/$_userId');
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['success'] == true) {
          setState(() {
            _history = List<Map<String, dynamic>>.from(
              (data['history'] as List).map((e) => Map<String, dynamic>.from(e as Map)),
            );
          });
        }
      } else {
        debugPrint('History Fetch Error: ${res.statusCode} ${res.body}');
      }
    } catch (e) {
      debugPrint('History fetch error: $e');
    } finally {
      setState(() => _isHistoryLoading = false);
    }
  }

  void _connectSocket() {
    _socket = IO.io(
      'https://tambola-67o6.onrender.com',
      IO.OptionBuilder().setTransports(['websocket']).disableAutoConnect().build(),
    );
    _socket!.connect();

    _socket!.on('replayReady', (data) {
      if (!mounted) return;
      final d = Map<String, dynamic>.from(data as Map);

      final roomCode = (d['roomCode'] ?? '').toString();
      final gameData = d['gameData'] is Map
          ? Map<String, dynamic>.from(d['gameData'] as Map)
          : null;

      Navigator.pushReplacementNamed(
        context,
        AppRoutes.game,
        arguments: {
          'roomCode': roomCode,
          'data': gameData,
        },
      );

      debugPrint('Replay ready: $roomCode');
    });
  }

  // ── Actions ──────────────────────────────────────────────
  Future<void> _handleSaveProfile() async {
    setState(() => _isSaving = true);
    bool avatarSuccess = true;

    try {
      if (_selectedAvatarId.isNotEmpty && _selectedAvatarImg != _avatar) {
        final res = await ApiClient.put(
          '/user/avatar',
          body: {'avatarId': _selectedAvatarId},
        );
        if (res.statusCode != 200) avatarSuccess = false;
      }

      if (avatarSuccess) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('userAvatar', _selectedAvatarImg);
        setState(() => _avatar = _selectedAvatarImg);
        _showSnack('Profile Avatar Updated Successfully! 🚀', AppColors.neonGreen);
      } else {
        _showSnack('Failed to update profile.', AppColors.neonRed);
      }
    } catch (e) {
      _showSnack('Server connection failed.', AppColors.neonRed);
    } finally {
      setState(() => _isSaving = false);
    }
  }

  void _handleDiscard() {
    setState(() {
      _selectedAvatarImg = _avatar;
      final current = _availableAvatars.where((a) => a['image'] == _avatar).toList();
      if (current.isNotEmpty) {
        _selectedAvatarId = current.first['id'].toString();
      }
    });
  }

  void _handleReplayMatch(String matchId) {
    _socket?.emit('startReplay', {
      'userId'    : _userId,
      'matchId'   : matchId,
      'userName'  : _name,
      'userAvatar': _selectedAvatarImg,
    });
  }

  Future<void> _handleLogout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
  }

  void _toggleMatch(int index) {
    setState(() {
      _expandedMatchIndex = _expandedMatchIndex == index ? null : index;
    });
  }

  void _showSnack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: color.withOpacity(0.15),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: color.withOpacity(0.5)),
      ),
      behavior: SnackBarBehavior.floating,
      content: Text(msg, style: TextStyle(color: color, fontWeight: FontWeight.w700)),
    ));
  }

  String _formatDate(String? iso) {
    if (iso == null) return '';
    try {
      final dt = DateTime.parse(iso);
      return '${dt.day}/${dt.month}/${dt.year} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }

  // ============================================================
  // BUILD
  // ============================================================
  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: AppColors.bgDeep,
        body: Center(
          child: CircularProgressIndicator(
            color: AppColors.neonPurple, strokeWidth: 3,
          ),
        ),
      );
    }

    final xpPercent = (_xp / _xpMax).clamp(0.0, 1.0);

    return Scaffold(
      backgroundColor: AppColors.bgDeep,
      body: Stack(
        children: [
          _CyberParticles(controller: _particleCtrl),
          const _CyberGrid(),
          SafeArea(
            child: Column(
              children: [
                _buildTopBar(),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    child: Column(
                      children: [
                        _buildProfileCard(xpPercent),
                        const SizedBox(height: 28),
                        _buildHistorySection(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── TOP BAR ──────────────────────────────────────────────
  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          if (Navigator.canPop(context) || widget.onBack != null)
            GestureDetector(
              onTap: () {
                if (Navigator.canPop(context)) {
                  Navigator.pop(context);
                } else if (widget.onBack != null) {
                  widget.onBack!();
                }
              },
              child: Container(
                margin: const EdgeInsets.only(right: 12),
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white.withOpacity(0.2)),
                ),
                child: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 18),
              ),
            ),
          ShaderMask(
            shaderCallback: (b) => const LinearGradient(
              colors: [AppColors.neonCyan, AppColors.neonPurple],
            ).createShader(b),
            child: const Text('LEXIRUSH',
              style: TextStyle(
                color: Colors.white, fontWeight: FontWeight.w900,
                fontSize: 18, letterSpacing: 2,
              ),
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: _handleLogout,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.neonRed.withOpacity(0.4)),
                borderRadius: BorderRadius.circular(20),
                color: AppColors.neonRed.withOpacity(0.08),
              ),
              child: Row(
                children: [
                  Icon(Icons.logout_rounded, color: AppColors.neonRed, size: 14),
                  const SizedBox(width: 5),
                  Text('Log Out',
                    style: TextStyle(
                      color: AppColors.neonRed, fontSize: 11, fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── PROFILE CARD ─────────────────────────────────────────
  Widget _buildProfileCard(double xpPercent) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        children: [
          // Cover banner + avatar overlap
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                height: 110,
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                  gradient: LinearGradient(
                    colors: [
                      AppColors.neonPurple.withOpacity(0.25),
                      AppColors.neonCyan.withOpacity(0.15),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
              ),
              Positioned(
                top: 60, left: 20,
                child: Container(
                  width: 90, height: 90,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.bgCard, width: 5),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.neonPurple.withOpacity(0.4),
                        blurRadius: 20,
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: _selectedAvatarImg.isNotEmpty
                        ? Image.network(_selectedAvatarImg.replaceAll('/svg', '/png'), fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                            color: AppColors.bgSurface,
                            child: const Icon(Icons.person, size: 40, color: Colors.white24)))
                        : Container(
                        color: AppColors.bgSurface,
                        child: const Icon(Icons.person, size: 40, color: Colors.white24)),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 48),

          // Name + level
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_name.toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w900,
                    fontSize: 22, letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.neonCyan.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppColors.neonCyan.withOpacity(0.3)),
                  ),
                  child: Text('LEVEL $_level',
                    style: TextStyle(
                      color: AppColors.neonCyan, fontSize: 10, fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),
          Divider(color: Colors.white.withOpacity(0.06), height: 1),

          // XP bar
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.military_tech_rounded,
                            color: AppColors.neonPurple, size: 14),
                        const SizedBox(width: 6),
                        Text('COMBAT XP',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.4),
                            fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.5,
                          ),
                        ),
                      ],
                    ),
                    Text('$_xp / $_xpMax XP',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.6),
                        fontSize: 11, fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    height: 10,
                    color: AppColors.bgDeep,
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: xpPercent,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [AppColors.neonCyan, AppColors.neonPurple],
                          ),
                          boxShadow: [
                            BoxShadow(color: AppColors.neonPurple.withOpacity(0.5), blurRadius: 10),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          Divider(color: Colors.white.withOpacity(0.06), height: 1),

          // Avatar selector
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.face_rounded, color: AppColors.neonPurple, size: 16),
                    const SizedBox(width: 8),
                    Text('IDENTITY SELECTION',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.5),
                        fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.5,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _availableAvatars.isEmpty
                    ? Text('Decrypting avatars from server...',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.3),
                    fontSize: 11, fontStyle: FontStyle.italic,
                  ),
                )
                    : Wrap(
                  spacing: 12, runSpacing: 12,
                  children: _availableAvatars.map((a) {
                    final isSelected = _selectedAvatarId == a['id'].toString();
                    return GestureDetector(
                      onTap: () => setState(() {
                        _selectedAvatarId  = a['id'].toString();
                        _selectedAvatarImg = a['image'] as String;
                      }),
                      child: Container(
                        width: 60, height: 60,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isSelected
                                ? AppColors.neonPurple
                                : Colors.white.withOpacity(0.1),
                            width: isSelected ? 2 : 1,
                          ),
                          boxShadow: isSelected
                              ? [BoxShadow(
                            color: AppColors.neonPurple.withOpacity(0.4),
                            blurRadius: 14,
                          )]
                              : [],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(13),
                          child: Stack(
                            children: [
                              Opacity(
                                opacity: isSelected ? 1.0 : 0.55,
                                child: Image.network(
                                  (a['image'] as String? ?? '').replaceAll('/svg', '/png'),
                                  width: 60, height: 60, fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Container(
                                      color: AppColors.bgSurface,
                                      child: const Icon(Icons.person, color: Colors.white24)),
                                ),
                              ),
                              if (isSelected)
                                Positioned(
                                  bottom: 2, right: 2,
                                  child: Container(
                                    padding: const EdgeInsets.all(2),
                                    decoration: BoxDecoration(
                                      color: AppColors.neonPurple,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.check,
                                        size: 10, color: Colors.white),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),

          Divider(color: Colors.white.withOpacity(0.06), height: 1),

          // Action buttons
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: _handleDiscard,
                    child: Container(
                      height: 46,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text('Discard',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.4),
                          fontWeight: FontWeight.w700, fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: GestureDetector(
                    onTap: (_isSaving || _selectedAvatarImg == _avatar)
                        ? null
                        : _handleSaveProfile,
                    child: Container(
                      height: 46,
                      decoration: BoxDecoration(
                        gradient: (_isSaving || _selectedAvatarImg == _avatar)
                            ? null
                            : const LinearGradient(
                          colors: [AppColors.neonCyan, AppColors.neonPurple],
                        ),
                        color: (_isSaving || _selectedAvatarImg == _avatar)
                            ? AppColors.bgSurface
                            : null,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: (_isSaving || _selectedAvatarImg == _avatar)
                            ? []
                            : [BoxShadow(
                          color: AppColors.neonPurple.withOpacity(0.4),
                          blurRadius: 14, offset: const Offset(0, 4),
                        )],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (_isSaving)
                            const SizedBox(
                              width: 16, height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          else
                            const Icon(Icons.save_rounded, color: Colors.white, size: 16),
                          const SizedBox(width: 8),
                          Text(
                            _isSaving ? 'Saving...' : 'Confirm Changes',
                            style: TextStyle(
                              color: (_isSaving || _selectedAvatarImg == _avatar)
                                  ? Colors.white38
                                  : Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── HISTORY SECTION ──────────────────────────────────────
  Widget _buildHistorySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.history_rounded, color: AppColors.neonCyan, size: 20),
            const SizedBox(width: 8),
            Text('COMBAT RECORDS',
              style: TextStyle(
                color: AppColors.neonCyan,
                fontWeight: FontWeight.w900,
                fontSize: 16, letterSpacing: 1.5,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        if (_isHistoryLoading)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 40),
            decoration: BoxDecoration(
              color: AppColors.bgCard.withOpacity(0.6),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withOpacity(0.05)),
            ),
            child: Center(
              child: Column(
                children: [
                  CircularProgressIndicator(color: AppColors.neonCyan, strokeWidth: 3),
                  const SizedBox(height: 14),
                  Text('DECRYPTING RECORDS...',
                    style: TextStyle(
                      color: AppColors.neonCyan,
                      fontWeight: FontWeight.w800, fontSize: 11, letterSpacing: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          )
        else if (_history.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 40),
            decoration: BoxDecoration(
              color: AppColors.bgCard.withOpacity(0.6),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withOpacity(0.05)),
            ),
            child: Center(
              child: Column(
                children: [
                  Icon(Icons.videogame_asset_off_rounded,
                      color: Colors.white.withOpacity(0.15), size: 50),
                  const SizedBox(height: 14),
                  Text('No combat history found.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.3),
                      fontWeight: FontWeight.w700, fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text('The Arena awaits.',
                    style: TextStyle(color: AppColors.neonCyan.withOpacity(0.5), fontSize: 11),
                  ),
                ],
              ),
            ),
          )
        else
          ...List.generate(_history.length, (index) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _buildMatchCard(_history[index], index),
            );
          }),
      ],
    );
  }

  Widget _buildMatchCard(Map<String, dynamic> match, int index) {
    final isExpanded = _expandedMatchIndex == index;
    final roomCode = match['roomCode'] as String? ?? '?';
    final playedAt = match['playedAt'] as String?;
    final points   = (match['points'] as num?)?.floor() ?? 0;
    final questions = (match['questions'] as List?) ?? [];

    return Container(
      decoration: BoxDecoration(
        color: AppColors.bgCard.withOpacity(0.8),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        children: [
          // Header
          GestureDetector(
            onTap: () => _toggleMatch(index),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.neonCyan.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: AppColors.neonCyan.withOpacity(0.3)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.public_rounded, color: AppColors.neonCyan, size: 11),
                            const SizedBox(width: 4),
                            Text('Arena: $roomCode',
                              style: TextStyle(
                                color: AppColors.neonCyan, fontSize: 9, fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      Text('+$points',
                        style: TextStyle(
                          color: AppColors.neonCyan, fontWeight: FontWeight.w900, fontSize: 18,
                        ),
                      ),
                      Text(' XP',
                        style: TextStyle(
                          color: AppColors.neonCyan.withOpacity(0.5), fontSize: 10, fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.schedule_rounded, color: Colors.white.withOpacity(0.25), size: 12),
                      const SizedBox(width: 4),
                      Text(_formatDate(playedAt),
                        style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 10),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () => _handleReplayMatch(match['_id'] as String? ?? ''),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              color: AppColors.neonGreen.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: AppColors.neonGreen.withOpacity(0.4)),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.replay_rounded, color: AppColors.neonGreen, size: 13),
                                const SizedBox(width: 5),
                                Text('REPLAY',
                                  style: TextStyle(
                                    color: AppColors.neonGreen, fontSize: 10, fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: isExpanded ? Colors.white.withOpacity(0.08) : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.white.withOpacity(0.1)),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(isExpanded ? 'HIDE INTEL' : 'VIEW INTEL',
                                style: TextStyle(
                                  color: isExpanded ? Colors.white : Colors.white60,
                                  fontSize: 10, fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Icon(
                                isExpanded ? Icons.expand_less : Icons.expand_more,
                                color: isExpanded ? Colors.white : Colors.white60,
                                size: 14,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Expanded question table
          if (isExpanded)
            Container(
              decoration: BoxDecoration(
                color: AppColors.bgDeep.withOpacity(0.4),
                border: Border(top: BorderSide(color: Colors.white.withOpacity(0.06))),
              ),
              child: Column(
                children: questions.asMap().entries.map((entry) {
                  final q = Map<String, dynamic>.from(entry.value as Map);
                  return _buildQuestionRow(q);
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildQuestionRow(Map<String, dynamic> q) {
    final serial    = q['serialNo'] ?? '?';
    final word      = q['word']     as String? ?? '?';
    final type      = q['type']     as String? ?? '?';
    final correct   = q['correctAnswer'] as String? ?? '?';
    final userAns   = q['userAnswer']    as String? ?? 'Not Attempted';
    final isCorrect = q['isCorrect'] == true;
    final notAttempted = userAns == 'Not Attempted';

    final resultColor = isCorrect
        ? AppColors.neonGreen
        : notAttempted
        ? Colors.white38
        : AppColors.neonRed;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.04))),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Text('#$serial',
              style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 10, fontWeight: FontWeight.w700),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(word.toUpperCase(),
              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.neonPurple.withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(type.toUpperCase(),
                style: TextStyle(color: AppColors.neonPurple, fontSize: 8, fontWeight: FontWeight.w800),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            flex: 2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: resultColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: resultColor.withOpacity(0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isCorrect)
                    Icon(Icons.check_circle, color: resultColor, size: 10)
                  else if (!notAttempted)
                    Icon(Icons.cancel, color: resultColor, size: 10),
                  if (isCorrect || !notAttempted) const SizedBox(width: 3),
                  Flexible(
                    child: Text(userAns,
                      style: TextStyle(color: resultColor, fontSize: 9, fontWeight: FontWeight.w800),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// Background Widgets
// ============================================================
class _CyberParticles extends StatelessWidget {
  final AnimationController controller;
  const _CyberParticles({required this.controller});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (_, __) => CustomPaint(
        painter: _ParticlePainter(controller.value),
        size: MediaQuery.of(context).size,
      ),
    );
  }
}

class _ParticlePainter extends CustomPainter {
  final double t;
  _ParticlePainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final rng = math.Random(31);
    for (int i = 0; i < 25; i++) {
      final x     = rng.nextDouble() * size.width;
      final baseY = rng.nextDouble() * size.height;
      final speed = 0.3 + rng.nextDouble() * 1.0;
      final y     = (baseY - t * size.height * speed) % size.height;
      final rad   = 1.0 + rng.nextDouble() * 2.0;
      final op    = 0.06 + rng.nextDouble() * 0.16;
      canvas.drawCircle(
        Offset(x, y), rad,
        Paint()..color = (rng.nextBool() ? AppColors.neonCyan : AppColors.neonPurple)
            .withOpacity(op),
      );
    }
  }

  @override
  bool shouldRepaint(_ParticlePainter o) => o.t != t;
}

class _CyberGrid extends StatelessWidget {
  const _CyberGrid();

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _GridPainter(), size: MediaQuery.of(context).size,
  );
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = AppColors.neonPurple.withOpacity(0.025)
      ..strokeWidth = 1;
    for (double x = 0; x < size.width; x += 38) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    }
    for (double y = 0; y < size.height; y += 38) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter o) => false;
}