// ============================================================
// FILE: lib/features/auth/screens/player_login_screen.dart
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'dart:math' as math;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/constants/app_colors.dart';
import '../services/auth_service.dart';
import '../../dashboard/students/student_dashboard.dart';
import '../../dashboard/admins/admin_dashboard.dart';
import 'admin_login_screen.dart';
import '../../../routes/app_routes.dart';

class PlayerLoginScreen extends StatefulWidget {
  const PlayerLoginScreen({super.key});

  @override
  State<PlayerLoginScreen> createState() => _PlayerLoginScreenState();
}

class _PlayerLoginScreenState extends State<PlayerLoginScreen>
    with TickerProviderStateMixin {

  late AnimationController _pulseController;
  late AnimationController _particleController;
  late Animation<double> _pulseAnimation;

  final AuthService _authService = AuthService();
  // Web Client ID from Google Cloud Console (same as backend GOOGLE_CLIENT_ID)
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    clientId: kIsWeb ? '301462111281-ermh2l8nrth4jm7t96nm17mpfvfp1m4u.apps.googleusercontent.com' : null,
    serverClientId: '301462111281-ermh2l8nrth4jm7t96nm17mpfvfp1m4u.apps.googleusercontent.com',
  );
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);

    _particleController = AnimationController(
      duration: const Duration(seconds: 5),
      vsync: this,
    )..repeat();

    _pulseAnimation = Tween<double>(begin: 0.88, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _particleController.dispose();
    super.dispose();
  }

  // ── GOOGLE LOGIN HANDLER ─────────────────────────────────
  Future<void> _handleGoogleLogin() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final GoogleSignInAccount? account = await _googleSignIn.signIn();
      if (account == null) {
        setState(() => _isLoading = false);
        return;
      }

      final GoogleSignInAuthentication googleAuth =
      await account.authentication;
      final String? idToken = googleAuth.idToken;

      if (idToken == null) {
        setState(() {
          _error = 'Google token nahi mila. Dobara try karo.';
          _isLoading = false;
        });
        return;
      }

      // Backend ko token bhejo
      final data = await _authService.googleLogin(idToken);

      // User info save karo
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('auth_token', data['token'] ?? '');
      await prefs.setString('username', data['user']?['name'] ?? '');
      await prefs.setString('role', data['user']?['role'] ?? 'student');
      await prefs.setString('userId', data['user']?['_id'] ?? '');

      if (!mounted) return;

      // Role ke hisab se navigate karo
      final role = data['user']?['role'] ?? 'student';
      if (role == 'admin' || role == 'superadmin') {
        Navigator.pushReplacementNamed(context, AppRoutes.adminDashboard);
        debugPrint('Admin login success');
      } else {
        Navigator.pushReplacementNamed(context, AppRoutes.studentDashboard);
        debugPrint('Student login success');
      }

    } on PlatformException catch (e, stackTrace) {
      debugPrint('\n--- GOOGLE SIGN-IN PLATFORM EXCEPTION ---');
      debugPrint('Code: ${e.code}');
      debugPrint('Message: ${e.message}');
      debugPrint('Details: ${e.details}');
      debugPrint('ServerClientId: ${_googleSignIn.serverClientId}');
      debugPrint('ClientId: ${_googleSignIn.clientId}');
      debugPrint('Google Email: ${_googleSignIn.currentUser?.email ?? "Not available"}');
      debugPrint('idToken available? ${_googleSignIn.currentUser != null ? "Check token logic" : "No user"}');
      debugPrint('Expected Package Name: com.example.lexirush');
      debugPrint('Stacktrace:\n$stackTrace');
      debugPrint('-----------------------------------------\n');
      setState(() {
        _error = 'Google Sign-In failed (Code: ${e.code}). Please verify your SHA-1 in Google Cloud Console.';
      });
    } catch (e, stackTrace) {
      debugPrint('\n--- GOOGLE SIGN-IN ERROR ---');
      debugPrint('Error: $e');
      debugPrint('Google Email: ${_googleSignIn.currentUser?.email ?? "Not available"}');
      debugPrint('Stacktrace:\n$stackTrace');
      debugPrint('----------------------------\n');
      final msg = e.toString().replaceFirst('Exception: ', '');
      setState(() {
        _error = msg.contains('kiet.edu')
            ? '⚠️ Only @kiet.edu emails allowed!'
            : msg;
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
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
                      children: [
                        const SizedBox(height: 20),
                        _buildHeroCard(),
                        const SizedBox(height: 20),
                        _buildLoginCard(),
                        const SizedBox(height: 24),
                        _buildFooter(),
                        const SizedBox(height: 20),
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
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.neonPurple,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.rocket_launch_rounded,
                    color: Colors.white, size: 20),
              ),
              const SizedBox(width: 10),
              const Text(
                'LEXIRUSH',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ),
          GestureDetector(
            onTap: () {
              Navigator.pushNamed(context, AppRoutes.adminLogin);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                border: Border.all(
                    color: AppColors.neonPurple.withOpacity(0.6)),
                borderRadius: BorderRadius.circular(20),
                color: AppColors.neonPurple.withOpacity(0.1),
              ),
              child: Row(
                children: [
                  Icon(Icons.shield_outlined,
                      color: AppColors.neonPurple, size: 16),
                  const SizedBox(width: 6),
                  Text(
                    'Admin Login',
                    style: TextStyle(
                      color: AppColors.neonPurple,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
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

  // ── HERO CARD ────────────────────────────────────────────
  Widget _buildHeroCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFAB20FD), Color(0xFF7B2FE0)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.neonPurple.withOpacity(0.4),
            blurRadius: 30,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFFFFC107),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              'NEW VERSION LIVE',
              style: TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.w800,
                fontSize: 11,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'UNLEASH\nYOUR\nGENIUS.',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 40,
              height: 1.05,
              letterSpacing: -1,
            ),
          ),
          const SizedBox(height: 24),
          _buildAvatarsRow(),
        ],
      ),
    );
  }

  // ── AVATARS ROW ─────────────────────────────────────────
  Widget _buildAvatarsRow() {
    final List<Color> avatarColors = [
      const Color(0xFFFF6B6B),
      const Color(0xFF4ECDC4),
      const Color(0xFFFFE66D),
    ];
    final List<IconData> avatarIcons = [
      Icons.person,
      Icons.face,
      Icons.face_3,
    ];

    return Row(
      children: [
        SizedBox(
          width: 116,
          height: 38,
          child: Stack(
            children: [
              for (int i = 0; i < 3; i++)
                Positioned(
                  left: i * 26.0,
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: avatarColors[i],
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: const Color(0xFFAB20FD), width: 2),
                    ),
                    child:
                    Icon(avatarIcons[i], color: Colors.white, size: 20),
                  ),
                ),
              Positioned(
                left: 78,
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFC107),
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: const Color(0xFFAB20FD), width: 2),
                  ),
                  child: const Center(
                    child: Text(
                      '+99',
                      style: TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.w800,
                        fontSize: 10,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 14),
        Text(
          'People Loved it',
          style: TextStyle(
            color: Colors.white.withOpacity(0.9),
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
        ),
      ],
    );
  }

  // ── LOGIN CARD ──────────────────────────────────────────
  Widget _buildLoginCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 36),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(20),
        border:
        Border.all(color: AppColors.neonPurple.withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.4),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) => Transform.scale(
              scale: _pulseAnimation.value,
              child: child,
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.neonPurple.withOpacity(0.45),
                        blurRadius: 28,
                        spreadRadius: 6,
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.bgSurface,
                    border: Border.all(
                      color: AppColors.neonPurple.withOpacity(0.6),
                      width: 1.5,
                    ),
                  ),
                  child: Icon(
                    Icons.sports_esports_rounded,
                    color: AppColors.neonPurple,
                    size: 38,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          const Text(
            'Ready to Play?',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 28,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'One click to start your quest for glory.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withOpacity(0.4),
              fontSize: 14,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 32),

          // Error message
          if (_error != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.withOpacity(0.4)),
              ),
              child: Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.redAccent, fontSize: 13),
              ),
            ),
            const SizedBox(height: 16),
          ],

          _buildGoogleButton(),

          const SizedBox(height: 20),
          Text(
            'By logging in, you agree to our Terms and Privacy Policy.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withOpacity(0.22),
              fontSize: 12,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  // ── GOOGLE BUTTON ────────────────────────────────────────
  Widget _buildGoogleButton() {
    return GestureDetector(
      onTap: _isLoading ? null : _handleGoogleLogin,
      child: Container(
        width: double.infinity,
        height: 54,
        decoration: BoxDecoration(
          color: const Color(0xFF1E1B2E),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: Colors.white.withOpacity(0.12),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: _isLoading
            ? Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.neonPurple,
            ),
          ),
        )
            : Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(3),
              ),
              child: const Padding(
                padding: EdgeInsets.all(3),
                child: CustomPaint(painter: _GoogleGPainter()),
              ),
            ),
            const SizedBox(width: 12),
            const Text(
              'Continue with Google',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 15,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── FOOTER ───────────────────────────────────────────────
  Widget _buildFooter() {
    return Column(
      children: [
        Text(
          '© 2026 LEXIRUSH STUDIO',
          style: TextStyle(
            color: Colors.white.withOpacity(0.2),
            fontSize: 11,
            letterSpacing: 1,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'MADE WITH ♡ BY SHASHWAT SRIVASTAVA, SIDDHANT SHUKLA,\nYASH PRADEEP AND SHRAJAL PANDEY\nFOR TRAINING DIVISION, CRPC KIET.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white.withOpacity(0.13),
            fontSize: 10,
            height: 1.6,
            letterSpacing: 0.3,
          ),
        ),
      ],
    );
  }
}

