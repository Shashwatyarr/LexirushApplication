// ============================================================
// FILE: lib/features/leaderboard/screens/global_ranking_screen.dart
// ============================================================

import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import '../../../core/constants/app_colors.dart';

class GlobalRankingScreen extends StatefulWidget {
  final VoidCallback? onBack;
  const GlobalRankingScreen({super.key, this.onBack});

  @override
  State<GlobalRankingScreen> createState() => _GlobalRankingScreenState();
}

class _GlobalRankingScreenState extends State<GlobalRankingScreen>
    with TickerProviderStateMixin {

  late AnimationController _particleCtrl;
  late AnimationController _crownCtrl;

  IO.Socket? _socket;

  bool _isLoading = true;
  List<Map<String, dynamic>> _leaderboard = [];

  String _userName   = 'Operative';
  String _userAvatar = '';
  int    _userLevel  = 1;
  String _role       = 'student';

  @override
  void initState() {
    super.initState();

    _particleCtrl = AnimationController(
      duration: const Duration(seconds: 6), vsync: this,
    )..repeat();

    _crownCtrl = AnimationController(
      duration: const Duration(milliseconds: 800), vsync: this,
    )..repeat(reverse: true);

    _init();
  }

  @override
  void dispose() {
    _socket?.disconnect();
    _socket?.dispose();
    _particleCtrl.dispose();
    _crownCtrl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _userName   = prefs.getString('userName') ?? 'Operative';
      _userAvatar = prefs.getString('avatar')   ?? '';
      _userLevel  = prefs.getInt('userLevel')   ?? 1;
      _role       = prefs.getString('role')     ?? 'student';
    });
    _connectSocket();
  }

  void _connectSocket() {
    _socket = IO.io(
      'https://tambola-67o6.onrender.com',
      IO.OptionBuilder().setTransports(['websocket']).disableAutoConnect().build(),
    );
    _socket!.connect();

    _socket!.onConnect((_) {
      _socket!.emit('requestGlobalLeaderboard', {
        'page': 1, 'limit': 10, 'isAdmin': false,
      });
    });

    _socket!.on('globalLeaderboardData', (data) {
      if (!mounted) return;
      final d = Map<String, dynamic>.from(data as Map);
      final list = (d['leaderboard'] as List?) ?? [];
      setState(() {
        _leaderboard = list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _isLoading = false;
      });
    });

    _socket!.on('error', (msg) {
      if (!mounted) return;
      debugPrint('Leaderboard error: $msg');
      setState(() => _isLoading = false);
    });
  }

  Future<void> _handleLogout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
  }

  String _avatarUrl(Map<String, dynamic> p) {
    final a = p['avatar'] as String?;
    if (a != null && a.isNotEmpty) return a;
    final name = Uri.encodeComponent(p['name'] as String? ?? 'Player');
    return 'https://api.dicebear.com/7.x/avataaars/svg?seed=$name';
  }

  // ============================================================
  // BUILD
  // ============================================================
  @override
  Widget build(BuildContext context) {
    final top3 = _leaderboard.take(3).toList();
    final rest = _leaderboard.length > 3
        ? _leaderboard.sublist(3, math.min(10, _leaderboard.length))
        : <Map<String, dynamic>>[];

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
                    child: Column(
                      children: [
                        _buildHeroBanner(),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                          child: _isLoading
                              ? _buildLoadingState()
                              : _leaderboard.isEmpty
                              ? _buildEmptyState()
                              : Column(
                            children: [
                              const SizedBox(height: 30),
                              _buildPodium(top3),
                              if (rest.isNotEmpty) ...[
                                const SizedBox(height: 28),
                                _buildRestList(rest),
                              ],
                            ],
                          ),
                        ),
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
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 18,
                letterSpacing: 2,
              ),
            ),
          ),
          const Spacer(),

          // Avatar + name chip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.04),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.neonCyan.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Container(
                  width: 22, height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.neonCyan, width: 1.5),
                  ),
                  child: ClipOval(
                    child: _userAvatar.isNotEmpty
                        ? Image.network(_userAvatar, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Icon(
                            Icons.person, size: 14, color: Colors.white60))
                        : const Icon(Icons.person, size: 14, color: Colors.white60),
                  ),
                ),
                const SizedBox(width: 6),
                Text(_userName,
                  style: const TextStyle(
                    color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 8),

          GestureDetector(
            onTap: _handleLogout,
            child: Icon(Icons.logout_rounded,
                color: AppColors.neonRed.withOpacity(0.7), size: 20),
          ),
        ],
      ),
    );
  }

  // ── HERO BANNER ──────────────────────────────────────────
  Widget _buildHeroBanner() {
    return Container(
      width: double.infinity,
      height: 200,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          colors: [
            AppColors.bgCard,
            AppColors.neonCyan.withOpacity(0.08),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Glow
          Container(
            width: 150, height: 150,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.neonCyan.withOpacity(0.1),
            ),
          ),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.neonCyan.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.neonCyan.withOpacity(0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.public_rounded, color: AppColors.neonCyan, size: 12),
                    const SizedBox(width: 5),
                    Text('KIET SERVER',
                      style: TextStyle(
                        color: AppColors.neonCyan,
                        fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              const Text('HALL OF FAME',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 28,
                  fontStyle: FontStyle.italic,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 8),
              Text('The Elite Combatants of the Academy',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.35),
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── LOADING / EMPTY ──────────────────────────────────────
  Widget _buildLoadingState() {
    return Container(
      margin: const EdgeInsets.only(top: 30),
      padding: const EdgeInsets.symmetric(vertical: 50),
      decoration: BoxDecoration(
        color: AppColors.bgCard.withOpacity(0.6),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        children: [
          SizedBox(
            width: 50, height: 50,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              valueColor: AlwaysStoppedAnimation(AppColors.neonCyan),
            ),
          ),
          const SizedBox(height: 18),
          Text('SYNCING DATABASE...',
            style: TextStyle(
              color: AppColors.neonCyan,
              fontWeight: FontWeight.w800,
              fontSize: 11,
              letterSpacing: 2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      margin: const EdgeInsets.only(top: 30),
      padding: const EdgeInsets.symmetric(vertical: 50),
      decoration: BoxDecoration(
        color: AppColors.bgCard.withOpacity(0.6),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        children: [
          Icon(Icons.sentiment_dissatisfied_rounded,
              color: Colors.white.withOpacity(0.2), size: 50),
          const SizedBox(height: 14),
          Text('No operatives found yet.',
            style: TextStyle(
              color: Colors.white.withOpacity(0.3),
              fontWeight: FontWeight.w800,
              fontSize: 11,
              letterSpacing: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  // ── PODIUM (Top 3) ───────────────────────────────────────
  Widget _buildPodium(List<Map<String, dynamic>> top3) {
    final p1 = top3.isNotEmpty ? top3[0] : null;
    final p2 = top3.length > 1 ? top3[1] : null;
    final p3 = top3.length > 2 ? top3[2] : null;

    return Column(
      children: [
        // #1 on top (mobile: stacked vertical, but let's do podium row for >2)
        if (p1 != null) _buildFirstPlace(p1),
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (p2 != null) Expanded(child: _buildSecondThird(p2, 2, Colors.white60, const Color(0xFF1e293b))),
            if (p2 != null && p3 != null) const SizedBox(width: 10),
            if (p3 != null) Expanded(child: _buildSecondThird(p3, 3, const Color(0xFFD97706), const Color(0xFF291404))),
          ],
        ),
      ],
    );
  }

  Widget _buildFirstPlace(Map<String, dynamic> p) {
    return Column(
      children: [
        AnimatedBuilder(
          animation: _crownCtrl,
          builder: (_, child) => Transform.translate(
            offset: Offset(0, -4 * _crownCtrl.value),
            child: child,
          ),
          child: const Text('👑', style: TextStyle(fontSize: 38)),
        ),
        const SizedBox(height: 6),

        // XP badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
          decoration: BoxDecoration(
            color: const Color(0xFFFFC107).withOpacity(0.15),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFFFC107).withOpacity(0.5)),
          ),
          child: Text('${p['xp']} XP',
            style: const TextStyle(
              color: Color(0xFFFFC107),
              fontWeight: FontWeight.w900,
              fontSize: 18,
            ),
          ),
        ),

        const SizedBox(height: 14),

        // Avatar with glow
        Stack(
          alignment: Alignment.bottomCenter,
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 110, height: 110,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFFFC107), width: 4),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFFC107).withOpacity(0.4),
                    blurRadius: 30,
                    spreadRadius: 4,
                  ),
                ],
              ),
              child: ClipOval(
                child: Image.network(_avatarUrl(p), fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                        color: AppColors.bgSurface,
                        child: const Icon(Icons.person, size: 50, color: Colors.white24))),
              ),
            ),
            Positioned(
              bottom: -14,
              child: Container(
                width: 32, height: 32,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFFFC107),
                  border: Border.all(color: AppColors.bgDeep, width: 3),
                ),
                child: const Center(
                  child: Text('1',
                    style: TextStyle(
                      color: Colors.black, fontWeight: FontWeight.w900, fontSize: 15,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 22),

        // Name plate
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [const Color(0xFF422006).withOpacity(0.7), AppColors.bgDeep],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(color: const Color(0xFFFFC107).withOpacity(0.3)),
          ),
          child: Column(
            children: [
              Text((p['name'] as String? ?? '').toUpperCase(),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w900, fontSize: 17, letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFC107).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFFFC107).withOpacity(0.2)),
                ),
                child: Text('LEVEL ${p['level'] ?? 1}',
                  style: const TextStyle(
                    color: Color(0xFFFFC107), fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 1,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSecondThird(Map<String, dynamic> p, int rank, Color accentColor, Color bgColor) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: accentColor.withOpacity(0.12),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: accentColor.withOpacity(0.4)),
          ),
          child: Text('${p['xp']} XP',
            style: TextStyle(color: accentColor, fontWeight: FontWeight.w900, fontSize: 13),
          ),
        ),
        const SizedBox(height: 10),

        Stack(
          alignment: Alignment.bottomCenter,
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 76, height: 76,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: accentColor, width: 3),
                boxShadow: [BoxShadow(color: accentColor.withOpacity(0.3), blurRadius: 16)],
              ),
              child: ClipOval(
                child: Image.network(_avatarUrl(p), fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                        color: AppColors.bgSurface,
                        child: const Icon(Icons.person, size: 34, color: Colors.white24))),
              ),
            ),
            Positioned(
              bottom: -10,
              child: Container(
                width: 24, height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accentColor,
                  border: Border.all(color: AppColors.bgDeep, width: 2.5),
                ),
                child: Center(
                  child: Text('$rank',
                    style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 11),
                  ),
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 16),

        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
          decoration: BoxDecoration(
            color: bgColor.withOpacity(0.5),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
            border: Border.all(color: accentColor.withOpacity(0.25)),
          ),
          child: Column(
            children: [
              Text((p['name'] as String? ?? '').toUpperCase(),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12,
                ),
              ),
              const SizedBox(height: 4),
              Text('LVL ${p['level'] ?? 1}',
                style: TextStyle(
                  color: accentColor.withOpacity(0.8), fontSize: 9, fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── REST LIST (rank 4-10) ────────────────────────────────
  Widget _buildRestList(List<Map<String, dynamic>> rest) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.bgCard.withOpacity(0.8),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.groups_rounded, color: AppColors.neonCyan, size: 16),
              const SizedBox(width: 8),
              Text('ELITE VANGUARD (RANKS 4-10)',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.5),
                  fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          const Divider(color: Colors.white12, height: 24),

          ...rest.asMap().entries.map((entry) {
            final i = entry.key;
            final p = entry.value;
            final rank = i + 4;
            final isMe = (p['name'] as String?) == _userName;

            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isMe
                      ? AppColors.neonCyan.withOpacity(0.08)
                      : Colors.white.withOpacity(0.02),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isMe
                        ? AppColors.neonCyan.withOpacity(0.4)
                        : Colors.white.withOpacity(0.05),
                  ),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 30,
                      child: Text('#$rank',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.3),
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    Container(
                      width: 38, height: 38,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isMe
                              ? AppColors.neonCyan
                              : Colors.white.withOpacity(0.1),
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(9),
                        child: Image.network(_avatarUrl(p), fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                                color: AppColors.bgSurface,
                                child: const Icon(Icons.person, size: 18, color: Colors.white24))),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text((p['name'] as String? ?? '').toUpperCase(),
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12,
                                  ),
                                ),
                              ),
                              if (isMe) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppColors.neonCyan,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text('YOU',
                                    style: TextStyle(
                                      color: Colors.black, fontSize: 8, fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          Text('Level ${p['level'] ?? 1}',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.3),
                              fontSize: 9, fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text('${p['xp']}',
                      style: TextStyle(
                        color: AppColors.neonCyan,
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(width: 2),
                    Text('XP',
                      style: TextStyle(
                        color: AppColors.neonCyan.withOpacity(0.5),
                        fontSize: 9, fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
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
    final rng = math.Random(13);
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
      ..color = AppColors.neonCyan.withOpacity(0.025)
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