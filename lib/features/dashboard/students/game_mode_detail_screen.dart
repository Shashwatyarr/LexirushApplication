import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../../../core/constants/app_colors.dart';
import '../../game/services/room_service.dart';
import '../../game/lexirush/lobby_screen.dart';
import '../../game/spell_shooter/spell_lobby_screen.dart';

class GameModeDetailScreen extends StatefulWidget {
  final String gameMode;
  final String title;
  final String description;

  const GameModeDetailScreen({
    super.key,
    required this.gameMode,
    required this.title,
    required this.description,
  });

  @override
  State<GameModeDetailScreen> createState() => _GameModeDetailScreenState();
}

class _GameModeDetailScreenState extends State<GameModeDetailScreen> with TickerProviderStateMixin {
  late AnimationController _particleController;
  final RoomService _roomService = RoomService();
  final TextEditingController _roomCodeController = TextEditingController();

  bool _isJoining = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _particleController = AnimationController(
      duration: const Duration(seconds: 6),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _particleController.dispose();
    _roomCodeController.dispose();
    super.dispose();
  }

  Future<void> _handleJoinRoom() async {
    final code = _roomCodeController.text.trim();
    if (code.isEmpty) {
      setState(() => _error = 'Room code daalo!');
      return;
    }
    setState(() { _isJoining = true; _error = null; });
    try {
      final data = await _roomService.joinRoom(code);
      if (!mounted) return;
      debugPrint('Joined: $data');

      final roomData = data['room'];
      final joinedGameMode = (data['gameMode'] ??
          (roomData is Map ? roomData['gameMode'] : null) ??
          widget.gameMode).toString().toLowerCase();

      if (joinedGameMode == 'spell_shooter' || joinedGameMode == 'spellshooter') {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => SpellLobbyScreen(roomCode: code, isAdmin: false),
          ),
        );
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => LobbyScreen(roomCode: code, isAdmin: false),
          ),
        );
      }
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isJoining = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDeep,
      body: Stack(
        children: [
          _CyberParticles(controller: _particleController),
          const _CyberGrid(),
          SafeArea(
            child: Column(
              children: [
                _buildTopBar(),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const SizedBox(height: 32),
                        _buildHeader(),
                        const SizedBox(height: 40),
                        _buildJoinRoomCard(),
                        const SizedBox(height: 30),
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

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withOpacity(0.2)),
              ),
              child: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 20),
            ),
          ),
          const SizedBox(width: 16),
          Text(widget.title.toUpperCase(),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 18,
              letterSpacing: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        Container(
          width: 80, height: 80,
          decoration: BoxDecoration(
            color: widget.gameMode == 'spell_shooter' ? const Color(0xFF00BCD4).withOpacity(0.2) : AppColors.neonPurple.withOpacity(0.2),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: widget.gameMode == 'spell_shooter' ? const Color(0xFF00BCD4) : AppColors.neonPurple),
          ),
          child: Icon(
            widget.gameMode == 'spell_shooter' ? Icons.sports_esports_rounded : Icons.flash_on_rounded,
            color: widget.gameMode == 'spell_shooter' ? const Color(0xFF00BCD4) : AppColors.neonPurple,
            size: 40,
          ),
        ),
        const SizedBox(height: 20),
        Text(widget.title,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 28,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 8),
        Text(widget.description,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white.withOpacity(0.6),
            fontSize: 14,
          ),
        ),
      ],
    );
  }

  Widget _buildJoinRoomCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.neonPurple.withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.4),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.meeting_room_rounded,
                  color: AppColors.neonPurple, size: 22),
              const SizedBox(width: 10),
              const Text('Join Match',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Error
          if (_error != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.withOpacity(0.4)),
              ),
              child: Text(_error!,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
            ),
            const SizedBox(height: 12),
          ],

          // Room code input
          Container(
            decoration: BoxDecoration(
              color: AppColors.bgSurface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.neonPurple.withOpacity(0.3)),
            ),
            child: TextField(
              controller: _roomCodeController,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                letterSpacing: 3,
                fontSize: 18,
              ),
              textAlign: TextAlign.center,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                hintText: 'ENTER ROOM CODE',
                hintStyle: TextStyle(
                  color: Colors.white.withOpacity(0.25),
                  letterSpacing: 2,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 16),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Join button
          GestureDetector(
            onTap: _isJoining ? null : _handleJoinRoom,
            child: Container(
              width: double.infinity,
              height: 52,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.neonPurple, Color(0xFF7B2FE0)],
                ),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.neonPurple.withOpacity(0.4),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Center(
                child: _isJoining
                    ? const SizedBox(
                  width: 22, height: 22,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
                    : const Text('JOIN MATCH',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                    letterSpacing: 1.5,
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
    final rng = math.Random(99);
    for (int i = 0; i < 28; i++) {
      final x = rng.nextDouble() * size.width;
      final baseY = rng.nextDouble() * size.height;
      final speed = 0.4 + rng.nextDouble() * 1.2;
      final y = (baseY - t * size.height * speed) % size.height;
      final rad = 1.0 + rng.nextDouble() * 2.2;
      final op = 0.08 + rng.nextDouble() * 0.22;
      canvas.drawCircle(Offset(x, y), rad,
          Paint()..color = (rng.nextBool()
              ? AppColors.neonCyan : AppColors.neonPurple).withOpacity(op));
    }
  }

  @override
  bool shouldRepaint(_ParticlePainter o) => o.t != t;
}

class _CyberGrid extends StatelessWidget {
  const _CyberGrid();

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _GridPainter(),
    size: MediaQuery.of(context).size,
  );
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = AppColors.neonPurple.withOpacity(0.035)
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
