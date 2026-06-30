// ============================================================
// FILE: lib/features/dashboard/admins/admin_dashboard.dart
// ============================================================

import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/constants/app_colors.dart';
import '../../auth/services/auth_service.dart';
import '../services/admin_service.dart';
import '../../../routes/app_routes.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard>
    with TickerProviderStateMixin {

  late AnimationController _particleController;
  final AdminService _adminService = AdminService();
  final AuthService _authService = AuthService();

  List<dynamic> _rooms = [];
  bool _isLoading = true;
  bool _isCreating = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _particleController = AnimationController(
      duration: const Duration(seconds: 6),
      vsync: this,
    )..repeat();
    _loadRooms();
  }

  @override
  void dispose() {
    _particleController.dispose();
    super.dispose();
  }

  Future<void> _loadRooms() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      final rooms = await _adminService.getAllRooms();
      setState(() => _rooms = rooms);
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleCreateRoom() async {
    setState(() { _isCreating = true; _error = null; });
    try {
      await _adminService.createRoomAdmin();
      await _loadRooms();
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }

  Future<void> _handleDeleteRoom(String roomCode) async {
    try {
      await _adminService.deleteRoomAdmin(roomCode);
      await _loadRooms();
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _handleLogout() async {
    await _authService.logout();
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, AppRoutes.login);
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
                  child: RefreshIndicator(
                    onRefresh: _loadRooms,
                    color: AppColors.neonPurple,
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Column(
                        children: [
                          const SizedBox(height: 24),
                          _buildStatsRow(),
                          const SizedBox(height: 20),
                          _buildCreateRoomCard(),
                          const SizedBox(height: 20),
                          _buildRoomsList(),
                          const SizedBox(height: 30),
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

  // ── TOP BAR ─────────────────────────────────────────────
  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: AppColors.neonPurple,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.rocket_launch_rounded,
                    color: Colors.white, size: 20),
              ),
              const SizedBox(width: 10),
              const Text('ARENA HUB',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ),
          Row(
            children: [
              GestureDetector(
                onTap: () {
                  Navigator.pushNamed(context, AppRoutes.analytics);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    border: Border.all(
                        color: AppColors.neonCyan.withOpacity(0.5)),
                    borderRadius: BorderRadius.circular(20),
                    color: AppColors.neonCyan.withOpacity(0.08),
                  ),
                  child: Icon(Icons.analytics_rounded,
                      color: AppColors.neonCyan, size: 18),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _handleLogout,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.red.withOpacity(0.5)),
                    borderRadius: BorderRadius.circular(20),
                    color: Colors.red.withOpacity(0.08),
                  ),
                  child: const Icon(Icons.logout_rounded,
                      color: Colors.redAccent, size: 18),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── STATS ROW ────────────────────────────────────────────
  Widget _buildStatsRow() {
    return Row(
      children: [
        Expanded(child: _buildStatCard(
          icon: Icons.meeting_room_rounded,
          label: 'Active Rooms',
          value: '${_rooms.length}',
          color: AppColors.neonPurple,
        )),
        const SizedBox(width: 12),
        Expanded(child: _buildStatCard(
          icon: Icons.people_rounded,
          label: 'Total Players',
          value: _rooms.fold<int>(0, (sum, r) =>
          sum + ((r['players'] as List?)?.length ?? 0)).toString(),
          color: const Color(0xFF00BCD4),
        )),
      ],
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 12),
          Text(value,
            style: TextStyle(
              color: color,
              fontSize: 28,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(label,
            style: TextStyle(
              color: Colors.white.withOpacity(0.5),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  // ── CREATE ROOM ──────────────────────────────────────────
  Widget _buildCreateRoomCard() {
    return GestureDetector(
      onTap: _isCreating ? null : _handleCreateRoom,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [AppColors.neonPurple, const Color(0xFF7B2FE0)],
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: AppColors.neonPurple.withOpacity(0.4),
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _isCreating
                ? const SizedBox(
                width: 22, height: 22,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.add_circle_rounded,
                color: Colors.white, size: 24),
            const SizedBox(width: 12),
            const Text('CREATE NEW ROOM',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 16,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── ROOMS LIST ───────────────────────────────────────────
  Widget _buildRoomsList() {
    if (_error != null) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.red.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.red.withOpacity(0.3)),
        ),
        child: Text(_error!,
          style: const TextStyle(color: Colors.redAccent),
          textAlign: TextAlign.center,
        ),
      );
    }

    if (_isLoading) {
      return Center(
        child: CircularProgressIndicator(color: AppColors.neonPurple),
      );
    }

    if (_rooms.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(40),
        decoration: BoxDecoration(
          color: AppColors.bgCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.neonPurple.withOpacity(0.15)),
        ),
        child: Column(
          children: [
            Icon(Icons.meeting_room_outlined,
                color: Colors.white.withOpacity(0.2), size: 48),
            const SizedBox(height: 12),
            Text('No rooms yet',
              style: TextStyle(
                color: Colors.white.withOpacity(0.4),
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text('Create a room to get started!',
              style: TextStyle(
                color: Colors.white.withOpacity(0.25),
                fontSize: 13,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Active Rooms',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 14),
        ..._rooms.map((room) => _buildRoomCard(room)),
      ],
    );
  }

  Widget _buildRoomCard(Map<String, dynamic> room) {
    final code = room['roomCode'] ?? 'N/A';
    final players = (room['players'] as List?)?.length ?? 0;
    final status = room['status'] ?? 'waiting';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.neonPurple.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: AppColors.neonPurple.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.meeting_room_rounded,
                color: AppColors.neonPurple, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Room: $code',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 4),
                Text('$players players • $status',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.4),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => _handleDeleteRoom(code),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.withOpacity(0.3)),
              ),
              child: const Icon(Icons.delete_rounded,
                  color: Colors.redAccent, size: 18),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Background ───────────────────────────────────────────
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