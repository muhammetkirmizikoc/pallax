import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'package:fl_chart/fl_chart.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('tr_TR', null);
  runApp(const TuyapApp());
}

class ThemeModeProvider extends ChangeNotifier {
  bool _isDarkMode = false;
  bool _showGraphs = true;
  SharedPreferences? _prefs;

  bool get isDarkMode => _isDarkMode;
  bool get showGraphs => _showGraphs;

  ThemeModeProvider() {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    _prefs = await SharedPreferences.getInstance();
    _isDarkMode = _prefs?.getBool('isDarkMode') ?? false;
    _showGraphs = _prefs?.getBool('showGraphs') ?? true;
    notifyListeners();
  }

  Future<void> toggleTheme() async {
    _isDarkMode = !_isDarkMode;
    await _prefs?.setBool('isDarkMode', _isDarkMode);
    notifyListeners();
  }

  Future<void> toggleGraphs() async {
    _showGraphs = !_showGraphs;
    await _prefs?.setBool('showGraphs', _showGraphs);
    notifyListeners();
  }
}

class TransactionEntry {
  final double amount;
  final bool isIncome;
  final String description;
  final DateTime timestamp;

  TransactionEntry({
    required this.amount,
    required this.isIncome,
    required this.description,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
    'amount': amount,
    'isIncome': isIncome,
    'description': description,
    'timestamp': timestamp.toIso8601String(),
  };

  factory TransactionEntry.fromJson(Map<String, dynamic> json) => TransactionEntry(
    amount: json['amount'],
    isIncome: json['isIncome'],
    description: json['description'],
    timestamp: DateTime.parse(json['timestamp']),
  );
}

class TuyapData extends ChangeNotifier {
  double totalIncome = 0.0;
  double todayIncome = 0.0;
  String lastAdditionTime = '';
  List<TransactionEntry> transactionHistory = [];
  SharedPreferences? _prefs;

  TuyapData() {
    _loadData();
  }

  Future<void> _loadData() async {
    _prefs = await SharedPreferences.getInstance();
    totalIncome = _prefs?.getDouble('totalIncome') ?? 0.0;
    todayIncome = _prefs?.getDouble('todayIncome') ?? 0.0;
    lastAdditionTime = _prefs?.getString('lastAdditionTime') ?? DateFormat('HH:mm').format(DateTime.now());
    
    final String? transactionsJson = _prefs?.getString('transactionHistory');
    if (transactionsJson != null && transactionsJson.isNotEmpty) {
      try {
        transactionHistory = (json.decode(transactionsJson) as List)
            .map((item) => TransactionEntry.fromJson(item))
            .toList();
      } catch (e) {
        transactionHistory = [];
      }
    }
    notifyListeners();
  }

  Future<void> _saveData() async {
    await _prefs?.setDouble('totalIncome', totalIncome);
    await _prefs?.setDouble('todayIncome', todayIncome);
    await _prefs?.setString('lastAdditionTime', lastAdditionTime);
    await _prefs?.setString('transactionHistory', 
        json.encode(transactionHistory.map((t) => t.toJson()).toList()));
  }

  void addIncome(double amount, String description) {
    totalIncome += amount;
    todayIncome += amount;
    lastAdditionTime = DateFormat('HH:mm').format(DateTime.now());
    transactionHistory.insert(0, TransactionEntry(
      amount: amount,
      isIncome: true,
      description: description,
      timestamp: DateTime.now(),
    ));
    if (transactionHistory.length > 100) {
      transactionHistory = transactionHistory.sublist(0, 100);
    }
    _saveData();
    notifyListeners();
  }

  void removeIncome(double amount, String description) {
    totalIncome = (totalIncome - amount).clamp(0.0, double.infinity);
    todayIncome = (todayIncome - amount).clamp(0.0, double.infinity);
    lastAdditionTime = DateFormat('HH:mm').format(DateTime.now());
    transactionHistory.insert(0, TransactionEntry(
      amount: amount,
      isIncome: false,
      description: description,
      timestamp: DateTime.now(),
    ));
    if (transactionHistory.length > 100) {
      transactionHistory = transactionHistory.sublist(0, 100);
    }
    _saveData();
    notifyListeners();
  }