// ── Google G Painter ─────────────────────────────────────
class _GoogleGPainter extends CustomPainter {
  const _GoogleGPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r  = size.width * 0.5;
    final sw = size.width * 0.3;

    final segments = [
      [-90.0, 80.0,  const Color(0xFF4285F4)],
      [ -10.0, 95.0, const Color(0xFF34A853)],
      [  85.0, 95.0, const Color(0xFFFBBC05)],
      [ 180.0, 90.0, const Color(0xFFEA4335)],
    ];

    for (final s in segments) {
      canvas.drawArc(
        Rect.fromCircle(center: Offset(cx, cy), radius: r - sw / 2),
        (s[0] as double) * math.pi / 180,
        (s[1] as double) * math.pi / 180,
        false,
        Paint()
          ..color = s[2] as Color
          ..style = PaintingStyle.stroke
          ..strokeWidth = sw
          ..strokeCap = StrokeCap.butt,
      );
    }

    canvas.drawCircle(Offset(cx, cy), r - sw - 0.5,
        Paint()..color = Colors.white);

    final barTop    = cy - size.height * 0.12;
    final barBottom = cy + size.height * 0.12;
    final barLeft   = cx - size.width * 0.04;
    final barRight  = size.width;
    canvas.drawRect(Rect.fromLTRB(barLeft, barTop, barRight, barBottom),
        Paint()..color = const Color(0xFF4285F4));

