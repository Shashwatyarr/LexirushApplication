// ============================================================
// FILE: lib/features/game/lexirush/game_screen.dart
// ============================================================

import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import '../../../core/constants/app_colors.dart';

// ── Data model for a grid cell ───────────────────────────────
class GridCell {
  final String cellId;
  final String text;
  GridCell({required this.cellId, required this.text});
  factory GridCell.fromJson(Map<String, dynamic> j) =>
      GridCell(cellId: j['cellId'] as String, text: j['text'] as String);
}

// ── Cell visual state ────────────────────────────────────────
enum CellState { idle, correct, wrong, adminCorrect, locked }

class GameScreen extends StatefulWidget {
  final String roomCode;
  final bool isAdmin;
  final Map<String, dynamic>? initialState; // from lobby navigation

  const GameScreen({
    super.key,
    required this.roomCode,
    required this.isAdmin,
    this.initialState,
  });

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen>
    with TickerProviderStateMixin {

  // ── Animation controllers ─────────────────────────────────
  late AnimationController _particleCtrl;
  late AnimationController _timerPulseCtrl;

  // ── Socket ───────────────────────────────────────────────
  IO.Socket? _socket;

  // ── User info ────────────────────────────────────────────
  String _userId   = '';
  String _userName = '';
  String _avatar   = '';
  String _role     = 'student';

  // ── Game state ───────────────────────────────────────────
  List<GridCell>         _grid          = [];
  List<Map<String,dynamic>> _fullQuestions = [];
  Map<String, dynamic>?  _currentQ;
  int                    _timeLeft      = 0;
  double                 _score         = 0;
  bool                   _isLocked      = false;
  Map<String, CellState> _cellStates    = {};
  List<Map<String,dynamic>> _liveRanks  = [];
  String?                _hintData;
  int                    _hintsLeft     = 5;

  // ── UI state ─────────────────────────────────────────────
  int  _activeTab        = 0; // 0=arena 1=ranks 2=masterkey
  bool _gridVisible      = true;
  bool _questionChanging = false;

  // ── Timer ────────────────────────────────────────────────
  bool _timerRunning = false;

  @override
  void initState() {
    super.initState();

    _particleCtrl = AnimationController(
      duration: const Duration(seconds: 6), vsync: this,
    )..repeat();

    _timerPulseCtrl = AnimationController(
      duration: const Duration(milliseconds: 500), vsync: this,
    )..repeat(reverse: true);

    _loadUserAndConnect();
  }

  @override
  void dispose() {
    _socket?.disconnect();
    _socket?.dispose();
    _particleCtrl.dispose();
    _timerPulseCtrl.dispose();
    super.dispose();
  }

  // ── Load prefs → build grid from initialState → connect ──
  Future<void> _loadUserAndConnect() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _userId   = prefs.getString('userId')   ?? '';
      _userName = prefs.getString('userName') ?? 'Player';
      _avatar   = prefs.getString('avatar')   ?? '';
      _role     = prefs.getString('role')     ?? 'student';
    });

    // Build grid from nav args
    if (widget.initialState != null) {
      final gridBase = widget.initialState!['gridBase'] as List?;
      if (gridBase != null && gridBase.isNotEmpty) {
        final shuffled = List<Map<String,dynamic>>.from(gridBase)..shuffle();
        setState(() {
          _grid = shuffled.map((e) => GridCell.fromJson(Map<String,dynamic>.from(e))).toList();
        });
      }
      final fq = widget.initialState!['fullQuestionData'] as List?;
      if (fq != null) {
        setState(() {
          _fullQuestions = fq.map((e) => Map<String,dynamic>.from(e as Map)).toList();
        });
      }
      // Reconnect data
      final rData = widget.initialState!['reconnectData'] as Map?;
      if (rData != null) {
        setState(() {
          _score    = (rData['score'] as num?)?.toDouble() ?? 0;
          _currentQ = rData['currentQuestion'] as Map<String,dynamic>?;
          _timeLeft = _currentQ != null ? (_currentQ!['timeLimit'] as num?)?.toInt() ?? 0 : 0;
          _isLocked = rData['answeredCurrent'] == true;
        });
        _startTimer();
      }
    }

    _connectSocket();
  }

  // ── Socket setup ─────────────────────────────────────────
  void _connectSocket() {
    _socket = IO.io(
      'https://tambola-67o6.onrender.com',
      IO.OptionBuilder().setTransports(['websocket']).disableAutoConnect().build(),
    );
    _socket!.connect();

    _socket!.onConnect((_) {
      _socket!.emit('joinRoom', {
        'roomCode': widget.roomCode.toUpperCase(),
        'userId'  : _userId,
        'name'    : _userName,
        'avatar'  : _avatar,
        'isAdmin' : widget.isAdmin,
      });
      _socket!.emit('requestSync', {
        'roomCode': widget.roomCode,
        'userId'  : _userId,
      });
    });

    // ── newQuestion ──
    _socket!.on('newQuestion', (data) {
      if (!mounted) return;
      final q = Map<String,dynamic>.from(data as Map);
      setState(() {
        _gridVisible      = false;
        _questionChanging = true;
        _hintData         = null;
        _currentQ         = q;
        _timeLeft         = (q['timeLimit'] as num?)?.toInt() ?? 15;
        _isLocked         = false;
        // keep correct cells, reset others
        _cellStates = Map.fromEntries(
          _cellStates.entries.where((e) => e.value == CellState.correct),
        );
      });
      Future.delayed(const Duration(milliseconds: 150), () {
        if (mounted) setState(() => _gridVisible = true);
      });
      Future.delayed(const Duration(milliseconds: 400), () {
        if (mounted) setState(() => _questionChanging = false);
      });
      _startTimer();

      // admin: highlight correct cell
      if (widget.isAdmin) _highlightAdminCorrect(q);
    });

    // ── answerResult ──
    _socket!.on('answerResult', (data) {
      if (!mounted) return;
      final d = Map<String,dynamic>.from(data as Map);
      setState(() {
        _score = (d['totalPoints'] as num?)?.toDouble() ?? _score;
        final cellId = d['cellId'] as String? ?? '';
        if (d['success'] == true) {
          _cellStates[cellId] = CellState.correct;
          _isLocked = true;
        } else {
          _cellStates[cellId] = CellState.wrong;
          _isLocked = true;
          Future.delayed(const Duration(milliseconds: 1000), () {
            if (mounted) setState(() {
              _cellStates[cellId] = CellState.idle;
              _isLocked = false;
            });
          });
        }
      });
    });

    // ── hintResult ──
    _socket!.on('hintResult', (data) {
      if (!mounted) return;
      final d = Map<String,dynamic>.from(data as Map);
      setState(() => _hintData = d['meaning'] as String?);
    });

    // ── liveLeaderboard ──
    _socket!.on('liveLeaderboard', (data) {
      if (!mounted) return;
      setState(() {
        _liveRanks = (data as List)
            .map((e) => Map<String,dynamic>.from(e as Map))
            .toList();
      });
    });

    // ── reconnectGame ──
    _socket!.on('reconnectGame', (data) {
      if (!mounted) return;
      final d = Map<String,dynamic>.from(data as Map);
      setState(() {
        _score    = (d['score'] as num?)?.toDouble() ?? 0;
        _currentQ = d['currentQuestion'] as Map<String,dynamic>?;
        _timeLeft = _currentQ != null
            ? (_currentQ!['timeLimit'] as num?)?.toInt() ?? 0
            : 0;
        _isLocked = d['answeredCurrent'] == true;
      });
      final gb = d['gridBase'] as List?;
      if (gb != null && _grid.isEmpty) {
        final shuffled = List<Map<String,dynamic>>.from(gb)..shuffle();
        setState(() {
          _grid = shuffled.map((e) => GridCell.fromJson(Map<String,dynamic>.from(e))).toList();
        });
      }
      _startTimer();
    });

    // ── playerKicked ──
    _socket!.on('playerKicked', (kickedId) {
      if (!mounted) return;
      if (kickedId == _userId) {
        _showAlert('Kicked!', 'You were removed by the Admin.', () {
          Navigator.pop(context);
        });
      }
    });

    // ── gameOver ──
    _socket!.on('gameOver', (data) {
      if (!mounted) return;
      // TODO: Navigator.pushReplacementNamed(context, AppRoutes.leaderboard,
      //   arguments: {'roomCode': widget.roomCode, 'data': data});
      debugPrint('Game over: $data');
      Navigator.pop(context);
    });

    // ── error ──
    _socket!.on('error', (msg) {
      if (!mounted) return;
      _showAlert('Arena Error', msg.toString(), () => Navigator.pop(context));
    });
  }

  void _highlightAdminCorrect(Map<String,dynamic> q) {
    final answer = q['answer'] ?? q['question']?['answer'];
    if (answer == null) return;
    for (final cell in _grid) {
      if (cell.text == answer) {
        setState(() => _cellStates[cell.cellId] = CellState.adminCorrect);
        break;
      }
    }
  }

  // ── Timer ────────────────────────────────────────────────
  void _startTimer() {
    _timerRunning = true;
    _tickTimer();
  }

  void _tickTimer() async {
    while (_timerRunning && mounted && _timeLeft > 0) {
      await Future.delayed(const Duration(seconds: 1));
      if (mounted && _timerRunning) setState(() => _timeLeft--);
    }
  }

  // ── Actions ──────────────────────────────────────────────
  void _handleCellTap(GridCell cell) {
    if (_isLocked || widget.isAdmin) return;
    if ((_cellStates[cell.cellId] ?? CellState.idle) != CellState.idle) return;
    setState(() => _isLocked = true);
    _socket?.emit('submitAnswer', {
      'roomCode'  : widget.roomCode,
      'userId'    : _userId,
      'answerText': cell.text,
      'cellId'    : cell.cellId,
    });
  }

  void _handleHint() {
    if (_hintsLeft <= 0 || _hintData != null || _isLocked) return;
    setState(() => _hintsLeft--);
    _socket?.emit('useHint', {'roomCode': widget.roomCode, 'userId': _userId});
  }

  void _handleExit() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: AppColors.neonRed.withOpacity(0.4)),
        ),
        title: const Text('Abandon Arena?',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
        content: const Text('You will not be able to rejoin this match.',
            style: TextStyle(color: Colors.white60)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Stay', style: TextStyle(color: Colors.white.withOpacity(0.4))),
          ),
          TextButton(
            onPressed: () {
              _socket?.emit('leaveRoom', {'roomCode': widget.roomCode});
              Navigator.pop(context); // close dialog
              Navigator.pop(context); // go back
            },
            child: Text('Exit', style: TextStyle(color: AppColors.neonRed, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  void _showAlert(String title, String msg, VoidCallback onOk) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: AppColors.neonPurple.withOpacity(0.3)),
        ),
        title: Text(title,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
        content: Text(msg, style: const TextStyle(color: Colors.white60)),
        actions: [
          TextButton(onPressed: onOk,
              child: Text('OK', style: TextStyle(color: AppColors.neonPurple))),
        ],
      ),
    );
  }

  // ── Helpers ──────────────────────────────────────────────
  String _formatTime(int s) {
    final m = (s ~/ 60).toString().padLeft(2, '0');
    final sec = (s % 60).toString().padLeft(2, '0');
    return '$m:$sec';
  }

  String get _currentType =>
      _currentQ?['type'] ?? _currentQ?['question']?['type'] ?? '???';

  String get _currentWord =>
      _currentQ?['word'] ?? _currentQ?['question']?['word'] ?? '???';

  int get _currentSerial => (_currentQ?['serialNo'] as num?)?.toInt() ?? 0;

  int get _myRankIndex =>
      _liveRanks.indexWhere((p) => p['userId'] == _userId);

  String get _myRankDisplay =>
      _myRankIndex >= 0 ? '#${_myRankIndex + 1}' : '-';

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
                  child: _activeTab == 0
                      ? _buildArenaTab()
                      : _activeTab == 1
                      ? _buildRanksTab()
                      : _buildMasterKeyTab(),
                ),
                _buildBottomNav(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── HEADER ───────────────────────────────────────────────
  Widget _buildHeader() {
    final isAdminRole = widget.isAdmin;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.bgCard.withOpacity(0.9),
        border: Border(
          bottom: BorderSide(color: Colors.white.withOpacity(0.06)),
        ),
      ),
      child: Column(
        children: [
          // Question line
          Row(
            children: [
              // Live badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.neonPurple.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.neonPurple.withOpacity(0.4)),
                ),
                child: Row(
                  children: [
                    AnimatedBuilder(
                      animation: _timerPulseCtrl,
                      builder: (_, __) => Container(
                        width: 5, height: 5,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.neonPurple.withOpacity(0.5 + 0.5 * _timerPulseCtrl.value),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Text('LIVE ARENA',
                      style: TextStyle(
                        color: AppColors.neonPurple,
                        fontSize: 8, fontWeight: FontWeight.w800, letterSpacing: 1.5,
                      ),
                    ),
                  ],
                ),
              ),

              const Spacer(),

              // Q counter
              Text(
                'Q $_currentSerial / 25',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.3),
                  fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1,
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // Question text
          if (_currentQ != null)
            AnimatedOpacity(
              opacity: _questionChanging ? 0.3 : 1.0,
              duration: const Duration(milliseconds: 200),
              child: Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 6,
                children: [
                  const Text('FIND THE',
                    style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w900, fontSize: 16),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: (_currentType == 'synonym'
                          ? AppColors.neonCyan
                          : AppColors.neonPurple).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      _currentType.toUpperCase(),
                      style: TextStyle(
                        color: _currentType == 'synonym'
                            ? AppColors.neonCyan
                            : AppColors.neonPurple,
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  const Text('OF',
                    style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w900, fontSize: 16),
                  ),
                  ShaderMask(
                    shaderCallback: (b) => const LinearGradient(
                      colors: [Colors.white, Color(0xFFCCCCCC)],
                    ).createShader(b),
                    child: Text(
                      _currentWord.toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                        decoration: TextDecoration.underline,
                        decorationColor: AppColors.neonPurple,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            Text(
              'DECRYPTING GRID...',
              style: TextStyle(
                color: Colors.white.withOpacity(0.3),
                fontWeight: FontWeight.w900,
                fontSize: 15,
                letterSpacing: 2,
              ),
            ),

          // Hint banner
          if (_hintData != null) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFFFC107).withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFFFC107).withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.lightbulb_outline_rounded,
                      color: Color(0xFFFFC107), size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '"$_hintData"',
                      style: const TextStyle(
                        color: Color(0xFFFFF9C4),
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 10),

          // Stats row
          Row(
            children: [
              // Timer
              _buildStatChip(
                label: 'TIME',
                value: _formatTime(_timeLeft),
                color: _timeLeft <= 5 ? AppColors.neonRed : Colors.white,
                pulse: _timeLeft <= 5,
              ),
              const SizedBox(width: 8),

              if (!isAdminRole) ...[
                // Rank
                _buildStatChip(
                  label: 'RANK',
                  value: _myRankDisplay,
                  color: AppColors.neonCyan,
                ),
                const SizedBox(width: 8),

                // Score
                _buildStatChip(
                  label: 'XP',
                  value: _score.toStringAsFixed(0),
                  color: AppColors.neonPurple,
                ),
                const SizedBox(width: 8),

                // Hint button
                GestureDetector(
                  onTap: _handleHint,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: (_hintsLeft > 0 && _hintData == null)
                          ? const Color(0xFFFFC107).withOpacity(0.1)
                          : Colors.white.withOpacity(0.04),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: (_hintsLeft > 0 && _hintData == null)
                            ? const Color(0xFFFFC107).withOpacity(0.4)
                            : Colors.white.withOpacity(0.08),
                      ),
                    ),
                    child: Column(
                      children: [
                        Text('HINT',
                          style: TextStyle(
                            color: (_hintsLeft > 0 && _hintData == null)
                                ? const Color(0xFFFFC107)
                                : Colors.white30,
                            fontSize: 7,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1,
                          ),
                        ),
                        Row(
                          children: [
                            Icon(Icons.lightbulb_outline_rounded,
                              color: (_hintsLeft > 0 && _hintData == null)
                                  ? const Color(0xFFFFC107)
                                  : Colors.white30,
                              size: 12,
                            ),
                            const SizedBox(width: 2),
                            Text('$_hintsLeft',
                              style: TextStyle(
                                color: (_hintsLeft > 0 && _hintData == null)
                                    ? const Color(0xFFFFC107)
                                    : Colors.white30,
                                fontSize: 14,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatChip({
    required String label,
    required String value,
    required Color color,
    bool pulse = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Column(
        children: [
          Text(label,
            style: TextStyle(
              color: color.withOpacity(0.6),
              fontSize: 7, fontWeight: FontWeight.w800, letterSpacing: 1,
            ),
          ),
          pulse
              ? AnimatedBuilder(
            animation: _timerPulseCtrl,
            builder: (_, __) => Text(value,
              style: TextStyle(
                color: color.withOpacity(0.6 + 0.4 * _timerPulseCtrl.value),
                fontSize: 15, fontWeight: FontWeight.w900,
              ),
            ),
          )
              : Text(value,
            style: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }

  // ── ARENA TAB ────────────────────────────────────────────
  Widget _buildArenaTab() {
    if (_grid.isEmpty) {
      return Center(
        child: Text('INITIALIZING BATTLEFIELD...',
          style: TextStyle(
            color: Colors.white.withOpacity(0.3),
            fontWeight: FontWeight.w900,
            letterSpacing: 2,
            fontSize: 12,
          ),
        ),
      );
    }

    return AnimatedOpacity(
      opacity: _gridVisible ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 150),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: GridView.builder(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 5,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 1.1,
          ),
          itemCount: _grid.length,
          itemBuilder: (_, i) => _buildCell(_grid[i]),
        ),
      ),
    );
  }

  Widget _buildCell(GridCell cell) {
    final state = _cellStates[cell.cellId] ?? CellState.idle;
    final isAdminRole = widget.isAdmin;

    Color bgColor;
    Color borderColor;
    Color textColor;
    bool canTap = !_isLocked && !isAdminRole && state == CellState.idle;

    switch (state) {
      case CellState.correct:
        bgColor     = AppColors.neonGreen.withOpacity(0.15);
        borderColor = AppColors.neonGreen.withOpacity(0.6);
        textColor   = AppColors.neonGreen;
        canTap      = false;
        break;
      case CellState.adminCorrect:
        bgColor     = AppColors.neonGreen.withOpacity(0.08);
        borderColor = AppColors.neonGreen.withOpacity(0.4);
        textColor   = AppColors.neonGreen.withOpacity(0.8);
        canTap      = false;
        break;
      case CellState.wrong:
        bgColor     = AppColors.neonRed.withOpacity(0.15);
        borderColor = AppColors.neonRed.withOpacity(0.6);
        textColor   = AppColors.neonRed;
        canTap      = false;
        break;
      case CellState.locked:
      case CellState.idle:
      default:
        if (_isLocked || isAdminRole) {
          bgColor     = AppColors.bgDeep.withOpacity(0.8);
          borderColor = Colors.white.withOpacity(0.05);
          textColor   = Colors.white.withOpacity(0.25);
        } else {
          bgColor     = AppColors.bgCard.withOpacity(0.85);
          borderColor = Colors.white.withOpacity(0.1);
          textColor   = Colors.white.withOpacity(0.85);
        }
    }

    return GestureDetector(
      onTap: canTap ? () => _handleCellTap(cell) : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor, width: 1.2),
          boxShadow: state == CellState.correct
              ? [BoxShadow(color: AppColors.neonGreen.withOpacity(0.3), blurRadius: 10)]
              : state == CellState.wrong
              ? [BoxShadow(color: AppColors.neonRed.withOpacity(0.3), blurRadius: 10)]
              : [],
        ),
        child: Center(
          child: Text(
            cell.text,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: textColor,
              fontWeight: FontWeight.w800,
              fontSize: 10,
              letterSpacing: 0.5,
              height: 1.2,
            ),
          ),
        ),
      ),
    );
  }

  // ── RANKS TAB ────────────────────────────────────────────
  Widget _buildRanksTab() {
    final myRank = _myRankIndex >= 0 ? _liveRanks[_myRankIndex] : null;

    return Container(
      margin: const EdgeInsets.all(14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bgCard.withOpacity(0.9),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ShaderMask(
            shaderCallback: (b) => const LinearGradient(
              colors: [AppColors.neonCyan, Color(0xFF3B82F6)],
            ).createShader(b),
            child: const Text('LIVE RANKINGS',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 18,
                letterSpacing: 2,
              ),
            ),
          ),

          const SizedBox(height: 12),

          // My rank card
          if (myRank != null && !widget.isAdmin) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.neonPurple.withOpacity(0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.neonPurple.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Text('#${_myRankIndex + 1}',
                    style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w900, fontSize: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  _buildAvatar(myRank['avatar'] as String?),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(myRank['name'] as String? ?? _userName,
                              style: const TextStyle(
                                color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.neonPurple.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text('YOU',
                                style: TextStyle(
                                  color: AppColors.neonPurple, fontSize: 8, fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                        Text('Current Position',
                          style: TextStyle(
                            color: AppColors.neonPurple.withOpacity(0.6),
                            fontSize: 10, fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text('${(myRank['points'] as num?)?.toStringAsFixed(0) ?? '0'} XP',
                    style: const TextStyle(
                      color: AppColors.neonPurple, fontWeight: FontWeight.w900, fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          // All ranks
          Expanded(
            child: _liveRanks.isEmpty
                ? Center(
              child: Text('Waiting for XP...',
                style: TextStyle(color: Colors.white.withOpacity(0.3),
                    fontWeight: FontWeight.w700),
              ),
            )
                : ListView.separated(
              itemCount: _liveRanks.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final p = _liveRanks[i];
                final isMe = p['userId'] == _userId;
                final isOffline = p['isOnline'] == false;

                final rankColor = i == 0
                    ? const Color(0xFFFFC107)
                    : i == 1
                    ? Colors.white60
                    : i == 2
                    ? const Color(0xFFCD7F32)
                    : Colors.white30;

                return Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isMe
                        ? AppColors.neonPurple.withOpacity(0.08)
                        : Colors.white.withOpacity(0.03),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isOffline
                          ? AppColors.neonRed.withOpacity(0.2)
                          : isMe
                          ? AppColors.neonPurple.withOpacity(0.3)
                          : Colors.white.withOpacity(0.07),
                    ),
                  ),
                  child: Row(
                    children: [
                      Text('#${i + 1}',
                        style: TextStyle(
                          color: rankColor, fontWeight: FontWeight.w900, fontSize: 18,
                        ),
                      ),
                      const SizedBox(width: 10),
                      _buildAvatar(p['avatar'] as String?,
                          grayscale: isOffline),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          p['name'] as String? ?? 'Player',
                          style: TextStyle(
                            color: isOffline ? Colors.white30 : Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            decoration: isOffline ? TextDecoration.lineThrough : null,
                          ),
                        ),
                      ),
                      Text(
                        '${(p['points'] as num?)?.toStringAsFixed(0) ?? '0'} XP',
                        style: const TextStyle(
                          color: AppColors.neonPurple,
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ── MASTER KEY TAB (admin) ───────────────────────────────
  Widget _buildMasterKeyTab() {
    return Container(
      margin: const EdgeInsets.all(14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bgCard.withOpacity(0.9),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('MASTER KEY',
            style: TextStyle(
              color: AppColors.neonGreen,
              fontWeight: FontWeight.w900,
              fontSize: 18,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 12),

          Expanded(
            child: _fullQuestions.isEmpty
                ? Center(
              child: Text('Decrypting Master Key...',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.3),
                  fontWeight: FontWeight.w700,
                ),
              ),
            )
                : ListView.separated(
              itemCount: _fullQuestions.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final q = _fullQuestions[i];
                final type   = q['type']   ?? q['question']?['type']   ?? '?';
                final word   = q['word']   ?? q['question']?['word']   ?? '?';
                final answer = q['answer'] ?? q['question']?['answer'] ?? '?';
                final serial = q['serialNo'] ?? i + 1;

                return Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.03),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withOpacity(0.07)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black26,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text('Q$serial',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.4),
                            fontWeight: FontWeight.w800,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: RichText(
                          text: TextSpan(
                            style: const TextStyle(fontSize: 12),
                            children: [
                              const TextSpan(text: 'Find the ',
                                  style: TextStyle(color: Colors.white60)),
                              TextSpan(
                                text: type,
                                style: TextStyle(
                                  color: type == 'synonym'
                                      ? AppColors.neonCyan
                                      : AppColors.neonPurple,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const TextSpan(text: ' of ',
                                  style: TextStyle(color: Colors.white60)),
                              TextSpan(
                                text: word.toString().toUpperCase(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.neonGreen.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: AppColors.neonGreen.withOpacity(0.3)),
                        ),
                        child: Text(answer.toString().toUpperCase(),
                          style: TextStyle(
                            color: AppColors.neonGreen,
                            fontWeight: FontWeight.w900,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ── BOTTOM NAV ───────────────────────────────────────────
  Widget _buildBottomNav() {
    final tabs = [
      {'icon': Icons.sports_esports_rounded, 'label': 'ARENA'},
      {'icon': Icons.leaderboard_rounded,    'label': 'RANKS'},
      if (widget.isAdmin)
        {'icon': Icons.vpn_key_rounded, 'label': 'MASTER KEY'},
    ];

    return Container(
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        border: Border(top: BorderSide(color: Colors.white.withOpacity(0.06))),
      ),
      child: Row(
        children: [
          // Exit button
          GestureDetector(
            onTap: _handleExit,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Icon(Icons.logout_rounded,
                  color: AppColors.neonRed, size: 22),
            ),
          ),

          // Tabs
          ...tabs.asMap().entries.map((entry) {
            final i     = entry.key;
            final tab   = entry.value;
            final isAct = _activeTab == i;
            return Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _activeTab = i),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(
                        color: isAct ? AppColors.neonPurple : Colors.transparent,
                        width: 2,
                      ),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(tab['icon'] as IconData,
                        color: isAct ? AppColors.neonPurple : Colors.white30,
                        size: 20,
                      ),
                      const SizedBox(height: 2),
                      Text(tab['label'] as String,
                        style: TextStyle(
                          color: isAct ? AppColors.neonPurple : Colors.white30,
                          fontSize: 8,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  // ── Avatar helper ─────────────────────────────────────────
  Widget _buildAvatar(String? url, {bool grayscale = false}) {
    Widget img = Container(
      width: 36, height: 36,
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: url != null && url.isNotEmpty
          ? ClipRRect(
        borderRadius: BorderRadius.circular(7),
        child: Image.network(url, fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const Icon(
                Icons.person_rounded, color: Colors.white30, size: 20)),
      )
          : const Icon(Icons.person_rounded, color: Colors.white30, size: 20),
    );

    if (grayscale) {
      img = ColorFiltered(
        colorFilter: const ColorFilter.matrix([
          0.2126, 0.7152, 0.0722, 0, 0,
          0.2126, 0.7152, 0.0722, 0, 0,
          0.2126, 0.7152, 0.0722, 0, 0,
          0,      0,      0,      1, 0,
        ]),
        child: Opacity(opacity: 0.4, child: img),
      );
    }

    return img;
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
    final rng = math.Random(42);
    for (int i = 0; i < 25; i++) {
      final x     = rng.nextDouble() * size.width;
      final baseY = rng.nextDouble() * size.height;
      final speed = 0.3 + rng.nextDouble() * 1.0;
      final y     = (baseY - t * size.height * speed) % size.height;
      final rad   = 1.0 + rng.nextDouble() * 2.0;
      final op    = 0.06 + rng.nextDouble() * 0.18;
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