  Future<void> clearAllData() async {
    totalIncome = 0.0;
    todayIncome = 0.0;
    lastAdditionTime = DateFormat('HH:mm').format(DateTime.now());
    transactionHistory = [];
    await _prefs?.clear();
    notifyListeners();
  }

  Map<int, double> getWeeklyData() {
    final now = DateTime.now();
    final weeklyData = <int, double>{};
    
    // Pazartesi'yi bul (haftanın başlangıcı)
    final monday = now.subtract(Duration(days: now.weekday - 1));
    
    double runningTotal = 0.0;
    
    for (int i = 0; i < 7; i++) {
      final date = monday.add(Duration(days: i));
      final dayTransactions = transactionHistory.where((t) =>
          t.timestamp.year == date.year &&
          t.timestamp.month == date.month &&
          t.timestamp.day == date.day);
      
      // Her günün net değerini hesapla ve birikimli toplama ekle
      final dayNet = dayTransactions.fold(0.0, (sum, t) {
        return sum + (t.isIncome ? t.amount : -t.amount);
      });
      
      runningTotal += dayNet;
      weeklyData[i] = runningTotal;
    }
    return weeklyData;
  }

  Map<int, double> getMonthlyData() {
    final now = DateTime.now();
    final monthlyData = <int, double>{};
    
    double runningTotal = 0.0;
    
    for (int i = 0; i < 30; i++) {
      final date = now.subtract(Duration(days: 29 - i));
      final dayTransactions = transactionHistory.where((t) =>
          t.timestamp.year == date.year &&
          t.timestamp.month == date.month &&
          t.timestamp.day == date.day);
      
      // Her günün net değerini hesapla ve birikimli toplama ekle
      final dayNet = dayTransactions.fold(0.0, (sum, t) {
        return sum + (t.isIncome ? t.amount : -t.amount);
      });
      
      runningTotal += dayNet;
      monthlyData[i] = runningTotal;
    }
    return monthlyData;
  }

  Map<int, double> getAllTimeData() {
    if (transactionHistory.isEmpty) return {};
    
    final monthlyTotals = <String, double>{};
    
    // Her ay için net değeri hesapla
    for (var t in transactionHistory) {
      final key = DateFormat('yyyy-MM').format(t.timestamp);
      monthlyTotals[key] = (monthlyTotals[key] ?? 0) + (t.isIncome ? t.amount : -t.amount);
    }
    
    final sortedKeys = monthlyTotals.keys.toList()..sort();
    
    // Birikimli toplam hesapla
    double runningTotal = 0.0;
    final cumulativeData = <int, double>{};
    
    for (int i = 0; i < sortedKeys.length; i++) {
      runningTotal += monthlyTotals[sortedKeys[i]]!;
      cumulativeData[i] = runningTotal;
    }
    
    return cumulativeData;
  }
}

class TuyapApp extends StatelessWidget {
  const TuyapApp({super.key});

