// ============================================================
// FILE: lib/features/game/lexirush/game_screen.dart
// ============================================================

import 'dart:convert';
import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:confetti/confetti.dart';
import 'package:flutter/services.dart';

import '../../../core/constants/app_colors.dart';
import '../../../routes/app_routes.dart';

// ── Data model for a grid cell ───────────────────────────────
class GridCell {
  final String cellId;
  final String text;
  GridCell({required this.cellId, required this.text});
  factory GridCell.fromJson(Map<String, dynamic> j) =>
      GridCell(cellId: j['cellId'] as String, text: j['text'] as String);
  Map<String, dynamic> toJson() => {'cellId': cellId, 'text': text};
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

class _GameScreenState extends State<GameScreen> with TickerProviderStateMixin {
  // ── Animation controllers ─────────────────────────────────
  late AnimationController _timerPulseCtrl;
  late AnimationController _shakeCtrl;
  late ConfettiController _confettiController;

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

  bool _timerRunning = false;
  bool _isDisposing = false;
  Timer? _timer;

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeRight,
      DeviceOrientation.landscapeLeft,
    ]);

    _timerPulseCtrl = AnimationController(
      duration: const Duration(milliseconds: 500), vsync: this,
    )..repeat(reverse: true);

    _shakeCtrl = AnimationController(
      duration: const Duration(milliseconds: 400), vsync: this,
    );

    _confettiController = ConfettiController(duration: const Duration(seconds: 2));

    _loadUserAndConnect();
  }

  @override
  void dispose() {
    _isDisposing = true;
    _timer?.cancel();
    _socket?.disconnect();
    _socket?.dispose();
    _timerPulseCtrl.dispose();
    _shakeCtrl.dispose();
    _confettiController.dispose();

    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    super.dispose();
  }

  // ── Load prefs → build grid from initialState → connect ──
  Future<void> _loadUserAndConnect() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _userId   = prefs.getString('userId')   ?? '';
      _userName = prefs.getString('userName') ?? prefs.getString('name') ?? 'Player';
      _avatar   = prefs.getString('avatar')   ?? prefs.getString('userAvatar') ?? 'https://api.dicebear.com/7.x/avataaars/svg?seed=$_userName';
      _role     = prefs.getString('role')     ?? 'student';
    });

    // Storage fallback similar to React's sessionStorage
    final savedGridStr = prefs.getString('grid_${widget.roomCode}');
    final savedQsStr = prefs.getString('questions_${widget.roomCode}');

    if (widget.initialState != null && widget.initialState!['gridBase'] != null && (widget.initialState!['gridBase'] as List).isNotEmpty) {
      if (savedGridStr == null) {
        final gb = widget.initialState!['gridBase'] as List;
        final shuffled = List<Map<String,dynamic>>.from(gb)..shuffle();
        setState(() {
          _grid = shuffled.map((e) => GridCell.fromJson(Map<String,dynamic>.from(e))).toList();
        });
        prefs.setString('grid_${widget.roomCode}', jsonEncode(_grid.map((c) => c.toJson()).toList()));
      } else {
        final decoded = jsonDecode(savedGridStr) as List;
        setState(() {
          _grid = decoded.map((e) => GridCell.fromJson(Map<String,dynamic>.from(e))).toList();
        });
      }

      final fq = widget.initialState!['fullQuestionData'] as List?;
      if (fq != null) {
        setState(() {
          _fullQuestions = fq.map((e) => Map<String,dynamic>.from(e as Map)).toList();
        });
        prefs.setString('questions_${widget.roomCode}', jsonEncode(_fullQuestions));
      }

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
    } else if (savedGridStr != null && savedQsStr != null) {
      final dGrid = jsonDecode(savedGridStr) as List;
      final dQs = jsonDecode(savedQsStr) as List;
      setState(() {
        _grid = dGrid.map((e) => GridCell.fromJson(Map<String,dynamic>.from(e))).toList();
        _fullQuestions = dQs.map((e) => Map<String,dynamic>.from(e as Map)).toList();
      });
    } else if (!widget.isAdmin) {
      // Hard redirect if no state and no fallback
      Navigator.pushReplacementNamed(context, AppRoutes.studentDashboard);
      return;
    }

    _connectSocket();
  }

  // ── Socket setup ─────────────────────────────────────────
  void _connectSocket() {
    _socket = IO.io(
      'https://tambola-67o6.onrender.com',
      IO.OptionBuilder()
          .setTransports(['websocket'])
          .enableForceNew()
          .disableAutoConnect()
          .build(),
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

    _socket!.onDisconnect((_) {
      // React hard reload check behavior
      if (mounted && !_isDisposing) {
        if (!widget.isAdmin) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Connection lost. Returning to dashboard.")));
          Navigator.pushReplacementNamed(context, AppRoutes.studentDashboard);
        }
      }
    });

    // ── newQuestion ──
    _socket!.on('newQuestion', (data) {
      if (!mounted || _isDisposing) return;
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
        if (mounted && !_isDisposing) setState(() => _gridVisible = true);
      });
      Future.delayed(const Duration(milliseconds: 400), () {
        if (mounted && !_isDisposing) setState(() => _questionChanging = false);
      });
      _startTimer();

      // admin: highlight correct cell
      if (widget.isAdmin) _highlightAdminCorrect(q);
    });

    // ── answerResult ──
    _socket!.on('answerResult', (data) {
      if (!mounted || _isDisposing) return;
      final d = Map<String,dynamic>.from(data as Map);
      setState(() {
        _score = (d['totalPoints'] as num?)?.toDouble() ?? _score;
        final cellId = d['cellId'] as String? ?? '';
        if (d['success'] == true) {
          SystemSound.play(SystemSoundType.click); // Play success click
          _confettiController.play();
          _cellStates[cellId] = CellState.correct;
          _isLocked = true;
        } else {
          SystemSound.play(SystemSoundType.alert); // Play error alert
          _cellStates[cellId] = CellState.wrong;
          _isLocked = true;
          _shakeCtrl.forward(from: 0.0);
          Future.delayed(const Duration(milliseconds: 1000), () {
            if (mounted && !_isDisposing) setState(() {
              _cellStates[cellId] = CellState.idle;
              _isLocked = false;
            });
          });
        }
      });
    });

    // ── hintResult ──
    _socket!.on('hintResult', (data) {
      if (!mounted || _isDisposing) return;
      final d = Map<String,dynamic>.from(data as Map);
      setState(() => _hintData = d['meaning'] as String?);
    });

    // ── liveLeaderboard ──
    _socket!.on('liveLeaderboard', (data) {
      if (!mounted || _isDisposing) return;
      setState(() {
        _liveRanks = (data as List)
            .map((e) => Map<String,dynamic>.from(e as Map))
            .toList();
      });
    });

    // ── reconnectGame ──
    _socket!.on('reconnectGame', (data) async {
      if (!mounted || _isDisposing) return;
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
        final prefs = await SharedPreferences.getInstance();
        prefs.setString('grid_${widget.roomCode}', jsonEncode(_grid.map((c) => c.toJson()).toList()));
        
        if (d['fullQuestionData'] != null) {
          _fullQuestions = (d['fullQuestionData'] as List).map((e) => Map<String,dynamic>.from(e as Map)).toList();
          prefs.setString('questions_${widget.roomCode}', jsonEncode(_fullQuestions));
        }
      }
      _startTimer();
      
      if (widget.isAdmin && _currentQ != null) {
        _highlightAdminCorrect(_currentQ!);
      }
    });

    // ── playerKicked ──
    _socket!.on('playerKicked', (kickedId) async {
      if (!mounted || _isDisposing) return;
      if (kickedId == _userId) {
        final prefs = await SharedPreferences.getInstance();
        prefs.remove('activeRoomCode');
        prefs.remove('grid_${widget.roomCode}');
        prefs.remove('questions_${widget.roomCode}');
        _showAlert('Kicked!', 'You were removed by the Admin.', () {
          Navigator.pushReplacementNamed(context, AppRoutes.studentDashboard);
        });
      }
    });

    // ── gameEnded (gameOver) ──
    _socket!.on('gameOver', (data) async {
      if (!mounted || _isDisposing) return;
      try {
        final prefs = await SharedPreferences.getInstance();
        prefs.remove('grid_${widget.roomCode}');
        prefs.remove('questions_${widget.roomCode}');
        
        Map<String, dynamic> d = {};
        if (data is Map) {
          d = Map<String, dynamic>.from(data);
        }
        
        final leaderboard = (d['leaderboard'] as List? ?? [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
            
        final questionStats = (d['questionStats'] as List? ?? [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
            
        double avg = 0.0;
        if (d['roomAverage'] != null) {
          avg = double.tryParse(d['roomAverage'].toString()) ?? 0.0;
        }

        Navigator.pushReplacementNamed(context, AppRoutes.leaderboard, arguments: {
          'roomCode': widget.roomCode,
          'isAdmin': widget.isAdmin,
          'leaderboard': leaderboard,
          'roomAverage': avg,
          'questionStats': questionStats,
        });
      } catch (e, st) {
        debugPrint('Error in gameOver: $e\n$st');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Transition error: $e'))
          );
        }
      }
    });

    _socket!.on('error', (msg) {
      if (!mounted || _isDisposing) return;
      _showAlert('Arena Error', msg.toString(), () => Navigator.pushReplacementNamed(context, AppRoutes.studentDashboard));
    });
  }

  void _highlightAdminCorrect(Map<String,dynamic> q) {
    final answer = q['answer'] ?? q['question']?['answer'];
    if (answer == null) return;
    
    final target = answer.toString().toLowerCase().trim();
    for (final cell in _grid) {
      if (cell.text.toLowerCase().trim() == target) {
        setState(() => _cellStates[cell.cellId] = CellState.adminCorrect);
        break;
      }
    }
  }

  // ── Timer ────────────────────────────────────────────────
  void _startTimer() {
    _timer?.cancel();
    _timerRunning = true;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_timeLeft > 0) {
        setState(() => _timeLeft--);
      } else {
        timer.cancel();
        _timerRunning = false;
      }
    });
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

  void _handleExit() async {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF131022),
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
            onPressed: () async {
              _socket?.emit('leaveRoom', {'roomCode': widget.roomCode});
              final prefs = await SharedPreferences.getInstance();
              prefs.remove('activeRoomCode');
              prefs.remove('grid_${widget.roomCode}');
              prefs.remove('questions_${widget.roomCode}');
              Navigator.pop(context); // close dialog
              Navigator.pushReplacementNamed(
                context, 
                widget.isAdmin ? AppRoutes.adminDashboard : AppRoutes.studentDashboard
              );
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
        backgroundColor: const Color(0xFF131022),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: AppColors.neonPurple.withOpacity(0.3)),
        ),
        title: Text(title,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
        content: Text(msg, style: const TextStyle(color: Colors.white60)),
        actions: [
          TextButton(onPressed: onOk,
              child: const Text('OK', style: TextStyle(color: AppColors.neonPurple))),
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
      key: _scaffoldKey,
      backgroundColor: const Color(0xFF07050A),
      drawer: _buildDrawer(),
      body: Stack(
        children: [
          // Background Image with Blend
          Positioned.fill(
            child: Opacity(
              opacity: 0.4,
              child: Image.network(
                'https://res.cloudinary.com/dvjefysfi/image/upload/v1781769261/Gemini_Generated_Image_cpwarscpwarscpwa_xdv10b.png',
                fit: BoxFit.cover,
                colorBlendMode: BlendMode.screen,
              ),
            ),
          ),
          
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
              ],
            ),
          ),
          // Confetti overlay
          Align(
            alignment: Alignment.bottomCenter,
            child: ConfettiWidget(
              confettiController: _confettiController,
              blastDirectionality: BlastDirectionality.explosive,
              shouldLoop: false,
              colors: const [Colors.green, Colors.blue, Colors.pink, Colors.orange, Colors.purple],
              maxBlastForce: 100,
              minBlastForce: 80,
              emissionFrequency: 0.05,
              numberOfParticles: 50,
              gravity: 0.1,
            ),
          ),
        ],
      ),
    );
  }

  // ── HEADER ───────────────────────────────────────────────
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Left side: Menu button + Live badge
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.menu, color: Colors.white, size: 28),
                onPressed: () => _scaffoldKey.currentState?.openDrawer(),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF131022).withOpacity(0.8),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withOpacity(0.1)),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 10)
                  ],
                ),
                child: Row(
                  children: [
                    AnimatedBuilder(
                      animation: _timerPulseCtrl,
                      builder: (_, __) => Container(
                        width: 8, height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.neonPurple.withOpacity(0.5 + 0.5 * _timerPulseCtrl.value),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text('LIVE ARENA',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // Center: Question Area
          Expanded(
            child: _buildQuestionArea(),
          ),

          // Right side: Quick Stats Row (Time, Rank, XP, Hint)
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 6,
            runSpacing: 6,
            children: [
              _buildStatChip(
                label: 'TIME',
                value: _formatTime(_timeLeft),
                color: _timeLeft <= 5 ? AppColors.neonRed : Colors.white,
                pulse: _timeLeft <= 5,
                bgColor: Colors.white.withOpacity(0.05),
              ),
              if (!widget.isAdmin) ...[
                const SizedBox(width: 6),
                _buildStatChip(
                  label: 'RANK',
                  value: _myRankDisplay,
                  color: Colors.blueAccent,
                  bgColor: Colors.blueAccent.withOpacity(0.1),
                  borderColor: Colors.blueAccent.withOpacity(0.2),
                ),
                const SizedBox(width: 6),
                _buildStatChip(
                  label: 'TOTAL XP',
                  value: _score.toStringAsFixed(0),
                  color: AppColors.neonPurple,
                  bgColor: AppColors.neonPurple.withOpacity(0.1),
                  borderColor: AppColors.neonPurple.withOpacity(0.2),
                ),
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: _handleHint,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: (_hintsLeft > 0 && _hintData == null && !_isLocked)
                          ? Colors.amber.withOpacity(0.1)
                          : Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: (_hintsLeft > 0 && _hintData == null && !_isLocked)
                            ? Colors.amber.withOpacity(0.3)
                            : Colors.white.withOpacity(0.1),
                      ),
                    ),
                    child: Column(
                      children: [
                        Text('HINT',
                          style: TextStyle(
                            color: (_hintsLeft > 0 && _hintData == null && !_isLocked)
                                ? Colors.amber
                                : Colors.white30,
                            fontSize: 8,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1,
                          ),
                        ),
                        Row(
                          children: [
                            Icon(Icons.lightbulb_outline_rounded,
                              color: (_hintsLeft > 0 && _hintData == null && !_isLocked)
                                  ? Colors.amber
                                  : Colors.white30,
                              size: 14,
                            ),
                            const SizedBox(width: 2),
                            Text('$_hintsLeft',
                              style: TextStyle(
                                color: (_hintsLeft > 0 && _hintData == null && !_isLocked)
                                    ? Colors.amber
                                    : Colors.white30,
                                fontSize: 16,
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

  // ── QUESTION AREA ─────────────────────────────────────────
  Widget _buildQuestionArea() {
    return Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF131022).withOpacity(0.6),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white.withOpacity(0.05)),
                  ),
                  child: Text(
                    'Q $_currentSerial/25',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.6),
                      fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 2,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                if (_currentQ != null)
                  AnimatedOpacity(
                    opacity: _questionChanging ? 0.3 : 1.0,
                    duration: const Duration(milliseconds: 200),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Wrap(
                        alignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          const Text('FIND',
                            style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 1),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: (_currentType == 'synonym'
                                  ? AppColors.neonCyan
                                  : AppColors.neonPurple).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              _currentType.toUpperCase(),
                              style: TextStyle(
                                color: _currentType == 'synonym'
                                    ? AppColors.neonCyan
                                    : AppColors.neonPurple,
                                fontWeight: FontWeight.w900,
                                fontSize: 16,
                                letterSpacing: 1,
                              ),
                            ),
                          ),
                          const Text('OF',
                            style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 1),
                          ),
                          Container(
                            decoration: const BoxDecoration(
                              border: Border(bottom: BorderSide(color: AppColors.neonPurple, width: 2)),
                            ),
                            padding: const EdgeInsets.only(bottom: 2, left: 4, right: 4),
                            child: ShaderMask(
                              shaderCallback: (b) => const LinearGradient(
                                colors: [Colors.white, Color(0xFFCCCCCC)],
                              ).createShader(b),
                              child: Text(
                                _currentWord.toUpperCase(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 24,
                                  letterSpacing: 1,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  Text(
                    'DECRYPTING GRID...',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.5),
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                      letterSpacing: 4,
                    ),
                  ),

                // Hint banner
                if (_hintData != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.amber.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.amber.withOpacity(0.3)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.tips_and_updates,
                            color: Colors.amber, size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('DECRYPTED INTEL',
                                style: TextStyle(
                                  color: Colors.amber,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 2,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '"$_hintData"',
                                style: const TextStyle(
                                  color: Color(0xFFFFF9C4),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          );
  }

  Widget _buildStatChip({
    required String label,
    required String value,
    required Color color,
    Color? bgColor,
    Color? borderColor,
    bool pulse = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor ?? color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor ?? color.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          Text(label,
            style: TextStyle(
              color: color.withOpacity(0.8),
              fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: 1,
            ),
          ),
          pulse
              ? AnimatedBuilder(
            animation: _timerPulseCtrl,
            builder: (_, __) => Text(value,
              style: TextStyle(
                color: color.withOpacity(0.6 + 0.4 * _timerPulseCtrl.value),
                fontSize: 18, fontWeight: FontWeight.w900,
              ),
            ),
          )
              : Text(value,
            style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }

  // ── ARENA TAB ────────────────────────────────────────────
  Widget _buildArenaTab() {
    return Column(
      children: [
        Expanded(child: _buildGrid()),
      ],
    );
  }

  Widget _buildGrid() {
    if (_grid.isEmpty) {
      return Center(
        child: Text('INITIALIZING BATTLEFIELD...',
          style: TextStyle(
            color: Colors.white.withOpacity(0.5),
            fontWeight: FontWeight.w900,
            letterSpacing: 4,
            fontSize: 14,
          ),
        ),
      );
    }

    return AnimatedOpacity(
      opacity: _gridVisible ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 150),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: LayoutBuilder(
          builder: (context, constraints) {
            return GridView.builder(
              physics: const BouncingScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 5,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                childAspectRatio: (constraints.maxWidth / 5) / ((constraints.maxHeight - 32) / 5),
              ),
              itemCount: _grid.length,
              itemBuilder: (_, i) => _buildCell(_grid[i]),
            );
          }
        ),
      ),
    );
  }

  Widget _buildCell(GridCell cell) {
    final state = _cellStates[cell.cellId] ?? CellState.idle;
    final isAdminRole = widget.isAdmin;
    bool canTap = !_isLocked && !isAdminRole && state == CellState.idle;

    // Default styles (React match)
    Color bgColor = const Color(0xFF131022).withOpacity(0.8);
    Color borderColor = Colors.white.withOpacity(0.1);
    Color textColor = Colors.white70;
    double scale = 1.0;
    List<BoxShadow> shadow = [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 10, offset: const Offset(0,4))];

    if (state == CellState.correct) {
      bgColor = Colors.teal.shade900.withOpacity(0.6);
      borderColor = Colors.tealAccent.withOpacity(0.5);
      textColor = Colors.tealAccent;
      scale = 1.05;
      shadow = [BoxShadow(color: Colors.teal.withOpacity(0.4), blurRadius: 15)];
    } else if (state == CellState.adminCorrect) {
      bgColor = Colors.teal.shade900.withOpacity(0.3);
      borderColor = Colors.teal.shade600.withOpacity(0.5);
      textColor = Colors.tealAccent;
      scale = 1.05;
    } else if (state == CellState.wrong) {
      bgColor = Colors.red.shade900.withOpacity(0.6);
      borderColor = Colors.redAccent.withOpacity(0.5);
      textColor = Colors.red.shade200;
      shadow = [BoxShadow(color: Colors.red.withOpacity(0.4), blurRadius: 15)];
    } else if ((_isLocked || isAdminRole) && state == CellState.idle) {
      bgColor = const Color(0xFF0B0914).withOpacity(0.8);
      borderColor = Colors.white.withOpacity(0.05);
      textColor = Colors.white30;
      shadow = [];
    }

    Widget cellWidget = AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      transform: Matrix4.identity()..scale(scale),
      transformAlignment: Alignment.center,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: state == CellState.correct || state == CellState.wrong ? 2 : 1),
        boxShadow: shadow,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: canTap ? () => _handleCellTap(cell) : null,
          borderRadius: BorderRadius.circular(16),
          splashColor: AppColors.neonPurple.withOpacity(0.3),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(4.0),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  cell.text.toUpperCase(),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    // Apply shake animation if wrong
    if (state == CellState.wrong) {
      cellWidget = AnimatedBuilder(
        animation: _shakeCtrl,
        builder: (ctx, child) {
          final sine = math.sin(_shakeCtrl.value * math.pi * 3);
          return Transform.translate(
            offset: Offset(sine * 8, 0),
            child: child,
          );
        },
        child: cellWidget,
      );
    }

    return cellWidget;
  }

  // ── RANKS TAB ────────────────────────────────────────────
  Widget _buildRanksTab() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF131022).withOpacity(0.8),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ShaderMask(
            shaderCallback: (b) => const LinearGradient(
              colors: [Colors.cyanAccent, Colors.blue],
            ).createShader(b),
            child: const Text('LIVE RANKINGS',
              style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: 2),
            ),
          ),
          const SizedBox(height: 24),
          
          if (!widget.isAdmin && _myRankIndex >= 0)
            Container(
              margin: const EdgeInsets.only(bottom: 24),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.neonPurple.withOpacity(0.1),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppColors.neonPurple.withOpacity(0.3)),
                boxShadow: [BoxShadow(color: AppColors.neonPurple.withOpacity(0.2), blurRadius: 20)],
              ),
              child: Row(
                children: [
                  Text('#${_myRankIndex + 1}', style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900)),
                  const SizedBox(width: 16),
                  Container(
                    width: 48, height: 48,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white.withOpacity(0.2)),
                      image: DecorationImage(image: NetworkImage(_liveRanks[_myRankIndex]['avatar'] ?? _avatar), fit: BoxFit.cover),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        RichText(
                          text: TextSpan(
                            text: (_liveRanks[_myRankIndex]['name'] ?? _userName).toUpperCase(),
                            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 1),
                            children: const [
                              TextSpan(text: ' (YOU)', style: TextStyle(color: AppColors.neonPurple, fontSize: 12))
                            ]
                          )
                        ),
                        const Text('CURRENT POSITION', style: TextStyle(color: AppColors.neonPurple, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 2)),
                      ],
                    ),
                  ),
                  Text('${(_liveRanks[_myRankIndex]['points'] ?? 0).toStringAsFixed(0)} XP',
                    style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900),
                  ),
                ],
              ),
            ),

          Expanded(
            child: _liveRanks.isEmpty
                ? const Center(
                    child: Text('WAITING FOR PLAYERS TO EARN XP...',
                      style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 2),
                    ),
                  )
                : ListView.separated(
                    physics: const BouncingScrollPhysics(),
                    itemCount: _liveRanks.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (ctx, i) {
                      final p = _liveRanks[i];
                      final isOnline = p['isOnline'] ?? true;
                      final isMe = p['userId'] == _userId;

                      Color rankColor = Colors.white54;
                      if (i == 0) rankColor = Colors.amber;
                      else if (i == 1) rankColor = Colors.white;
                      else if (i == 2) rankColor = Colors.orangeAccent;

                      return Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: isMe ? AppColors.neonPurple.withOpacity(0.1) : Colors.white.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: !isOnline ? Colors.red.withOpacity(0.3) 
                                 : isMe ? AppColors.neonPurple.withOpacity(0.5) 
                                 : Colors.white.withOpacity(0.1),
                          ),
                        ),
                        child: Row(
                          children: [
                            Text('#${i + 1}',
                              style: TextStyle(
                                color: rankColor, fontSize: 24, fontWeight: FontWeight.w900,
                                shadows: i == 0 ? [BoxShadow(color: Colors.amber.withOpacity(0.5), blurRadius: 10)] : null,
                              ),
                            ),
                            const SizedBox(width: 16),
                            ColorFiltered(
                              colorFilter: ColorFilter.mode(
                                !isOnline ? Colors.grey : Colors.transparent, 
                                BlendMode.saturation
                              ),
                              child: Container(
                                width: 40, height: 40,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: !isOnline ? Colors.red : Colors.white.withOpacity(0.1)),
                                  image: DecorationImage(image: NetworkImage(p['avatar']), fit: BoxFit.cover),
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  RichText(
                                    text: TextSpan(
                                      text: p['name'].toString().toUpperCase(),
                                      style: TextStyle(
                                        color: !isOnline ? Colors.white54 : Colors.white, 
                                        fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 1,
                                        decoration: !isOnline ? TextDecoration.lineThrough : TextDecoration.none,
                                      ),
                                      children: [
                                        if (isMe) const TextSpan(text: ' (YOU)', style: TextStyle(color: AppColors.neonPurple, fontSize: 10, decoration: TextDecoration.none))
                                      ]
                                    )
                                  ),
                                  if (!isOnline)
                                    const Text('OFFLINE', style: TextStyle(color: Colors.redAccent, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 2)),
                                ],
                              ),
                            ),
                            Text('${(p['points'] ?? 0).toStringAsFixed(0)} XP',
                              style: const TextStyle(color: AppColors.neonPurple, fontSize: 20, fontWeight: FontWeight.w900),
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

  // ── MASTER KEY TAB ───────────────────────────────────────
  Widget _buildMasterKeyTab() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF131022).withOpacity(0.8),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 20)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('MASTER KEY',
            style: TextStyle(color: Colors.tealAccent, fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: 2),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: _fullQuestions.isEmpty
                ? const Center(
                    child: Text('DECRYPTING MASTER KEY DATA...',
                      style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 2),
                    ),
                  )
                : ListView.separated(
                    physics: const BouncingScrollPhysics(),
                    itemCount: _fullQuestions.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (ctx, i) {
                      final q = _fullQuestions[i];
                      final type = q['type'] ?? q['question']?['type'] ?? 'Unknown';
                      final word = q['word'] ?? q['question']?['word'] ?? 'Unknown';
                      final answer = q['answer'] ?? q['question']?['answer'] ?? 'Unknown';
                      final serial = q['serialNo'] ?? (i + 1);

                      return Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.white.withOpacity(0.1)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.black26,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text('Q$serial', style: const TextStyle(color: Colors.white54, fontWeight: FontWeight.w900)),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: RichText(
                                text: TextSpan(
                                  style: const TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w700),
                                  children: [
                                    const TextSpan(text: 'Find the '),
                                    TextSpan(text: type, style: TextStyle(color: type == 'synonym' ? AppColors.neonCyan : AppColors.neonPurple)),
                                    const TextSpan(text: ' of '),
                                    TextSpan(text: word.toString().toUpperCase(), style: const TextStyle(color: Colors.white, decoration: TextDecoration.underline, decorationColor: Colors.white24)),
                                  ],
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              decoration: BoxDecoration(
                                color: Colors.teal.shade900.withOpacity(0.4),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.teal.shade600.withOpacity(0.5)),
                                boxShadow: [BoxShadow(color: Colors.teal.withOpacity(0.2), blurRadius: 10)],
                              ),
                              child: Text(answer.toString().toUpperCase(), style: const TextStyle(color: Colors.tealAccent, fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 1)),
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

  // ── DRAWER (SIDEBAR) ────────────────────────────────────
  Widget _buildDrawer() {
    return Drawer(
      backgroundColor: const Color(0xFF0B0914),
      child: SafeArea(
        child: Column(
          children: [
            // Profile Section
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.05))),
              ),
              child: Row(
                children: [
                  Container(
                    width: 48, height: 48,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white.withOpacity(0.1)),
                      image: DecorationImage(image: NetworkImage(_avatar), fit: BoxFit.cover),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_userName.toUpperCase(),
                          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900),
                        ),
                        Text(widget.isAdmin ? 'SUPERADMIN' : 'PLAYER',
                          style: const TextStyle(color: AppColors.neonCyan, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Navigation Links
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  children: [
                    _buildDrawerItem(0, Icons.sports_esports, 'ARENA', AppColors.neonPurple),
                    _buildDrawerItem(1, Icons.leaderboard, 'RANKS', AppColors.neonCyan),
                    if (widget.isAdmin)
                      _buildDrawerItem(2, Icons.fact_check, 'MASTER KEY', Colors.tealAccent),
                  ],
                ),
              ),
            ),
            
            // Exit Match Button
            Padding(
              padding: const EdgeInsets.all(20),
              child: InkWell(
                onTap: _handleExit,
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    color: AppColors.neonRed.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.neonRed.withOpacity(0.3)),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.logout, color: AppColors.neonRed, size: 20),
                      SizedBox(width: 12),
                      Text('EXIT MATCH', style: TextStyle(color: AppColors.neonRed, fontWeight: FontWeight.w900, letterSpacing: 1, fontSize: 14)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawerItem(int index, IconData icon, String label, Color accent) {
    final active = _activeTab == index;
    return InkWell(
      onTap: () {
        setState(() => _activeTab = index);
        Navigator.pop(context); // close drawer
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          gradient: active ? LinearGradient(colors: [accent.withOpacity(0.2), accent.withOpacity(0.05)]) : null,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: active ? accent.withOpacity(0.5) : Colors.transparent),
        ),
        child: Row(
          children: [
            Icon(icon, color: active ? accent : Colors.white54, size: 24),
            const SizedBox(width: 16),
            Text(label, style: TextStyle(color: active ? Colors.white : Colors.white54, fontWeight: FontWeight.w900, letterSpacing: 1, fontSize: 14)),
          ],
        ),
      ),
    );
  }
}