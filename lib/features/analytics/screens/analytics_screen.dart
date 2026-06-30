// ============================================================
// FILE: lib/features/analytics/screens/analytics_screen.dart
// ============================================================
// NOTE: pubspec.yaml mein add karo:  fl_chart: ^0.69.0

import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../core/constants/app_colors.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen>
    with TickerProviderStateMixin {

  late AnimationController _particleCtrl;
  static const String _baseUrl = 'https://tambola-67o6.onrender.com';

  bool _isLoading = true;
  bool _isSuper   = false;
  String _token   = '';

  List<Map<String, dynamic>> _rawData = [];

  // ── Tabs ─────────────────────────────────────────────────
  int _activeTab = 0; // 0=visuals 1=matches 2=students 3=admins 4=branches 5=sections 6=semesters

  // ── Filters ──────────────────────────────────────────────
  String _branch   = 'ALL';
  String _section  = 'ALL';
  String _semester = 'ALL';
  String _gameMode = 'ALL';
  String _search   = '';
  String _chartGroupBy = 'batch';

  final List<String> _branchOptions   = ['CSE','IT','CS','CSIT','CSE-AI','CSE-AIML','ECE','ELCE','EEE','ME','CSDS','LEGACY'];
  final List<String> _sectionOptions  = ['A','B','C','D','E','LEGACY'];
  final List<String> _semesterOptions = ['1','2','3','4','5','6','7','8','LEGACY'];

  @override
  void initState() {
    super.initState();
    _particleCtrl = AnimationController(
      duration: const Duration(seconds: 6), vsync: this,
    )..repeat();
    _init();
  }

  @override
  void dispose() {
    _particleCtrl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    _token   = prefs.getString('token') ?? '';
    final role = (prefs.getString('role') ?? 'student').toLowerCase();
    setState(() => _isSuper = role == 'superadmin');
    _fetchAnalytics();
  }

  Future<void> _fetchAnalytics() async {
    setState(() => _isLoading = true);
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/api/analytics/query'),
        headers: {
          'Content-Type' : 'application/json',
          'Authorization': 'Bearer $_token',
        },
        body: jsonEncode({
          'page'   : 1,
          'limit'  : 5000,
          'branch' : _branch,
          'section': _section,
          'semester': _semester,
          'gameMode': _gameMode,
          'search' : _search,
          'tab'    : 'matches',
        }),
      );
      final data = jsonDecode(res.body);
      if (data['success'] == true) {
        setState(() {
          _rawData = List<Map<String, dynamic>>.from(
            (data['data']['table'] as List).map((e) => Map<String, dynamic>.from(e as Map)),
          );
        });
      }
    } catch (e) {
      debugPrint('Analytics fetch error: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // ============================================================
  // DATA PROCESSING (mirrors React useMemo logic)
  // ============================================================
  Map<String, dynamic> get _processed {
    final Map<String, Map<String, dynamic>> matchSessions = {};
    final Map<String, Map<String, dynamic>> students = {};
    final Map<String, Map<String, dynamic>> admins = {};
    final Map<String, int> roomFirstPlayed = {};

    for (final log in _rawData) {
      final rCode = log['roomCode'] as String? ?? 'UNKNOWN';
      final time  = DateTime.tryParse(log['playedAt'] as String? ?? '')?.millisecondsSinceEpoch ?? 0;
      if (!roomFirstPlayed.containsKey(rCode) || time < roomFirstPlayed[rCode]!) {
        roomFirstPlayed[rCode] = time;
      }
    }

    for (final log in _rawData) {
      final rCode    = log['roomCode'] as String? ?? 'UNKNOWN';
      final playedAt = log['playedAt'] as String?;
      final dt = DateTime.tryParse(playedAt ?? '');
      final logDate = dt != null ? '${dt.year}-${dt.month}-${dt.day}' : 'UNKNOWN';
      final sessionKey = '${rCode}_$logDate';
      final sName = log['studentName'] as String? ?? 'Anonymous';
      final aName = log['adminName'] as String? ?? 'System Admin';
      final branch = log['branch'] as String? ?? 'LEGACY';
      final section = log['section'] as String? ?? 'LEGACY';
      final semester = log['semester'] as String? ?? 'LEGACY';
      final points = (log['points'] as num?)?.toDouble() ?? 0;
      final accuracy = (log['accuracy'] as num?)?.toDouble() ?? 0;

      final logTime = dt?.millisecondsSinceEpoch ?? 0;
      final isRematch = logTime > ((roomFirstPlayed[rCode] ?? 0) + 43200000);

      matchSessions.putIfAbsent(sessionKey, () => {
        'sessionKey': sessionKey, 'roomCode': rCode, 'date': playedAt,
        'isRematch': isRematch, 'branch': branch, 'section': section,
        'semester': semester, 'gameMode': log['gameMode'] ?? 'lexirush',
        'adminName': aName, 'players': <Map<String,dynamic>>[],
        'questions': log['questions'] ?? [],
      });
      (matchSessions[sessionKey]!['players'] as List).add({
        'playerName': sName, 'points': points, 'accuracy': accuracy,
      });

      students.putIfAbsent(sName, () => {
        'studentName': sName, 'branch': branch, 'section': section, 'semester': semester,
        'totalXP': 0.0, 'totalMatches': 0, 'totalAccAcc': 0.0,
      });
      students[sName]!['totalXP']      = (students[sName]!['totalXP'] as double) + points;
      students[sName]!['totalMatches'] = (students[sName]!['totalMatches'] as int) + 1;
      students[sName]!['totalAccAcc']  = (students[sName]!['totalAccAcc'] as double) + accuracy;

      admins.putIfAbsent(aName, () => {
        'adminName': aName, 'adminEmail': log['adminEmail'] ?? 'N/A',
        'hostedKeys': <String>{}, 'students': <String>{}, 'totalXPGiven': 0.0,
      });
      (admins[aName]!['hostedKeys'] as Set).add(sessionKey);
      (admins[aName]!['students'] as Set).add(sName);
      admins[aName]!['totalXPGiven'] = (admins[aName]!['totalXPGiven'] as double) + points;
    }

    // Finalize matches
    final finalMatches = matchSessions.values.map((session) {
      final players = session['players'] as List<Map<String,dynamic>>;
      final totalPlayers = players.length;
      final totalPoints = players.fold<double>(0, (s, p) => s + (p['points'] as double));
      final totalAcc    = players.fold<double>(0, (s, p) => s + (p['accuracy'] as double));
      final sorted = List<Map<String,dynamic>>.from(players)
        ..sort((a, b) => (b['points'] as double).compareTo(a['points'] as double));
      for (int i = 0; i < sorted.length; i++) {
        sorted[i]['rank'] = i + 1;
      }
      return {
        ...session,
        'totalPlayers': totalPlayers,
        'avgScore'   : totalPlayers > 0 ? double.parse((totalPoints / totalPlayers).toStringAsFixed(1)) : 0.0,
        'avgAccuracy': totalPlayers > 0 ? double.parse((totalAcc / totalPlayers).toStringAsFixed(1)) : 0.0,
        'leaderboard': sorted,
      };
    }).toList()
      ..sort((a, b) => (DateTime.tryParse(b['date'] as String? ?? '') ?? DateTime(0))
          .compareTo(DateTime.tryParse(a['date'] as String? ?? '') ?? DateTime(0)));

    final finalStudents = students.values.map((s) => {
      ...s,
      'avgAccuracy': (s['totalMatches'] as int) > 0
          ? double.parse(((s['totalAccAcc'] as double) / (s['totalMatches'] as int)).toStringAsFixed(1))
          : 0.0,
    }).toList()
      ..sort((a, b) => (b['totalXP'] as double).compareTo(a['totalXP'] as double));

    final finalAdmins = admins.values.map((a) => {
      ...a,
      'totalHostedCount'  : (a['hostedKeys'] as Set).length,
      'totalStudentsCount': (a['students'] as Set).length,
    }).toList()
      ..sort((a, b) => (b['totalHostedCount'] as int).compareTo(a['totalHostedCount'] as int));

    return {'matches': finalMatches, 'students': finalStudents, 'admins': finalAdmins};
  }

  List<Map<String, dynamic>> get _filteredMatches {
    final matches = List<Map<String,dynamic>>.from(_processed['matches'] as List);
    if (_search.isEmpty) return matches;
    final q = _search.toLowerCase();
    return matches.where((m) =>
    (m['roomCode'] as String).toLowerCase().contains(q) ||
        (m['adminName'] as String).toLowerCase().contains(q)
    ).toList();
  }

  Map<String, dynamic> get _kpis {
    final matches = _filteredMatches;
    int totalStudents = 0;
    double sumScore = 0, sumAcc = 0;
    for (final m in matches) {
      totalStudents += m['totalPlayers'] as int;
      sumScore += m['avgScore'] as double;
      sumAcc   += m['avgAccuracy'] as double;
    }
    return {
      'matches': matches.length,
      'totalStudents': totalStudents,
      'avgScore': matches.isNotEmpty ? (sumScore / matches.length).toStringAsFixed(1) : '0',
      'avgAcc'  : matches.isNotEmpty ? (sumAcc / matches.length).toStringAsFixed(1) : '0',
    };
  }

  List<Map<String, dynamic>> get _chartData {
    final groups = <String, Map<String, dynamic>>{};
    for (final session in _filteredMatches) {
      String key = 'Unknown';
      final branch   = session['branch'] as String;
      final section  = session['section'] as String;
      final semester = session['semester'] as String;
      final gameMode = session['gameMode'] as String;

      if (_chartGroupBy == 'batch') {
        key = branch == 'LEGACY' ? 'Legacy' : '$branch-S$section-Sem$semester';
      } else if (_chartGroupBy == 'branch') {
        key = branch;
      } else if (_chartGroupBy == 'section') {
        key = 'Sec $section';
      } else if (_chartGroupBy == 'semester') {
        key = 'Sem $semester';
      } else if (_chartGroupBy == 'gameMode') {
        key = gameMode == 'spell_shooter' ? 'Shooter' : 'LexiRush';
      }

      groups.putIfAbsent(key, () => {'name': key, 'totalPoints': 0.0, 'totalAcc': 0.0, 'count': 0});
      groups[key]!['totalPoints'] = (groups[key]!['totalPoints'] as double) + (session['avgScore'] as double);
      groups[key]!['totalAcc']    = (groups[key]!['totalAcc'] as double) + (session['avgAccuracy'] as double);
      groups[key]!['count']       = (groups[key]!['count'] as int) + 1;
    }

    final list = groups.values.map((g) {
      final count = g['count'] as int;
      return {
        'name'    : g['name'],
        'Volume'  : count,
        'Score'   : count > 0 ? double.parse(((g['totalPoints'] as double) / count).toStringAsFixed(1)) : 0.0,
        'Accuracy': count > 0 ? double.parse(((g['totalAcc'] as double) / count).toStringAsFixed(1)) : 0.0,
      };
    }).toList()
      ..sort((a, b) => (b['Volume'] as int).compareTo(a['Volume'] as int));

    return list.take(8).toList(); // limit for mobile readability
  }

  void _resetFilters() {
    setState(() {
      _branch = 'ALL'; _section = 'ALL'; _semester = 'ALL'; _gameMode = 'ALL'; _search = '';
    });
    _fetchAnalytics();
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
                _buildFiltersBar(),
                _buildTabs(),
                Expanded(child: _buildTabContent()),
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
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          Icon(Icons.dashboard_rounded, color: AppColors.neonCyan, size: 20),
          const SizedBox(width: 8),
          const Text('COMMAND CENTER',
            style: TextStyle(
              color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 1.5,
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: _fetchAnalytics,
            child: Icon(Icons.refresh_rounded, color: Colors.white.withOpacity(0.4), size: 20),
          ),
        ],
      ),
    );
  }

  // ── FILTERS ──────────────────────────────────────────────
  Widget _buildFiltersBar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.bgCard.withOpacity(0.8),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        children: [
          // Search
          Container(
            decoration: BoxDecoration(
              color: AppColors.bgDeep,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white.withOpacity(0.08)),
            ),
            child: TextField(
              onChanged: (v) => setState(() => _search = v),
              onSubmitted: (_) => _fetchAnalytics(),
              style: const TextStyle(color: Colors.white, fontSize: 12),
              decoration: InputDecoration(
                hintText: 'Search & hit enter...',
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 12),
                prefixIcon: Icon(Icons.search, color: Colors.white.withOpacity(0.3), size: 18),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
          const SizedBox(height: 10),

          // Filter chips row
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                if (!_isSuper) ...[
                  _buildFilterDropdown('Branch', _branch, ['ALL', ..._branchOptions],
                          (v) { setState(() => _branch = v); _fetchAnalytics(); }),
                  const SizedBox(width: 8),
                  _buildFilterDropdown('Section', _section, ['ALL', ..._sectionOptions],
                          (v) { setState(() => _section = v); _fetchAnalytics(); }),
                  const SizedBox(width: 8),
                  _buildFilterDropdown('Sem', _semester, ['ALL', ..._semesterOptions],
                          (v) { setState(() => _semester = v); _fetchAnalytics(); }),
                  const SizedBox(width: 8),
                ],
                _buildFilterDropdown('Mode', _gameMode, ['ALL', 'lexirush', 'spell_shooter'],
                        (v) { setState(() => _gameMode = v); _fetchAnalytics(); }),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _resetFilters,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.neonRed.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.neonRed.withOpacity(0.3)),
                    ),
                    child: Text('CLEAR',
                      style: TextStyle(color: AppColors.neonRed, fontSize: 10, fontWeight: FontWeight.w800),
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

  Widget _buildFilterDropdown(String label, String value, List<String> options, ValueChanged<String> onChanged) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.bgDeep,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.neonCyan.withOpacity(0.3)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          dropdownColor: AppColors.bgCard,
          isDense: true,
          style: TextStyle(color: AppColors.neonCyan, fontSize: 10, fontWeight: FontWeight.w700),
          icon: Icon(Icons.arrow_drop_down, color: AppColors.neonCyan, size: 16),
          items: options.map((o) => DropdownMenuItem(
            value: o,
            child: Text(o == 'ALL' ? 'All $label' : o),
          )).toList(),
          onChanged: (v) { if (v != null) onChanged(v); },
        ),
      ),
    );
  }

  // ── TABS ─────────────────────────────────────────────────
  Widget _buildTabs() {
    final tabs = [
      {'icon': Icons.insights_rounded, 'label': 'Visuals', 'color': const Color(0xFF3B82F6)},
      {'icon': Icons.sports_esports_rounded, 'label': 'Matches', 'color': AppColors.neonCyan},
      {'icon': Icons.school_rounded, 'label': 'Students', 'color': AppColors.neonGreen},
      if (_isSuper)
        {'icon': Icons.admin_panel_settings_rounded, 'label': 'Admins', 'color': AppColors.neonPurple},
      {'icon': Icons.account_tree_rounded, 'label': 'Branches', 'color': const Color(0xFFF97316)},
      {'icon': Icons.view_module_rounded, 'label': 'Sections', 'color': const Color(0xFFEC4899)},
      {'icon': Icons.calendar_view_month_rounded, 'label': 'Semesters', 'color': const Color(0xFF6366F1)},
    ];

    return Container(
      height: 44,
      margin: const EdgeInsets.symmetric(vertical: 10),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: tabs.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final t = tabs[i];
          final isActive = _activeTab == i;
          final color = t['color'] as Color;
          return GestureDetector(
            onTap: () => setState(() => _activeTab = i),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: isActive ? color.withOpacity(0.15) : AppColors.bgCard.withOpacity(0.6),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: isActive ? color.withOpacity(0.5) : Colors.white.withOpacity(0.06)),
              ),
              child: Row(
                children: [
                  Icon(t['icon'] as IconData, size: 14, color: isActive ? color : Colors.white38),
                  const SizedBox(width: 6),
                  Text(t['label'] as String,
                    style: TextStyle(
                      color: isActive ? color : Colors.white38,
                      fontSize: 11, fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ── TAB CONTENT ROUTER ───────────────────────────────────
  Widget _buildTabContent() {
    if (_isLoading) {
      return Center(
        child: CircularProgressIndicator(color: AppColors.neonCyan, strokeWidth: 3),
      );
    }

    switch (_activeTab) {
      case 0: return _buildVisualsTab();
      case 1: return _buildMatchesTab();
      case 2: return _buildStudentsTab();
      case 3: return _isSuper ? _buildAdminsTab() : _buildBranchesTab();
      case 4: return _isSuper ? _buildBranchesTab() : _buildSectionsTab();
      case 5: return _isSuper ? _buildSectionsTab() : _buildSemestersTab();
      case 6: return _buildSemestersTab();
      default: return _buildVisualsTab();
    }
  }

  // ── VISUALS TAB ──────────────────────────────────────────
  Widget _buildVisualsTab() {
    final kpis = _kpis;
    final chartData = _chartData;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      children: [
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 1.6,
          children: [
            _buildKpiCard('GLOBAL MATCHES', '${kpis['matches']}', Colors.white),
            _buildKpiCard('TOTAL PLAYERS', '${kpis['totalStudents']}', Colors.white),
            _buildKpiCard('MEAN XP', '${kpis['avgScore']}', AppColors.neonCyan),
            _buildKpiCard('MEAN ACCURACY', '${kpis['avgAcc']}%', AppColors.neonGreen),
          ],
        ),

        const SizedBox(height: 18),

        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.bgCard.withOpacity(0.8),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withOpacity(0.06)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('DATA SEGREGATION',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.5),
                      fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1,
                    ),
                  ),
                  _buildFilterDropdown('Group', _chartGroupBy,
                    ['batch','branch','section','semester','gameMode'],
                        (v) => setState(() => _chartGroupBy = v),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              if (chartData.isEmpty)
                Container(
                  height: 200,
                  alignment: Alignment.center,
                  child: Text('NO VISUAL DATA',
                    style: TextStyle(color: Colors.white.withOpacity(0.2), fontWeight: FontWeight.w800, letterSpacing: 2),
                  ),
                )
              else
                SizedBox(
                  height: 260,
                  child: _buildComboChart(chartData),
                ),

              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _legendDot(AppColors.neonCyan, 'Mean XP'),
                  const SizedBox(width: 16),
                  _legendDot(AppColors.neonGreen, 'Accuracy %'),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 10, fontWeight: FontWeight.w700)),
      ],
    );
  }

  Widget _buildComboChart(List<Map<String, dynamic>> data) {
    final maxScore = data.map((d) => d['Score'] as double).fold(0.0, math.max);
    final barMax = maxScore < 10 ? 10.0 : maxScore * 1.3;

    return BarChart(
      BarChartData(
        maxY: barMax,
        gridData: FlGridData(
          show: true, drawVerticalLine: false,
          getDrawingHorizontalLine: (_) => FlLine(color: Colors.white.withOpacity(0.06), strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true, reservedSize: 32,
              getTitlesWidget: (v, _) => Text(v.toInt().toString(),
                  style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 9)),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true, reservedSize: 36,
              getTitlesWidget: (v, _) {
                final i = v.toInt();
                if (i < 0 || i >= data.length) return const SizedBox();
                final name = data[i]['name'] as String;
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Transform.rotate(
                    angle: -0.5,
                    child: Text(
                      name.length > 8 ? '${name.substring(0, 8)}…' : name,
                      style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 8),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        barGroups: List.generate(data.length, (i) {
          final score = data[i]['Score'] as double;
          return BarChartGroupData(
            x: i,
            barRods: [
              BarChartRodData(
                toY: score,
                color: AppColors.neonCyan,
                width: 16,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
              ),
            ],
          );
        }),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => AppColors.bgDeep,
            getTooltipItem: (group, _, rod, __) {
              final d = data[group.x.toInt()];
              return BarTooltipItem(
                '${d['name']}\nXP: ${d['Score']}\nAcc: ${d['Accuracy']}%',
                const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildKpiCard(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.bgCard.withOpacity(0.8),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
            style: TextStyle(
              color: Colors.white.withOpacity(0.35),
              fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 1,
            ),
          ),
          const Spacer(),
          Text(value,
            style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 24),
          ),
        ],
      ),
    );
  }

  // ── MATCHES TAB ──────────────────────────────────────────
  Widget _buildMatchesTab() {
    final matches = _filteredMatches;
    if (matches.isEmpty) return _emptyState('No matches found');

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      itemCount: matches.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final m = matches[i];
        final date = DateTime.tryParse(m['date'] as String? ?? '');
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.bgCard.withOpacity(0.8),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withOpacity(0.06)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(m['roomCode'] as String,
                    style: TextStyle(color: AppColors.neonCyan, fontWeight: FontWeight.w900, fontSize: 14),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: (m['isRematch'] == true ? Colors.orange : Colors.blue).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(m['isRematch'] == true ? 'REMATCH' : 'ORIGINAL',
                      style: TextStyle(
                        color: m['isRematch'] == true ? Colors.orange : Colors.blue,
                        fontSize: 8, fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text('${m['avgScore']} XP',
                    style: TextStyle(color: AppColors.neonGreen, fontWeight: FontWeight.w800, fontSize: 13),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '${date != null ? "${date.day}/${date.month}/${date.year}" : ""} • ${m['gameMode'] == 'spell_shooter' ? 'Shooter' : 'LexiRush'}',
                style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 10),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Text(
                    m['branch'] == 'LEGACY' ? 'Legacy' : '${m['branch']} / Sec ${m['section']} / Sem ${m['semester']}',
                    style: TextStyle(color: Colors.white.withOpacity(0.45), fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  Text('${m['totalPlayers']} players • ${m['avgAccuracy']}%',
                    style: TextStyle(color: const Color(0xFFFBBF24).withOpacity(0.8), fontSize: 10, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  // ── STUDENTS TAB ─────────────────────────────────────────
  Widget _buildStudentsTab() {
    final students = List<Map<String,dynamic>>.from(_processed['students'] as List);
    if (students.isEmpty) return _emptyState('No students found');

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      itemCount: students.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final s = students[i];
        final medal = i == 0 ? '🥇' : i == 1 ? '🥈' : i == 2 ? '🥉' : null;
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.bgCard.withOpacity(0.8),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withOpacity(0.06)),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 30,
                child: medal != null
                    ? Text(medal, style: const TextStyle(fontSize: 18))
                    : Text('#${i + 1}', style: TextStyle(color: Colors.white.withOpacity(0.3), fontWeight: FontWeight.w800)),
              ),
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: AppColors.neonGreen.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.neonGreen.withOpacity(0.3)),
                ),
                child: Icon(Icons.person_rounded, color: AppColors.neonGreen, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s['studentName'] as String,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      s['branch'] == 'LEGACY' ? 'Legacy' : '${s['branch']}-S${s['section']}-Sem${s['semester']}',
                      style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 9),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('${s['totalXP']}',
                    style: TextStyle(color: AppColors.neonCyan, fontWeight: FontWeight.w900, fontSize: 15),
                  ),
                  Text('${s['totalMatches']} games • ${s['avgAccuracy']}%',
                    style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 9),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  // ── ADMINS TAB ───────────────────────────────────────────
  Widget _buildAdminsTab() {
    final admins = List<Map<String,dynamic>>.from(_processed['admins'] as List);
    if (admins.isEmpty) return _emptyState('No administrators found');

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      itemCount: admins.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final a = admins[i];
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.bgCard.withOpacity(0.8),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withOpacity(0.06)),
          ),
          child: Row(
            children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: AppColors.neonPurple.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.neonPurple.withOpacity(0.3)),
                ),
                child: Icon(Icons.admin_panel_settings_rounded, color: AppColors.neonPurple, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(a['adminName'] as String,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12),
                    ),
                    Text(a['adminEmail'] as String? ?? 'N/A',
                      style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 9),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('${a['totalHostedCount']} hosted',
                    style: TextStyle(color: AppColors.neonCyan, fontWeight: FontWeight.w800, fontSize: 11),
                  ),
                  Text('${a['totalStudentsCount']} students • ${a['totalXPGiven']} XP',
                    style: TextStyle(color: const Color(0xFFF97316).withOpacity(0.8), fontSize: 9, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  // ── COHORT TABS (branches/sections/semesters) ────────────
  Widget _buildCohortTab(String groupKeyType) {
    final matches = _filteredMatches;
    final Map<String, Map<String,dynamic>> cohorts = {};

    for (final m in matches) {
      String key;
      if (groupKeyType == 'branch') {
        key = m['branch'] as String;
      } else if (groupKeyType == 'section') {
        key = '${m['branch']} - Sec ${m['section']}';
      } else {
        key = '${m['branch']} - Sem ${m['semester']}';
      }
      cohorts.putIfAbsent(key, () => {'name': key, 'matchCount': 0, 'players': 0, 'xp': 0.0, 'acc': 0.0});
      cohorts[key]!['matchCount'] = (cohorts[key]!['matchCount'] as int) + 1;
      cohorts[key]!['players']    = (cohorts[key]!['players'] as int) + (m['totalPlayers'] as int);
      cohorts[key]!['xp']         = (cohorts[key]!['xp'] as double) + (m['avgScore'] as double);
      cohorts[key]!['acc']        = (cohorts[key]!['acc'] as double) + (m['avgAccuracy'] as double);
    }

    final list = cohorts.values.map((c) {
      final count = c['matchCount'] as int;
      return {
        ...c,
        'avgScore'   : count > 0 ? ((c['xp'] as double) / count).toStringAsFixed(1) : '0',
        'avgAccuracy': count > 0 ? ((c['acc'] as double) / count).toStringAsFixed(1) : '0',
      };
    }).toList()
      ..sort((a, b) => double.parse(b['avgScore'] as String).compareTo(double.parse(a['avgScore'] as String)));

    if (list.isEmpty) return _emptyState('No cohorts found');

    final icon = groupKeyType == 'branch'
        ? Icons.account_tree_rounded
        : groupKeyType == 'section'
        ? Icons.view_module_rounded
        : Icons.calendar_view_month_rounded;
    final color = groupKeyType == 'branch'
        ? const Color(0xFFF97316)
        : groupKeyType == 'section'
        ? const Color(0xFFEC4899)
        : const Color(0xFF6366F1);

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      itemCount: list.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final c = list[i];
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.bgCard.withOpacity(0.8),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withOpacity(0.06)),
          ),
          child: Row(
            children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: color.withOpacity(0.3)),
                ),
                child: Icon(icon, color: color, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c['name'] as String,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12),
                    ),
                    Text('${c['matchCount']} matches • ${c['players']} players',
                      style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 9),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('${c['avgScore']} XP',
                    style: TextStyle(color: AppColors.neonGreen, fontWeight: FontWeight.w800, fontSize: 12),
                  ),
                  Text('${c['avgAccuracy']}%',
                    style: TextStyle(color: const Color(0xFFFBBF24).withOpacity(0.8), fontSize: 10, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBranchesTab()  => _buildCohortTab('branch');
  Widget _buildSectionsTab()  => _buildCohortTab('section');
  Widget _buildSemestersTab() => _buildCohortTab('semester');

  Widget _emptyState(String msg) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.inbox_rounded, color: Colors.white.withOpacity(0.15), size: 50),
          const SizedBox(height: 12),
          Text(msg.toUpperCase(),
            style: TextStyle(color: Colors.white.withOpacity(0.25), fontWeight: FontWeight.w800, letterSpacing: 1.5),
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
    final rng = math.Random(55);
    for (int i = 0; i < 20; i++) {
      final x     = rng.nextDouble() * size.width;
      final baseY = rng.nextDouble() * size.height;
      final speed = 0.3 + rng.nextDouble() * 1.0;
      final y     = (baseY - t * size.height * speed) % size.height;
      final rad   = 1.0 + rng.nextDouble() * 2.0;
      final op    = 0.04 + rng.nextDouble() * 0.12;
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
      ..color = AppColors.neonCyan.withOpacity(0.02)
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