  @override
  Widget build(BuildContext context) {
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => TuyapData()),
        ChangeNotifierProvider(create: (_) => ThemeModeProvider()),
      ],
      child: Consumer<ThemeModeProvider>(
        builder: (context, themeProvider, _) => MaterialApp(
          title: 'Tuyap Gelir Takip',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            primarySwatch: Colors.blue,
            useMaterial3: true,
            brightness: themeProvider.isDarkMode ? Brightness.dark : Brightness.light,
            scaffoldBackgroundColor: themeProvider.isDarkMode 
                ? const Color(0xFF1C1C1E) 
                : const Color(0xFFF5F5F7),
          ),
          home: const HomeScreen(),
        ),
      ),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final tuyapData = context.watch<TuyapData>();
    final themeProvider = context.watch<ThemeModeProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            ListView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.only(bottom: 100),
              children: [
                _HeaderWidget(),
                const SizedBox(height: 10),
                _TotalIncomeCard(totalIncome: tuyapData.totalIncome),
                const SizedBox(height: 16),
                if (themeProvider.showGraphs) ...[
                  _ChartCard(tuyapData: tuyapData),
                  const SizedBox(height: 16),
                ],
                _CombinedInfoCard(
                  todayIncome: tuyapData.todayIncome,
                  totalIncome: tuyapData.totalIncome,
                  transactions: tuyapData.transactionHistory.take(10).toList(),
                ),
              ],
            ),
            const _BottomNavBar(),
          ],
        ),
      ),
    );
  }
}

class _HeaderWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final themeProvider = context.read<ThemeModeProvider>();
    final now = DateTime.now();
    final dateText = DateFormat('d MMMM', 'tr_TR').format(now);
    final dayText = DateFormat('EEEE', 'tr_TR').format(now);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(dateText, style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : const Color(0xFF1C1C1E),
              )),
              const SizedBox(height: 4),
              Text(dayText, style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.grey[400] : Colors.grey[600],
              )),
            ],
          ),
          Row(
            children: [
              _IconButton(
                icon: isDark ? Icons.light_mode : Icons.dark_mode,
                onTap: themeProvider.toggleTheme,
                isDark: isDark,
              ),
              const SizedBox(width: 10),
              _IconButton(
                icon: Icons.settings_outlined,
                onTap: () => Navigator.push(context, 
                    MaterialPageRoute(builder: (_) => const SettingsScreen())),
                isDark: isDark,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _IconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool isDark;

  const _IconButton({required this.icon, required this.onTap, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF2C2C2E) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.2 : 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          )],
        ),
        child: Icon(icon, color: isDark ? Colors.grey[400] : Colors.grey[700], size: 22),
      ),
    );
  }
}

class _TotalIncomeCard extends StatelessWidget {
  final double totalIncome;
  const _TotalIncomeCard({required this.totalIncome});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2C2C2E), Color(0xFF1e3a5f)],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(
          color: Colors.black.withOpacity(0.1),
          blurRadius: 16,
          offset: const Offset(0, 4),
        )],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Toplam Kazancınız', style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.grey[400],
              )),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.trending_up, color: Colors.white, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text('₺${NumberFormat('#,##0', 'tr_TR').format(totalIncome)}',
              style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold, 
                  color: Colors.white)),
        ],
      ),
    );
  }
}

class _ChartCard extends StatefulWidget {
  final TuyapData tuyapData;
  const _ChartCard({required this.tuyapData});

  @override
  State<_ChartCard> createState() => _ChartCardState();
}

class _ChartCardState extends State<_ChartCard> {
  int _period = 0;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    Map<int, double> data;
    String title;
    List<String> labels;