    canvas.drawRect(
      Rect.fromLTWH(cx - sw, 0, size.width, cy - size.height * 0.12),
      Paint()..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

// ── Background Particles + Grid ──────────────────────────
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
    if (!size.width.isFinite || !size.height.isFinite || size.width <= 0 || size.height <= 0) return;
    final rng = math.Random(99);
    for (int i = 0; i < 28; i++) {
      final x     = rng.nextDouble() * size.width;
      final baseY = rng.nextDouble() * size.height;
      final speed = 0.4 + rng.nextDouble() * 1.2;
      
      double y = (baseY - t * size.height * speed);
      if (size.height > 0) {
        y = y % size.height;
      }
      if (y.isNaN || y.isInfinite) y = 0.0;
      final safeX = (x.isNaN || x.isInfinite) ? 0.0 : x;
      
      final rad   = 1.0 + rng.nextDouble() * 2.2;
      final safeRad = (rad.isNaN || rad.isInfinite || rad <= 0) ? 1.0 : rad;
      final op    = 0.08 + rng.nextDouble() * 0.22;
      
      canvas.drawCircle(
        Offset(safeX, y),
        safeRad,
        Paint()
          ..color =
          (rng.nextBool() ? AppColors.neonCyan : AppColors.neonPurple)
              .withOpacity(op.clamp(0.0, 1.0)),
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