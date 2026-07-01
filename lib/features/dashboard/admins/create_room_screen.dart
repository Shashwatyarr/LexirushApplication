import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/constants/app_colors.dart';
import '../../../routes/app_routes.dart';

class CreateRoomScreen extends StatefulWidget {
  const CreateRoomScreen({super.key});

  @override
  State<CreateRoomScreen> createState() => _CreateRoomScreenState();
}

class _CreateRoomScreenState extends State<CreateRoomScreen>
    with TickerProviderStateMixin {

  late AnimationController _particleCtrl;
  static const String _baseUrl = 'https://tambola-67o6.onrender.com';

  // ── Game mode ────────────────────────────────────────────
  String _gameMode     = 'lexirush'; // 'lexirush' | 'spell_shooter'
  bool   _isCustomRoom = false;

  // ── Settings ─────────────────────────────────────────────
  int    _timeLimit   = 15;
  String _level       = '1';
  int    _easyQ       = 8;
  int    _mediumQ     = 9;
  int    _hardQ       = 8;

  // ── Room code ────────────────────────────────────────────
  String _roomCode      = '';
  bool   _isGenerating  = false;
  String _splitError    = '';

  String _token = '';

  bool get _isLexi => _gameMode == 'lexirush';

  // ── Theme helpers ─────────────────────────────────────────
  Color get _accentColor => _isLexi ? AppColors.neonPurple : const Color(0xFFF59E0B);
  Color get _accentColorAlt => _isLexi ? const Color(0xFFD946EF) : const Color(0xFFF97316);
  LinearGradient get _modeGradient => _isLexi
      ? const LinearGradient(colors: [Color(0xFFD946EF), Color(0xFF7B2FE0)])
      : const LinearGradient(colors: [Color(0xFFF59E0B), Color(0xFFF97316)]);

  int get _total => _easyQ + _mediumQ + _hardQ;

  @override
  void initState() {
    super.initState();
    _particleCtrl = AnimationController(
      duration: const Duration(seconds: 6), vsync: this,
    )..repeat();
    _loadToken();
  }

  @override
  void dispose() {
    _particleCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadToken() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _token = prefs.getString('token') ?? '');
  }

  void _validate() {
    setState(() {
      if (!_isCustomRoom && _total != 25) {
        _splitError = 'Total must be exactly 25. (Current: $_total)';
      } else {
        _splitError = '';
      }
    });
  }

  // ── Generate Room ─────────────────────────────────────────
  Future<void> _handleGenerateRoom() async {
    if (_token.isEmpty) return;
    if (!_isCustomRoom && _total != 25) {
      _showSnack('Total questions must be exactly 25.', AppColors.neonRed);
      return;
    }

    setState(() => _isGenerating = true);

    try {
      final payload = {
        'level'               : _isCustomRoom ? 1 : int.parse(_level),
        'timeLimitPerQuestion': _timeLimit,
        'maxPlayers'          : 99,
        'easyCount'           : _isCustomRoom ? 0 : _easyQ,
        'medCount'            : _isCustomRoom ? 0 : _mediumQ,
        'difCount'            : _isCustomRoom ? 0 : _hardQ,
        'isCustom'            : _isCustomRoom,
        'customWords'         : null,
        'gameMode'            : _gameMode,
      };

      final res = await http.post(
        Uri.parse('$_baseUrl/api/admin/create-room'),
        headers: {
          'Content-Type' : 'application/json',
          'Authorization': 'Bearer $_token',
        },
        body: jsonEncode(payload),
      );

      final data = jsonDecode(res.body);
      if (data['success'] == true) {
        setState(() => _roomCode = data['roomCode'] as String);
      } else {
        _showSnack(data['message'] as String? ?? 'Failed to create room.', AppColors.neonRed);
      }
    } catch (e) {
      _showSnack('Connection failed.', AppColors.neonRed);
    } finally {
      setState(() => _isGenerating = false);
    }
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

  // ============================================================
  // BUILD
  // ============================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDeep,
      body: Stack(
        children: [
          _CyberParticles(controller: _particleCtrl),
          const _CyberGrid(),
          SafeArea(
            child: Column(
              children: [
                _buildHeader(),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    child: Column(
                      children: [
                        _buildPageTitle(),
                        const SizedBox(height: 20),
                        _buildRoomSettingsCard(),
                        const SizedBox(height: 16),
                        _buildArenaAccessCard(),
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

  // ── HEADER ───────────────────────────────────────────────
  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.arrow_back_rounded, color: Colors.white70, size: 18),
            ),
          ),
          const SizedBox(width: 12),
          ShaderMask(
            shaderCallback: (b) => const LinearGradient(
              colors: [Color(0xFFA78BFA), Color(0xFFEC4899)],
            ).createShader(b),
            child: const Text('LEXIRUSH ADMIN',
              style: TextStyle(
                color: Colors.white, fontWeight: FontWeight.w900,
                fontSize: 16, letterSpacing: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── PAGE TITLE ───────────────────────────────────────────
  Widget _buildPageTitle() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.stars_rounded, color: const Color(0xFFFBBF24), size: 22),
            const SizedBox(width: 10),
            Text('CONFIGURE ARENA',
              style: TextStyle(
                color: _accentColorAlt,
                fontWeight: FontWeight.w900,
                fontSize: 22,
                fontStyle: FontStyle.italic,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(left: 32, top: 4),
          child: Text('SET THE RULES OF ENGAGEMENT.',
            style: TextStyle(
              color: Colors.white.withOpacity(0.3),
              fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 2,
            ),
          ),
        ),
      ],
    );
  }

  // ── ROOM SETTINGS CARD ───────────────────────────────────
  Widget _buildRoomSettingsCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section header
          Row(
            children: [
              Icon(Icons.tune_rounded, color: _accentColor, size: 18),
              const SizedBox(width: 8),
              const Text('ROOM SETTINGS',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15, letterSpacing: 1),
              ),
            ],
          ),

          const SizedBox(height: 18),

          // Game mode selector
          _buildGameModeSelector(),

          const SizedBox(height: 12),

          // Standard / Custom toggle
          _buildToggleRow(
            leftLabel: 'STANDARD DB',
            rightLabel: 'CUSTOM UPLOAD',
            rightIcon: Icons.table_view_rounded,
            isLeft: !_isCustomRoom,
            leftGradient: _modeGradient,
            rightGradient: const LinearGradient(colors: [Color(0xFF10B981), Color(0xFF0D9488)]),
            onLeft: () => setState(() => _isCustomRoom = false),
            onRight: () => setState(() => _isCustomRoom = true),
          ),

          const SizedBox(height: 20),

          // Time limit stepper
          Text('TIME LIMIT PER QUESTION',
            style: TextStyle(color: Colors.white.withOpacity(0.35),
                fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.5),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: 160,
            child: _StepperCard(
              title: 'SECONDS',
              value: _timeLimit,
              color: _isLexi ? AppColors.neonPurple : const Color(0xFFF59E0B),
              unit: 'SEC',
              min: 10, max: 60, step: 5,
              onChanged: (v) => setState(() => _timeLimit = v),
            ),
          ),

          const SizedBox(height: 20),

          if (!_isCustomRoom) ...[
            // Difficulty level
            Text('DIFFICULTY LEVEL',
              style: TextStyle(color: Colors.white.withOpacity(0.35),
                  fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.5),
            ),
            const SizedBox(height: 10),
            _buildLevelDropdown(),

            const SizedBox(height: 20),

            // Question distribution
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('QUESTION DISTRIBUTION',
                  style: TextStyle(color: Colors.white.withOpacity(0.35),
                      fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.5),
                ),
                Text('Total: $_total / 25',
                  style: TextStyle(
                    color: _total == 25 ? AppColors.neonGreen : AppColors.neonRed,
                    fontSize: 11, fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: _StepperCard(
                  title: 'EASY', value: _easyQ,
                  color: AppColors.neonGreen,
                  onChanged: (v) { setState(() => _easyQ = v); _validate(); },
                )),
                const SizedBox(width: 8),
                Expanded(child: _StepperCard(
                  title: 'MEDIUM', value: _mediumQ,
                  color: const Color(0xFFFBBF24),
                  onChanged: (v) { setState(() => _mediumQ = v); _validate(); },
                )),
                const SizedBox(width: 8),
                Expanded(child: _StepperCard(
                  title: 'HARD', value: _hardQ,
                  color: AppColors.neonRed,
                  onChanged: (v) { setState(() => _hardQ = v); _validate(); },
                )),
              ],
            ),
            if (_splitError.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.neonRed.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.neonRed.withOpacity(0.4)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning_rounded, color: AppColors.neonRed, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(_splitError,
                        style: TextStyle(color: AppColors.neonRed,
                            fontSize: 11, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ] else ...[
            // Custom upload section
            _buildCustomUploadSection(),
          ],
        ],
      ),
    );
  }

  Widget _buildGameModeSelector() {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _gameMode = 'lexirush'),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  gradient: _isLexi ? const LinearGradient(
                    colors: [Color(0xFFD946EF), Color(0xFF7B2FE0)],
                  ) : null,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.sports_esports_rounded,
                        color: _isLexi ? Colors.white : Colors.white38, size: 16),
                    const SizedBox(width: 6),
                    Text('LEXIRUSH',
                      style: TextStyle(
                        color: _isLexi ? Colors.white : Colors.white38,
                        fontWeight: FontWeight.w800, fontSize: 11, letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _gameMode = 'spell_shooter'),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  gradient: !_isLexi ? const LinearGradient(
                    colors: [Color(0xFFF59E0B), Color(0xFFF97316)],
                  ) : null,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.track_changes_rounded,
                        color: !_isLexi ? Colors.white : Colors.white38, size: 16),
                    const SizedBox(width: 6),
                    Text('SPELL SHOOTER',
                      style: TextStyle(
                        color: !_isLexi ? Colors.white : Colors.white38,
                        fontWeight: FontWeight.w800, fontSize: 11, letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToggleRow({
    required String leftLabel,
    required String rightLabel,
    required IconData rightIcon,
    required bool isLeft,
    required LinearGradient leftGradient,
    required LinearGradient rightGradient,
    required VoidCallback onLeft,
    required VoidCallback onRight,
  }) {
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: onLeft,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 11),
                decoration: BoxDecoration(
                  gradient: isLeft ? leftGradient : null,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Center(
                  child: Text(leftLabel,
                    style: TextStyle(
                      color: isLeft ? Colors.white : Colors.white38,
                      fontWeight: FontWeight.w800, fontSize: 11,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: onRight,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 11),
                decoration: BoxDecoration(
                  gradient: !isLeft ? rightGradient : null,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(rightIcon,
                        color: !isLeft ? Colors.white : Colors.white38, size: 14),
                    const SizedBox(width: 5),
                    Text(rightLabel,
                      style: TextStyle(
                        color: !isLeft ? Colors.white : Colors.white38,
                        fontWeight: FontWeight.w800, fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLevelDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _accentColor.withOpacity(0.3)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _level,
          isExpanded: true,
          dropdownColor: AppColors.bgCard,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13),
          icon: Icon(Icons.expand_more_rounded, color: _accentColor, size: 20),
          items: const [
            DropdownMenuItem(value: '1', child: Text('Level 1 (Novice) -0.1')),
            DropdownMenuItem(value: '2', child: Text('Level 2 (Intermediate) -0.2')),
            DropdownMenuItem(value: '3', child: Text('Level 3 (Advanced) -0.3')),
            DropdownMenuItem(value: '4', child: Text('Level 4 (Master) -0.5')),
          ],
          onChanged: (v) { if (v != null) setState(() => _level = v); },
        ),
      ),
    );
  }

  Widget _buildCustomUploadSection() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.neonGreen.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.neonGreen.withOpacity(0.3),
          style: BorderStyle.solid,
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.table_view_rounded, color: AppColors.neonGreen, size: 18),
              const SizedBox(width: 8),
              Text('UPLOAD EXCEL / CSV',
                style: TextStyle(
                  color: AppColors.neonGreen,
                  fontWeight: FontWeight.w900, fontSize: 14, fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text('Headers: WORD · POS · MEANING · SYNONYMS · ANTONYMS | Min 25 rows',
            style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 9, letterSpacing: 0.5),
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              color: AppColors.bgDeep,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withOpacity(0.08)),
            ),
            child: Column(
              children: [
                Icon(Icons.upload_file_rounded,
                    color: AppColors.neonGreen.withOpacity(0.5), size: 36),
                const SizedBox(height: 8),
                Text('Custom upload available via file_picker package',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.25),
                    fontSize: 10, fontStyle: FontStyle.italic,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text('Add file_picker: ^8.0.0 to pubspec.yaml',
                  style: TextStyle(
                    color: AppColors.neonGreen.withOpacity(0.4),
                    fontSize: 10, fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── ARENA ACCESS CARD ────────────────────────────────────
  Widget _buildArenaAccessCard() {
    final canGenerate = !_isGenerating &&
        (_isCustomRoom || _total == 25);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        children: [
          // QR icon
          Container(
            width: 60, height: 60,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.04),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withOpacity(0.08)),
            ),
            child: const Icon(Icons.qr_code_scanner_rounded,
                color: Colors.white, size: 30),
          ),

          const SizedBox(height: 12),

          const Text('ARENA ACCESS',
            style: TextStyle(
              color: Colors.white, fontWeight: FontWeight.w900,
              fontSize: 16, fontStyle: FontStyle.italic, letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 4),
          Text('Generate a unique key for deployment.',
            style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 10),
          ),

          const SizedBox(height: 20),

          // Room code display OR generate button
          if (_roomCode.isEmpty)
            GestureDetector(
              onTap: canGenerate ? _handleGenerateRoom : null,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  color: canGenerate
                      ? Colors.white.withOpacity(0.08)
                      : AppColors.bgSurface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: canGenerate
                        ? Colors.white.withOpacity(0.15)
                        : Colors.white.withOpacity(0.04),
                  ),
                ),
                child: Center(
                  child: _isGenerating
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 16, height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white70),
                            ),
                            const SizedBox(width: 10),
                            const Text('PROCESSING...',
                              style: TextStyle(color: Colors.white70,
                                  fontWeight: FontWeight.w800, letterSpacing: 2),
                            ),
                          ],
                        )
                      : Text('GENERATE CODE',
                          style: TextStyle(
                            color: canGenerate ? Colors.white : Colors.white24,
                            fontWeight: FontWeight.w900, letterSpacing: 2, fontSize: 13,
                          ),
                        ),
                ),
              ),
            )
          else
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    _accentColor.withOpacity(0.15),
                    _accentColorAlt.withOpacity(0.08),
                  ],
                ),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _accentColor.withOpacity(0.4)),
              ),
              child: Column(
                children: [
                  Text('ARENA CODE',
                    style: TextStyle(
                      color: _accentColor,
                      fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(_roomCode,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 32, letterSpacing: 4,
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 14),

          // Enter Lobby button
          GestureDetector(
            onTap: _roomCode.isEmpty
                ? null
                : () {
                    if (_isLexi) {
                      Navigator.pushNamed(context, AppRoutes.lobby,
                        arguments: {'roomCode': _roomCode, 'isAdmin': true});
                    } else {
                      Navigator.pushNamed(context, AppRoutes.spellLobby,
                        arguments: {'roomCode': _roomCode, 'isAdmin': true});
                    }
                  },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 18),
              decoration: BoxDecoration(
                gradient: _roomCode.isEmpty
                    ? null
                    : _isCustomRoom
                        ? const LinearGradient(
                            colors: [Color(0xFF10B981), Color(0xFF0D9488)])
                        : _modeGradient,
                color: _roomCode.isEmpty ? AppColors.bgSurface : null,
                borderRadius: BorderRadius.circular(16),
                boxShadow: _roomCode.isEmpty
                    ? []
                    : [BoxShadow(
                        color: _accentColor.withOpacity(0.4),
                        blurRadius: 20, offset: const Offset(0, 6),
                      )],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('ENTER LOBBY',
                    style: TextStyle(
                      color: _roomCode.isEmpty ? Colors.white12 : Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 15, letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.play_circle_rounded,
                      color: _roomCode.isEmpty ? Colors.white12 : Colors.white,
                      size: 22),
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
// Stepper Card Widget
// ============================================================
class _StepperCard extends StatelessWidget {
  final String title;
  final int value;
  final Color color;
  final String unit;
  final int min;
  final int max;
  final int step;
  final ValueChanged<int> onChanged;

  const _StepperCard({
    required this.title,
    required this.value,
    required this.color,
    required this.onChanged,
    this.unit = '',
    this.min = 0,
    this.max = 25,
    this.step = 1,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.bgSurface.withOpacity(0.8),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.15)),
      ),
      child: Column(
        children: [
          Text(title,
            style: TextStyle(
              color: color, fontSize: 9,
              fontWeight: FontWeight.w800, letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              // Value display
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white.withOpacity(0.05)),
                  ),
                  child: Column(
                    children: [
                      Text('$value',
                        style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w900, fontSize: 28,
                        ),
                      ),
                      if (unit.isNotEmpty)
                        Text(unit,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.3),
                            fontSize: 8, fontWeight: FontWeight.w700,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // +/- buttons
              Column(
                children: [
                  GestureDetector(
                    onTap: value < max ? () => onChanged(math.min(max, value + step)) : null,
                    child: Container(
                      width: 30, height: 30,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white.withOpacity(0.1)),
                      ),
                      child: Icon(Icons.keyboard_arrow_up_rounded,
                          color: value < max ? Colors.white60 : Colors.white12, size: 18),
                    ),
                  ),
                  const SizedBox(height: 6),
                  GestureDetector(
                    onTap: value > min ? () => onChanged(math.max(min, value - step)) : null,
                    child: Container(
                      width: 30, height: 30,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white.withOpacity(0.1)),
                      ),
                      child: Icon(Icons.keyboard_arrow_down_rounded,
                          color: value > min ? Colors.white60 : Colors.white12, size: 18),
                    ),
                  ),
                ],
              ),
            ],
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
    if (!size.width.isFinite || !size.height.isFinite || size.width <= 0 || size.height <= 0) return;
    final rng = math.Random(77);
    for (int i = 0; i < 22; i++) {
      final x     = rng.nextDouble() * size.width;
      final baseY = rng.nextDouble() * size.height;
      final speed = 0.3 + rng.nextDouble() * 1.0;
      
      double y = (baseY - t * size.height * speed);
      if (size.height > 0) {
        y = y % size.height;
      }
      if (y.isNaN || y.isInfinite) y = 0.0;
      final safeX = (x.isNaN || x.isInfinite) ? 0.0 : x;
      
      final rad   = 1.0 + rng.nextDouble() * 2.0;
      final safeRad = (rad.isNaN || rad.isInfinite || rad <= 0) ? 1.0 : rad;
      final op    = 0.05 + rng.nextDouble() * 0.14;
      
      canvas.drawCircle(
        Offset(safeX, y),
        safeRad,
        Paint()..color = (rng.nextBool() ? AppColors.neonPurple : AppColors.neonCyan)
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