    switch (_period) {
      case 0:
        data = widget.tuyapData.getWeeklyData();
        title = 'Bu Hafta';
        labels = List.generate(7, (i) {
          final now = DateTime.now();
          final monday = now.subtract(Duration(days: now.weekday - 1));
          final date = monday.add(Duration(days: i));
          return DateFormat('EEE', 'tr_TR').format(date).substring(0, 3);
        });
        break;
      case 1:
        data = widget.tuyapData.getMonthlyData();
        title = 'Son 30 Gün';
        labels = List.generate(6, (i) {
          final date = DateTime.now().subtract(Duration(days: 29 - (i * 5)));
          return DateFormat('d').format(date);
        });
        break;
      default:
        data = widget.tuyapData.getAllTimeData();
        title = 'Tüm Zamanlar';
        labels = [];
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF2C2C2E), Color(0xFF1e3a5f)]),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(
          color: Colors.black.withOpacity(0.1),
          blurRadius: 16,
          offset: const Offset(0, 4),
        )],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF007AFF).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.bar_chart, color: Color(0xFF007AFF), size: 20),
              ),
              const SizedBox(width: 12),
              Text(title, style: const TextStyle(
                fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(child: _PeriodButton('Haftalık', 0, _period == 0, 
                    () => setState(() => _period = 0))),
                Expanded(child: _PeriodButton('Aylık', 1, _period == 1, 
                    () => setState(() => _period = 1))),
                Expanded(child: _PeriodButton('Tüm', 2, _period == 2, 
                    () => setState(() => _period = 2))),
              ],
            ),
          ),
          const SizedBox(height: 20),
          data.isEmpty
              ? const SizedBox(height: 200, child: Center(
                  child: Text('Henüz veri yok', 
                      style: TextStyle(color: Colors.grey, fontSize: 16))))
              : SizedBox(
                  height: 200,
                  child: LineChart(LineChartData(
                    gridData: FlGridData(
                      show: true,
                      drawVerticalLine: false,
                      getDrawingHorizontalLine: (value) {
                        if (value == 0) {
                          return FlLine(
                            color: Colors.white.withOpacity(0.5),
                            strokeWidth: 2,
                            dashArray: [5, 5],
                          );
                        }
                        return FlLine(
                          color: Colors.white.withOpacity(0.1),
                          strokeWidth: 1,
                        );
                      },
                    ),
                    titlesData: FlTitlesData(
                      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      bottomTitles: AxisTitles(sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 30,
                        getTitlesWidget: (value, meta) {
                          final idx = value.toInt();
                          if (idx < 0 || idx >= labels.length) return const Text('');
                          return Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(labels[idx],
                                style: TextStyle(color: Colors.grey[400], fontSize: 10)),
                          );
                        },
                      )),
                      leftTitles: AxisTitles(sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 40,
                        getTitlesWidget: (value, meta) => Text(
                          value >= 1000 ? '${(value/1000).toStringAsFixed(0)}k' 
                                        : value.toStringAsFixed(0),
                          style: TextStyle(color: Colors.grey[400], fontSize: 10),
                        ),
                      )),
                    ),
                    borderData: FlBorderData(show: false),
                    minX: 0,
                    maxX: (data.length - 1).toDouble(),
                    minY: data.values.isEmpty ? 0 : (data.values.reduce((a, b) => a < b ? a : b) < 0 
                        ? data.values.reduce((a, b) => a < b ? a : b) * 1.2 
                        : 0),
                    maxY: data.values.isEmpty ? 100 : (data.values.reduce((a, b) => a > b ? a : b) > 0 
                        ? data.values.reduce((a, b) => a > b ? a : b) * 1.2 
                        : 0),
                    lineBarsData: [
                      LineChartBarData(
                        spots: data.entries.map((e) => FlSpot(e.key.toDouble(), e.value)).toList(),
                        isCurved: true,
                        gradient: const LinearGradient(
                            colors: [Color(0xFF34C759), Color(0xFF007AFF)]),
                        barWidth: 3,
                        dotData: const FlDotData(show: true),
                        belowBarData: BarAreaData(
                          show: true,
                          gradient: LinearGradient(
                            colors: [
                              const Color(0xFF34C759).withOpacity(0.3),
                              const Color(0xFF34C759).withOpacity(0.0),
                            ],
                          ),
                        ),
                      ),
                    ],
                    lineTouchData: LineTouchData(
                      touchTooltipData: LineTouchTooltipData(
                        tooltipBgColor: const Color(0xFF2C2C2E),
                        getTooltipItems: (spots) => spots.map((spot) => LineTooltipItem(
                          '₺${NumberFormat('#,##0', 'tr_TR').format(spot.y)}',
                          const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        )).toList(),
                      ),
                    ),
                  )),
                ),
        ],
      ),
    );
  }
}

