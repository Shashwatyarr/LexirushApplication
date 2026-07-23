// ============================================================
// FILE: lib/features/leaderboard/screens/leaderboard_screen.dart
// ============================================================

import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:confetti/confetti.dart';
import '../../../core/constants/app_colors.dart';
import '../../game/lexirush/game_screen.dart';
import '../../game/spell_shooter/spell_game_screen.dart';
import '../../../routes/app_routes.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/network/api_client.dart';

class LeaderboardScreen extends StatefulWidget {
  final String roomCode;
  final bool isAdmin;
  final List<Map<String, dynamic>> leaderboard;
  final double roomAverage;
  final List<Map<String, dynamic>> questionStats;

  const LeaderboardScreen({
    super.key,
    required this.roomCode,
    required this.isAdmin,
    required this.leaderboard,
    this.roomAverage = 0,
    this.questionStats = const [],
  });

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen>
    with TickerProviderStateMixin {

  late AnimationController _particleCtrl;
  late ConfettiController _confettiLeft;
  late ConfettiController _confettiRight;

  IO.Socket? _socket;

  int  _activeTab             = 0; // 0=rankings 1=analytics
  bool _showTerminatedModal   = false;
  bool _showRematchModal      = false;
  final TextEditingController _timeLimitCtrl = TextEditingController(text: '15');
  String _userId = '';

  @override
  void initState() {
    super.initState();

    _particleCtrl = AnimationController(
      duration: const Duration(seconds: 6), vsync: this,
    )..repeat();

    _confettiLeft = ConfettiController(duration: const Duration(seconds: 3));
    _confettiRight = ConfettiController(duration: const Duration(seconds: 3));

    if (widget.leaderboard.isNotEmpty) {
      _confettiLeft.play();
      _confettiRight.play();
    }

    _connectSocket();
  }

  @override
  void dispose() {
    _socket?.disconnect();
    _socket?.dispose();
    _particleCtrl.dispose();
    _confettiLeft.dispose();
    _confettiRight.dispose();
    _timeLimitCtrl.dispose();
    super.dispose();
  }

  void _connectSocket() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _userId = prefs.getString('userId') ?? '';
    });
    final name = prefs.getString('name') ?? '';

    _socket = IO.io(
      ApiClient.socketUrl,
      IO.OptionBuilder().setTransports(['websocket', 'polling']).enableForceNew().disableAutoConnect().build(),
    );
    _socket!.connect();

    _socket!.onConnect((_) {
      _socket!.emit('joinRoom', {
        'roomCode': widget.roomCode,
        'userId': _userId,
        'name': name,
        'isAdmin': widget.isAdmin,
      });
    });

    _socket!.on('gameStarted', (data) {
      if (!mounted) return;
      final d = Map<String, dynamic>.from(data as Map);

      if (d.containsKey('fullQuestionData')) {
        Navigator.pushReplacementNamed(
          context,
          AppRoutes.spellGame,
          arguments: {
            'roomCode': widget.roomCode,
            'fullQuestionData': d['fullQuestionData'],
            'reconnectData': d,
          },
        );
      } else {
        Navigator.pushReplacementNamed(
          context,
          AppRoutes.game,
          arguments: {
            'roomCode': widget.roomCode,
            'data': d,
          },
        );
      }

      debugPrint('Rematch started: $data');
    });

    _socket!.on('roomClosed', (_) {
      if (!mounted) return;
      setState(() => _showTerminatedModal = true);
    });
  }

  void _handleExit() {
    _socket?.emit('leaveRoom', {'roomCode': widget.roomCode});
    Navigator.pop(context);
  }

  void _confirmTerminationExit() {
    setState(() => _showTerminatedModal = false);
    Navigator.pop(context);
  }

  void _confirmRematch() {
    final timeLimitStr = _timeLimitCtrl.text.trim();
    final newTimeLimit = int.tryParse(timeLimitStr);
    _socket?.emit('initiateRematch', {
      'roomCode'    : widget.roomCode,
      'adminId'     : _userId,
      'newTimeLimit': newTimeLimit,
    });
    setState(() => _showRematchModal = false);
  }

  // ── rank color helper ─────────────────────────────────────
  Color _rankColor(int index) {
    if (index == 0) return const Color(0xFFFFC107);
    if (index == 1) return Colors.white60;
    if (index == 2) return const Color(0xFFCD7F32);
    return Colors.white30;
  }

  Color _accuracyColor(double acc) {
    if (acc >= 80) return AppColors.neonGreen;
    if (acc >= 50) return const Color(0xFFFFC107);
    return AppColors.neonRed;
  }

  // ============================================================
  // BUILD
  // ============================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDeep,
      body: Stack(
        children: [
          // Background glow blobs
          Positioned(
            top: -80, left: -80,
            child: Container(
              width: 300, height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.neonPurple.withOpacity(0.12),
              ),
            ),
          ),
          Positioned(
            bottom: -80, right: -80,
            child: Container(
              width: 300, height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.neonCyan.withOpacity(0.10),
              ),
            ),
          ),

          _CyberParticles(controller: _particleCtrl),
          const _CyberGrid(),

          // Main content
          SafeArea(
            child: Column(
              children: [
                _buildHeader(),
                _buildTabRow(),
                Expanded(
                  child: _activeTab == 0
                      ? _buildRankingsTab()
                      : _buildAnalyticsTab(),
                ),
                _buildBottomActions(),
              ],
            ),
          ),

          // Confetti
          Align(
            alignment: const Alignment(-0.8, -1.0),
            child: ConfettiWidget(
              confettiController: _confettiLeft,
              blastDirection: math.pi / 4,
              maxBlastForce: 20,
              minBlastForce: 10,
              emissionFrequency: 0.05,
              numberOfParticles: 20,
              gravity: 0.2,
              colors: const [Colors.green, Colors.blue, Colors.pink, Colors.orange, Colors.purple],
            ),
          ),
          Align(
            alignment: const Alignment(0.8, -1.0),
            child: ConfettiWidget(
              confettiController: _confettiRight,
              blastDirection: 3 * math.pi / 4,
              maxBlastForce: 20,
              minBlastForce: 10,
              emissionFrequency: 0.05,
              numberOfParticles: 20,
              gravity: 0.2,
              colors: const [Colors.green, Colors.blue, Colors.pink, Colors.orange, Colors.purple],
            ),
          ),

          // Modals
          if (_showTerminatedModal) _buildTerminatedModal(),
          if (_showRematchModal)    _buildRematchModal(),
        ],
      ),
    );
  }

  // ── HEADER ───────────────────────────────────────────────
  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
      child: Column(
        children: [
          // "MATCH CONCLUDED" badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.neonGreen.withOpacity(0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.neonGreen.withOpacity(0.5)),
            ),
            child: Text('MATCH CONCLUDED',
              style: TextStyle(
                color: AppColors.neonGreen,
                fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 2,
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Title
          ShaderMask(
            shaderCallback: (b) => const LinearGradient(
              colors: [Colors.white, Color(0xFF888888)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ).createShader(b),
            child: const Text(
              'POST-MATCH\nREPORT',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 30,
                letterSpacing: 3,
                height: 1.1,
              ),
            ),
          ),

          const SizedBox(height: 10),

          // Room code chip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.04),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white.withOpacity(0.06)),
            ),
            child: Text(
              'Arena: ${widget.roomCode}',
              style: TextStyle(
                color: Colors.white.withOpacity(0.4),
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 2,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── TABS ─────────────────────────────────────────────────
  Widget _buildTabRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        children: [
          Expanded(child: _buildTabBtn(0, 'Squad Rankings',   AppColors.neonPurple)),
          const SizedBox(width: 10),
          Expanded(child: _buildTabBtn(1, 'Match Analytics',  AppColors.neonCyan)),
        ],
      ),
    );
  }

  Widget _buildTabBtn(int idx, String label, Color color) {
    final isActive = _activeTab == idx;
    return GestureDetector(
      onTap: () => setState(() => _activeTab = idx),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isActive ? color : Colors.white.withOpacity(0.04),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isActive ? color : Colors.white.withOpacity(0.08),
          ),
          boxShadow: isActive
              ? [BoxShadow(color: color.withOpacity(0.3), blurRadius: 16, offset: const Offset(0, 4))]
              : [],
        ),
        child: Center(
          child: Text(label,
            style: TextStyle(
              color: isActive ? Colors.white : Colors.white38,
              fontWeight: FontWeight.w800,
              fontSize: 11,
              letterSpacing: 1,
            ),
          ),
        ),
      ),
    );
  }

  // ── RANKINGS TAB ─────────────────────────────────────────
  Widget _buildRankingsTab() {
    if (widget.leaderboard.isEmpty) {
      return Center(
        child: Text('NO DATA AVAILABLE',
          style: TextStyle(
            color: Colors.white.withOpacity(0.2),
            fontWeight: FontWeight.w800,
            letterSpacing: 3,
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      itemCount: widget.leaderboard.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final player = widget.leaderboard[i];
        final isFirst = i == 0;
        return _buildRankCard(player, i, isFirst);
      },
    );
  }

  Widget _buildRankCard(Map<String, dynamic> player, int index, bool isFirst) {
    final rankColor = _rankColor(index);
    final avatarUrl = player['avatar'] as String? ?? '';
    final name      = player['name']   as String? ?? 'Player';
    final points    = player['points'];

    return AnimatedContainer(
      duration: Duration(milliseconds: 300 + index * 80),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: isFirst
            ? LinearGradient(
          colors: [
            const Color(0xFFFFC107).withOpacity(0.15),
            Colors.transparent,
          ],
        )
            : null,
        color: isFirst ? null : AppColors.bgCard.withOpacity(0.8),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isFirst
              ? const Color(0xFFFFC107).withOpacity(0.4)
              : index == 1
              ? Colors.white30
              : index == 2
              ? const Color(0xFFCD7F32).withOpacity(0.4)
              : Colors.white.withOpacity(0.07),
        ),
        boxShadow: isFirst
            ? [BoxShadow(
          color: const Color(0xFFFFC107).withOpacity(0.15),
          blurRadius: 20,
          offset: const Offset(0, 6),
        )]
            : [],
      ),
      child: Row(
        children: [
          // Rank number
          SizedBox(
            width: 42,
            child: Text('#${index + 1}',
              style: TextStyle(
                color: rankColor,
                fontWeight: FontWeight.w900,
                fontSize: 22,
              ),
            ),
          ),

          // Avatar
          Container(
            width: 46, height: 46,
            decoration: BoxDecoration(
              color: AppColors.bgSurface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isFirst
                    ? const Color(0xFFFFC107).withOpacity(0.5)
                    : Colors.white.withOpacity(0.1),
              ),
            ),
            child: avatarUrl.isNotEmpty
                ? ClipRRect(
              borderRadius: BorderRadius.circular(9),
              child: Image.network(avatarUrl, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Icon(
                      Icons.person_rounded, color: Colors.white30)),
            )
                : const Icon(Icons.person_rounded, color: Colors.white30),
          ),

          const SizedBox(width: 12),

          // Name
          Expanded(
            child: Text(name.toUpperCase(),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 14,
                letterSpacing: 0.5,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),

          // XP
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$points',
                style: TextStyle(
                  color: isFirst ? const Color(0xFFFFC107) : AppColors.neonPurple,
                  fontWeight: FontWeight.w900,
                  fontSize: 20,
                ),
              ),
              Text('XP',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.3),
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── ANALYTICS TAB ────────────────────────────────────────
  Widget _buildAnalyticsTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      children: [
        // Average XP card
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [AppColors.bgCard, AppColors.bgSurface],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.neonCyan.withOpacity(0.2)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('SQUAD PERFORMANCE',
                      style: TextStyle(
                        color: AppColors.neonCyan,
                        fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text('Average XP earned across all operatives',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.35),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.neonCyan.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.neonCyan.withOpacity(0.3)),
                ),
                child: Column(
                  children: [
                    Text(widget.roomAverage.toStringAsFixed(1),
                      style: TextStyle(
                        color: AppColors.neonCyan,
                        fontWeight: FontWeight.w900,
                        fontSize: 32,
                      ),
                    ),
                    Text('AVG XP',
                      style: TextStyle(
                        color: AppColors.neonCyan.withOpacity(0.5),
                        fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Question stats header
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            children: [
              Icon(Icons.radar_rounded, color: AppColors.neonPurple, size: 18),
              const SizedBox(width: 8),
              Text('TARGET ACCURACY BREAKDOWN',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.6),
                  fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.5,
                ),
              ),
            ],
          ),
        ),

        if (widget.questionStats.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 30),
              child: Text('NO QUESTION DATA',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.2),
                  fontWeight: FontWeight.w700, letterSpacing: 2,
                ),
              ),
            ),
          )
        else
          ...widget.questionStats.asMap().entries.map((entry) {
            final i = entry.key;
            final q = entry.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _buildQuestionStatCard(q, i),
            );
          }),
      ],
    );
  }

  Widget _buildQuestionStatCard(Map<String, dynamic> q, int i) {
    final accuracy      = (q['accuracy'] as num?)?.toDouble() ?? 0;
    final word          = q['word']          as String? ?? '?';
    final type          = q['type']          as String? ?? '?';
    final serial        = q['serialNo']      ?? i + 1;
    final correctAnswer = q['correctAnswer'] as String? ?? '?';
    final correctCount  = q['correctCount']  ?? 0;
    final color         = _accuracyColor(accuracy);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top row
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black38,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text('Q$serial',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.4),
                    fontSize: 10, fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(word.toUpperCase(),
                style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: (type == 'synonym'
                      ? AppColors.neonCyan
                      : AppColors.neonPurple).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(type.toUpperCase(),
                  style: TextStyle(
                    color: type == 'synonym' ? AppColors.neonCyan : AppColors.neonPurple,
                    fontSize: 8, fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const Spacer(),
              Text('${accuracy.toStringAsFixed(0)}%',
                style: TextStyle(
                  color: color, fontWeight: FontWeight.w900, fontSize: 20,
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // Accuracy bar
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Container(
              height: 8,
              width: double.infinity,
              color: Colors.white.withOpacity(0.06),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: accuracy / 100,
                child: Container(
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(4),
                    boxShadow: [
                      BoxShadow(color: color.withOpacity(0.4), blurRadius: 6),
                    ],
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(height: 10),

          // Footer stats
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.white.withOpacity(0.05)),
                ),
                child: Text('Answer: $correctAnswer',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.6),
                    fontSize: 10, fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                'Correct: $correctCount / ${widget.leaderboard.length}',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.3),
                  fontSize: 10, fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── BOTTOM ACTIONS ───────────────────────────────────────
  Widget _buildBottomActions() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        border: Border(top: BorderSide(color: Colors.white.withOpacity(0.06))),
      ),
      child: Row(
        children: [
          // Return to HQ
          Expanded(
            child: GestureDetector(
              onTap: _handleExit,
              child: Container(
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withOpacity(0.08)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.logout_rounded,
                        color: Colors.white.withOpacity(0.4), size: 18),
                    const SizedBox(width: 8),
                    Text('Return to HQ',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.4),
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Rematch (admin only)
          if (widget.isAdmin) ...[
            const SizedBox(width: 10),
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _showRematchModal = true),
                child: Container(
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF10B981), Color(0xFF0D9488)],
                    ),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF10B981).withOpacity(0.3),
                        blurRadius: 14,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.replay_rounded,
                          color: Colors.white, size: 18),
                      const SizedBox(width: 8),
                      const Text('Rematch',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── TERMINATED MODAL ─────────────────────────────────────
  Widget _buildTerminatedModal() {
    return Container(
      color: Colors.black.withOpacity(0.8),
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 28),
          decoration: BoxDecoration(
            color: const Color(0xFF0B101E),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.neonRed.withOpacity(0.3)),
            boxShadow: [
              BoxShadow(
                color: AppColors.neonRed.withOpacity(0.1),
                blurRadius: 40,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Title
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: const Color(0xFF02040A),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                  border: Border(
                    bottom: BorderSide(color: Colors.white.withOpacity(0.06)),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning_rounded, color: AppColors.neonRed, size: 20),
                    const SizedBox(width: 10),
                    Text('ARENA TERMINATED',
                      style: TextStyle(
                        color: AppColors.neonRed,
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              ),

              // Body
              Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  'The Administrator has officially terminated this Arena session. Further gameplay in this room is disabled.',
                  style: TextStyle(color: Colors.white.withOpacity(0.6), height: 1.5),
                ),
              ),

              // Action
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF02040A),
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
                  border: Border(
                    top: BorderSide(color: Colors.white.withOpacity(0.06)),
                  ),
                ),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: GestureDetector(
                    onTap: _confirmTerminationExit,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppColors.neonRed.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.neonRed.withOpacity(0.4)),
                      ),
                      child: Text('Acknowledge & Exit',
                        style: TextStyle(
                          color: AppColors.neonRed,
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── REMATCH MODAL ────────────────────────────────────────
  Widget _buildRematchModal() {
    return Container(
      color: Colors.black.withOpacity(0.8),
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 28),
          decoration: BoxDecoration(
            color: const Color(0xFF0B101E),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.1)),
            boxShadow: [
              BoxShadow(
                color: AppColors.neonGreen.withOpacity(0.1),
                blurRadius: 40,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Title
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: const Color(0xFF02040A),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                  border: Border(
                    bottom: BorderSide(color: Colors.white.withOpacity(0.06)),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.replay_rounded, color: AppColors.neonGreen, size: 20),
                        const SizedBox(width: 10),
                        Text('CONFIGURE REMATCH',
                          style: TextStyle(
                            color: AppColors.neonGreen,
                            fontWeight: FontWeight.w900,
                            fontSize: 15,
                            letterSpacing: 1,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'All active operatives will be pulled into a new session instantly.',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.3),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),

              // Body
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('TIME LIMIT PER TARGET (SECONDS)',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.35),
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF060913),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: Colors.white.withOpacity(0.1)),
                      ),
                      child: TextField(
                        controller: _timeLimitCtrl,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w700,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Default: 15s',
                          hintStyle: TextStyle(color: Colors.white.withOpacity(0.25)),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text('Leave empty to retain previous match settings.',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.2),
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),

              // Actions
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF02040A),
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
                  border: Border(
                    top: BorderSide(color: Colors.white.withOpacity(0.06)),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    GestureDetector(
                      onTap: () => setState(() => _showRematchModal = false),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        child: Text('Cancel',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.35),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: _confirmRematch,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                        decoration: BoxDecoration(
                          color: AppColors.neonGreen.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.neonGreen.withOpacity(0.4)),
                        ),
                        child: Text('Launch Rematch',
                          style: TextStyle(
                            color: AppColors.neonGreen,
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
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
    if (size.width == 0 || size.height == 0) return;
    final rng = math.Random(77);
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
      ..color = AppColors.neonPurple.withOpacity(0.03)
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