class _PeriodButton extends StatelessWidget {
  final String label;
  final int index;
  final bool isSelected;
  final VoidCallback onTap;

  const _PeriodButton(this.label, this.index, this.isSelected, this.onTap);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white.withOpacity(0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            color: isSelected ? Colors.white : Colors.grey[400],
          ),
        ),
      ),
    );
  }
}

class _CombinedInfoCard extends StatelessWidget {
  final double todayIncome;
  final double totalIncome;
  final List<TransactionEntry> transactions;

  const _CombinedInfoCard({
    required this.todayIncome,
    required this.totalIncome,
    required this.transactions,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF2C2C2E), Color(0xFF1e3a5f)]),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(
          color: Colors.black.withOpacity(0.1),
          blurRadius: 10,
          offset: const Offset(0, 2),
        )],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(
                color: Colors.white.withOpacity(0.1), width: 1)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF34C759).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.today_outlined, color: Color(0xFF34C759), size: 24),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Bugünkü Kazanç', style: TextStyle(
                        fontSize: 14, color: Colors.grey[400])),
                      const SizedBox(height: 4),
                      Text('₺${NumberFormat('#,##0', 'tr_TR').format(todayIncome)}',
                          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, 
                              color: Colors.white)),
                    ],
                  ),
                ),
                if (totalIncome > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF34C759).withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('%${((todayIncome/totalIncome)*100).toStringAsFixed(1)}',
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, 
                            color: Color(0xFF34C759))),
                  ),
              ],
            ),
          ),
          if (transactions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('İşlem Geçmişi', style: TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                      Text('${transactions.length}', style: TextStyle(
                        fontSize: 14, color: Colors.grey[400])),
                    ],
                  ),
                  const SizedBox(height: 16),
                  ...transactions.map((t) => _TransactionItem(t)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _TransactionItem extends StatelessWidget {
  final TransactionEntry transaction;
  const _TransactionItem(this.transaction);

  @override
  Widget build(BuildContext context) {
    final color = transaction.isIncome ? const Color(0xFF34C759) : const Color(0xFFFF3B30);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 48,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  transaction.description.isEmpty 
                      ? (transaction.isIncome ? 'Gelir' : 'Gider')
                      : transaction.description,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, 
                      color: Colors.white),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Text(DateFormat('d MMM, HH:mm', 'tr_TR').format(transaction.timestamp),
                    style: TextStyle(fontSize: 13, color: Colors.grey[400])),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text('${transaction.isIncome ? "+" : "-"}₺${NumberFormat('#,##0', 'tr_TR').format(transaction.amount)}',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }
}

class _BottomNavBar extends StatelessWidget {
  const _BottomNavBar();

  @override
  Widget build(BuildContext context) {
    final tuyapData = context.read<TuyapData>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Positioned(
      left: 20,
      right: 20,
      bottom: 20,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF2C2C2E) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.3 : 0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          )],
        ),
        child: Row(
          children: [
            Expanded(child: _ActionButton(
              icon: Icons.add,
              label: 'Ekle',
              color: const Color(0xFF34C759),
              onTap: () => _showDialog(context, true, tuyapData),
            )),
            const SizedBox(width: 12),
            Expanded(child: _ActionButton(
              icon: Icons.remove,
              label: 'Çıkar',
              color: const Color(0xFFFF3B30),
              onTap: () => _showDialog(context, false, tuyapData),
            )),
          ],
        ),
      ),
    );
  }

  void _showDialog(BuildContext context, bool isAdd, TuyapData data) {
    final amountController = TextEditingController();
    final descController = TextEditingController();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF2C2C2E) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey[700] : Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: (isAdd ? const Color(0xFF34C759) : const Color(0xFFFF3B30))
                          .withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      isAdd ? Icons.add_circle_outline : Icons.remove_circle_outline,
                      color: isAdd ? const Color(0xFF34C759) : const Color(0xFFFF3B30),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(isAdd ? 'Gelir Ekle' : 'Gider Çıkar',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : const Color(0xFF1C1C1E))),
                ],
              ),
              const SizedBox(height: 24),
              TextField(
                controller: amountController,
                autofocus: true,
                keyboardType: TextInputType.number,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : const Color(0xFF1C1C1E)),
                decoration: InputDecoration(
                  labelText: 'Tutar',
                  hintText: '0.00',
                  prefixText: '₺',
                  filled: true,
                  fillColor: isDark ? const Color(0xFF1C1C1E) : Colors.grey[50],
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: descController,
                style: TextStyle(color: isDark ? Colors.white : const Color(0xFF1C1C1E)),
                decoration: InputDecoration(
                  labelText: 'Açıklama (İsteğe bağlı)',
                  hintText: 'Örn: Günlük kazanç',
                  prefixIcon: const Icon(Icons.description_outlined),
                  filled: true,
                  fillColor: isDark ? const Color(0xFF1C1C1E) : Colors.grey[50],
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text('İptal', style: TextStyle(fontSize: 16,
                          color: isDark ? Colors.grey[400] : Colors.grey[700])),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        final amount = double.tryParse(amountController.text) ?? 0.0;
                        if (amount > 0) {
                          if (isAdd) {
                            data.addIncome(amount, descController.text.trim());
                          } else {
                            data.removeIncome(amount, descController.text.trim());
                          }
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Row(
                              children: [
                                Icon(isAdd ? Icons.check_circle : Icons.remove_circle, 
                                    color: Colors.white, size: 20),
                                const SizedBox(width: 12),
                                Text('₺${NumberFormat('#,##0', 'tr_TR').format(amount)} '
                                    '${isAdd ? "eklendi" : "çıkarıldı"}!'),
                              ],
                            ),
                            backgroundColor: isAdd ? const Color(0xFF34C759) 
                                : const Color(0xFFFF3B30),
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ));
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isAdd ? const Color(0xFF34C759) 
                            : const Color(0xFFFF3B30),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text(isAdd ? 'Ekle' : 'Çıkar',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(
                fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)),
          ],
        ),
      ),
    );
  }
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final themeProvider = context.watch<ThemeModeProvider>();
    final tuyapData = context.read<TuyapData>();

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  _IconButton(
                    icon: Icons.arrow_back,
                    onTap: () => Navigator.pop(context),
                    isDark: isDark,
                  ),
                  const SizedBox(width: 16),
                  Text('Ayarlar', style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : const Color(0xFF1C1C1E),
                  )),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  _SectionTitle('Görünüm', isDark),
                  const SizedBox(height: 12),
                  _SettingCard(
                    icon: Icons.palette_outlined,
                    title: 'Karanlık Mod',
                    isDark: isDark,
                    trailing: Switch(
                      value: themeProvider.isDarkMode,
                      onChanged: (_) => themeProvider.toggleTheme(),
                      activeColor: const Color(0xFF34C759),
                    ),
                  ),
                  const SizedBox(height: 32),
                  _SectionTitle('İstatistik & Raporlar', isDark),
                  const SizedBox(height: 12),
                  _SettingCard(
                    icon: Icons.bar_chart_outlined,
                    title: 'Grafik Gösterimi',
                    isDark: isDark,
                    trailing: Switch(
                      value: themeProvider.showGraphs,
                      onChanged: (_) => themeProvider.toggleGraphs(),
                      activeColor: const Color(0xFF34C759),
                    ),
                  ),
                  const SizedBox(height: 32),
                  _SectionTitle('Destek & İletişim', isDark),
                  const SizedBox(height: 12),
                  _SettingCard(
                    icon: Icons.email_outlined,
                    title: 'Bize Ulaşın',
                    isDark: isDark,
                    onTap: () async {
                      final uri = Uri(
                        scheme: 'mailto',
                        path: 'muhametkoc@gmail.com',
                        query: 'subject=Tuyap Uygulama Desteği',
                      );
                      if (await canLaunchUrl(uri)) {
                        await launchUrl(uri);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  _SettingCard(
                    icon: Icons.star_outline,
                    title: 'Uygulamayı Değerlendir',
                    isDark: isDark,
                    onTap: () async {
                      final uri = Uri.parse(
                          'https://play.google.com/store/apps/details?id=com.tuyap.gelirtakip');
                      if (await canLaunchUrl(uri)) {
                        await launchUrl(uri, mode: LaunchMode.externalApplication);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  _SettingCard(
                    icon: Icons.ios_share,
                    title: 'Uygulamayı Paylaş',
                    isDark: isDark,
                    onTap: () => Share.share(
                      'Tuyap Gelir Takip uygulamasını deneyin!\n'
                      'https://play.google.com/store/apps/details?id=com.tuyap.gelirtakip'),
                  ),
                  const SizedBox(height: 32),
                  _SectionTitle('Veri Yönetimi', isDark),
                  const SizedBox(height: 12),
                  _SettingCard(
                    icon: Icons.delete_outline,
                    title: 'Tüm Verileri Sil',
                    isDark: isDark,
                    isDestructive: true,
                    onTap: () => _showClearDialog(context, tuyapData),
                  ),
                  const SizedBox(height: 32),
                  _SectionTitle('Hakkında', isDark),
                  const SizedBox(height: 12),
                  _SettingCard(
                    icon: Icons.info_outline,
                    title: 'Uygulama Versiyonu',
                    isDark: isDark,
                    trailing: Text('1.0.0', style: TextStyle(
                      fontSize: 16, color: isDark ? Colors.grey[400] : Colors.grey[600])),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showClearDialog(BuildContext context, TuyapData data) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF2C2C2E) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Color(0xFFFF3B30), size: 28),
            const SizedBox(width: 12),
            Text('Tüm Verileri Sil', style: TextStyle(
              fontSize: 20, fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : const Color(0xFF1C1C1E))),
          ],
        ),
        content: Text('Tüm veriler silinecek. Bu işlem geri alınamaz!',
            style: TextStyle(fontSize: 16, 
                color: isDark ? Colors.grey[400] : Colors.grey[700])),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('İptal', style: TextStyle(
                fontSize: 16, color: isDark ? Colors.grey[400] : Colors.grey[700])),
          ),
          ElevatedButton(
            onPressed: () async {
              await data.clearAllData();
              if (context.mounted) {
                Navigator.pop(context);
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Row(
                    children: [
                      Icon(Icons.check_circle, color: Colors.white, size: 20),
                      SizedBox(width: 12),
                      Text('Tüm veriler silindi'),
                    ],
                  ),
                  backgroundColor: Color(0xFF34C759),
                ));
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF3B30),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Sil', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final bool isDark;
  const _SectionTitle(this.title, this.isDark);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(title, style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: isDark ? Colors.grey[500] : Colors.grey[600],
      )),
    );
  }
}

class _SettingCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final bool isDark;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool isDestructive;

  const _SettingCard({
    required this.icon,
    required this.title,
    required this.isDark,
    this.trailing,
    this.onTap,
    this.isDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF2C2C2E) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.2 : 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          )],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: (isDestructive ? const Color(0xFFFF3B30) : const Color(0xFF007AFF))
                    .withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, 
                  color: isDestructive ? const Color(0xFFFF3B30) : const Color(0xFF007AFF), 
                  size: 22),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(title, style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: isDestructive ? const Color(0xFFFF3B30) 
                    : (isDark ? Colors.white : const Color(0xFF1C1C1E)),
              )),
            ),
            if (trailing != null) trailing!,
            if (onTap != null && trailing == null)
              Icon(Icons.arrow_forward_ios, size: 16, 
                  color: isDark ? Colors.grey[600] : Colors.grey[400]),
          ],
        ),
      ),
    );
  }
}
