import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  bool _isLoading = true;
  Map<String, dynamic>? _userData;

  String dayName = '';
  
  // Statistics data
  List<Map<String, dynamic>> _weeklyData = [];
  List<Map<String, dynamic>> _monthlyData = [];
  List<Map<String, dynamic>> _yearlyData = [];
  int _todayPractices = 0;
  int _dailyPractices = 0; // To specifically track daily_practices field
  int _totalDailyPractices = 5; // Maximum daily practices
  
  // Selected time period
  String _selectedTimePeriod = 'Week';
  final List<String> _timePeriods = ['Week', 'Month', 'Year'];
  
  @override
  void initState() {
    super.initState();
    _loadUserData();
    _loadStatisticsData();
  }

  Future<void> _loadUserData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('No user signed in');
      }

      final docSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (docSnapshot.exists) {
        setState(() {
          _userData = docSnapshot.data();
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading user data: ${e.toString()}')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadStatisticsData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('No user signed in');
      }

      // Load today's practice count
      await _loadTodaysPractices(user.uid);
      
      // Load weekly data (last 7 days)
      await _loadWeeklyData(user.uid);
      
      // Load monthly data (last 30 days)
      await _loadMonthlyData(user.uid);
      
      // Load yearly data (all data by day)
      await _loadYearlyData(user.uid);
      
    } catch (e) {
      print('Error loading statistics data: $e');
    }
  }

  Future<void> _loadTodaysPractices(String userId) async {
    // Get today's date in YYYY-MM-DD format
    final now = DateTime.now();
    final dateStr = "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
    
    try {
      final docSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('progress')
          .doc(dateStr)
          .get();
      
      if (docSnapshot.exists) {
        setState(() {
          _todayPractices = docSnapshot.data()?['practice_done'] ?? 0;
          _dailyPractices = docSnapshot.data()?['daily_practices'] ?? 0; 
        });
      } else {
        setState(() {
          _todayPractices = 0;
          _dailyPractices = 0;
        });
      }
    } catch (e) {
      print('Error loading today\'s practices: $e');
    }
  }

  Future<void> _loadWeeklyData(String userId) async {
    final List<Map<String, dynamic>> weekData = [];
    
    // Get dates for the last 7 days
    final now = DateTime.now();
    
    for (int i = 6; i >= 0; i--) {
      final date = now.subtract(Duration(days: i));
      final dateStr = "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
      
      try {
        final docSnapshot = await FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .collection('progress')
            .doc(dateStr)
            .get();
        
        dayName = DateFormat('E').format(date);
        
        if (docSnapshot.exists) {
          weekData.add({
            'date': date,
            'label': dayName,
            'value': docSnapshot.data()?['practice_done'] ?? 0,
          });
        } else {
          weekData.add({
            'date': date,
            'label': dayName,
            'value': 0,
          });
        }
      } catch (e) {
        print('Error loading data for $dateStr: $e');
        weekData.add({
          'date': date,
          'label': dayName,
          'value': 0,
        });
      }
    }
    
    setState(() {
      _weeklyData = weekData;
    });
  }

  Future<void> _loadMonthlyData(String userId) async {
    final List<Map<String, dynamic>> monthData = [];
    
    // Get dates for the last 30 days
    final now = DateTime.now();
    
    for (int i = 29; i >= 0; i--) {
      final date = now.subtract(Duration(days: i));
      final dateStr = "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
      
      try {
        final docSnapshot = await FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .collection('progress')
            .doc(dateStr)
            .get();
        
        if (docSnapshot.exists) {
          monthData.add({
            'date': date,
            'label': DateFormat('MMM d').format(date), // Format as "Mar 15"
            'value': docSnapshot.data()?['practice_done'] ?? 0,
          });
        } else {
          monthData.add({
            'date': date,
            'label': DateFormat('MMM d').format(date),
            'value': 0,
          });
        }
      } catch (e) {
        print('Error loading data for $dateStr: $e');
        monthData.add({
          'date': date,
          'label': DateFormat('MMM d').format(date),
          'value': 0,
        });
      }
    }
    
    setState(() {
      _monthlyData = monthData;
    });
  }

  Future<void> _loadYearlyData(String userId) async {
    final List<Map<String, dynamic>> yearData = [];
    
    // Get all progress documents for this user
    try {
      final querySnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('progress')
          .orderBy('date')
          .get();
      
      for (var doc in querySnapshot.docs) {
        final dateStr = doc.data()['date'] as String;
        final dateParts = dateStr.split('-');
        
        if (dateParts.length == 3) {
          final year = int.parse(dateParts[0]);
          final month = int.parse(dateParts[1]);
          final day = int.parse(dateParts[2]);
          
          final date = DateTime(year, month, day);
          
          yearData.add({
            'date': date,
            'label': DateFormat('MMM d').format(date),
            'value': doc.data()['practice_done'] ?? 0,
          });
        }
      }
      
      setState(() {
        _yearlyData = yearData;
      });
    } catch (e) {
      print('Error loading yearly data: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text(
          'Dashboard',
          style: TextStyle(
            color: Color(0xFF324259),
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Main content area with scrolling
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildUserInfoCard(),
                        const SizedBox(height: 20),
                        _buildPracticeStatisticsCard(),
                        const SizedBox(height: 20),
                        _buildProgressPieChart(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildUserInfoCard() {
    final String firstName = _userData?['firstName'] ?? 'User';
    final String lastName = _userData?['lastName'] ?? '';
    final int age = _userData?['age'] ?? 0;
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.2),
            spreadRadius: 1,
            blurRadius: 3,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 85, 
              height: 85,
              child: _userData?['avatarIndex'] != null
                  ? Image.asset(
                      'assets/images/avatar${_userData!['avatarIndex'] + 1}.png',
                      fit: BoxFit.cover,
                    )
                  : const Icon(Icons.person, size: 70), // Increased icon size too
            ),
          ),
          const SizedBox(width: 16),
          
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$firstName $lastName',
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF324259),
                  ),
                ),
                const SizedBox(height: 4),
                if (age > 0)
                  Text(
                    'Age: $age',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey[700],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPracticeStatisticsCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.2),
            spreadRadius: 1,
            blurRadius: 3,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Practice Statistics',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF324259),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFEEF2F6),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: DropdownButton<String>(
                  value: _selectedTimePeriod,
                  icon: const Icon(Icons.arrow_drop_down, color: Color(0xFF1F5377)),
                  iconSize: 24,
                  elevation: 16,
                  style: const TextStyle(
                    color: Color(0xFF1F5377),
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                  underline: Container(
                    height: 0,
                  ),
                  onChanged: (String? newValue) {
                    setState(() {
                      _selectedTimePeriod = newValue!;
                    });
                  },
                  items: _timePeriods.map<DropdownMenuItem<String>>((String value) {
                    return DropdownMenuItem<String>(
                      value: value,
                      child: Text(value),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Time spent statistics
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F7FA),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Total Practice Modules This Month',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey[700],
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(
                      Icons.timeline,
                      color: Color(0xFF1F5377),
                      size: 24,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _monthlyData.fold(0, (sum, item) => sum + (item['value'] as int)).toString(),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF324259),
                      ),
                    ),
                    const Text(
                      ' modules',
                      style: TextStyle(
                        fontSize: 16,
                        color: Color(0xFF324259),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          
          // Chart area
          SizedBox(
            height: 220,
            child: _selectedTimePeriod == 'Week'
                ? _buildWeeklyBarChart()
                : _selectedTimePeriod == 'Month'
                    ? _buildMonthlyLineChart()
                    : _buildYearlyContributionChart(),
          ),
        ],
      ),
    );
  }

  Widget _buildWeeklyBarChart() {
    return _weeklyData.isEmpty
        ? const Center(child: Text('No data available'))
        : BarChart(
            BarChartData(
              alignment: BarChartAlignment.spaceAround,
              maxY: 10, // Adjust based on your expected max value
              barTouchData: BarTouchData(
                enabled: true,
                touchTooltipData: BarTouchTooltipData(
                  getTooltipItem: (group, groupIndex, rod, rodIndex) {
                    return BarTooltipItem(
                      '${_weeklyData[groupIndex]['label']}: ${_weeklyData[groupIndex]['value']}',
                      const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        backgroundColor: Color(0xFF607D8B),
                      ),
                    );
                  },
                ),
              ),
              titlesData: FlTitlesData(
                show: true,
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (value, meta) {
                      if (value.toInt() >= 0 && value.toInt() < _weeklyData.length) {
                        return Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Text(
                            _weeklyData[value.toInt()]['label'],
                            style: const TextStyle(
                              color: Color(0xFF324259),
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        );
                      }
                      return const Text('');
                    },
                    reservedSize: 30,
                  ),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (value, meta) {
                      if (value == 0 || value % 2 == 0) {
                        return Text(
                          value.toInt().toString(),
                          style: const TextStyle(
                            color: Color(0xFF324259),
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        );
                      }
                      return const Text('');
                    },
                    reservedSize: 30,
                  ),
                ),
                topTitles: AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                rightTitles: AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
              ),
              borderData: FlBorderData(
                show: false,
              ),
              barGroups: List.generate(
                _weeklyData.length,
                (index) => BarChartGroupData(
                  x: index,
                  barRods: [
                    BarChartRodData(
                      toY: _weeklyData[index]['value'].toDouble(),
                      color: const Color(0xFF1F5377),
                      width: 20,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(6),
                        topRight: Radius.circular(6),
                      ),
                    ),
                  ],
                ),
              ),
              gridData: FlGridData(
                show: true,
                horizontalInterval: 2,
                drawVerticalLine: false,
                getDrawingHorizontalLine: (value) {
                  return FlLine(
                    color: const Color(0xFFE0E0E0),
                    strokeWidth: 1,
                  );
                },
              ),
            ),
          );
  }

  Widget _buildMonthlyLineChart() {
    return _monthlyData.isEmpty
        ? const Center(child: Text('No data available'))
        : LineChart(
            LineChartData(
              lineTouchData: LineTouchData(
                enabled: true,
                touchTooltipData: LineTouchTooltipData(
                  getTooltipItems: (touchedSpots) {
                    return touchedSpots.map((LineBarSpot spot) {
                      final index = spot.x.toInt();
                      if (index >= 0 && index < _monthlyData.length) {
                        return LineTooltipItem(
                          '${_monthlyData[index]['label']}: ${spot.y.toInt()}',
                          const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            backgroundColor: Color(0xFF607D8B),
                          ),
                        );
                      }
                      return LineTooltipItem('', const TextStyle());
                    }).toList();
                  },
                ),
              ),
              lineBarsData: [
                LineChartBarData(
                  spots: List.generate(
                    _monthlyData.length, 
                    (index) => FlSpot(index.toDouble(), _monthlyData[index]['value'].toDouble()),
                  ),
                  isCurved: true,
                  color: const Color(0xFF1F5377),
                  barWidth: 3,
                  isStrokeCapRound: true,
                  dotData: FlDotData(
                    show: false,
                  ),
                  belowBarData: BarAreaData(
                    show: true,
                    color: const Color(0xFF1F5377).withOpacity(0.2),
                  ),
                ),
              ],
              titlesData: FlTitlesData(
                show: true,
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (value, meta) {
                      if (value.toInt() % 5 == 0 && value.toInt() < _monthlyData.length) {
                        return Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Text(
                            _monthlyData[value.toInt()]['label'],
                            style: const TextStyle(
                              color: Color(0xFF324259),
                              fontWeight: FontWeight.bold,
                              fontSize: 10,
                            ),
                          ),
                        );
                      }
                      return const Text('');
                    },
                    reservedSize: 30,
                  ),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (value, meta) {
                      if (value == 0 || value % 2 == 0) {
                        return Text(
                          value.toInt().toString(),
                          style: const TextStyle(
                            color: Color(0xFF324259),
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        );
                      }
                      return const Text('');
                    },
                    reservedSize: 30,
                  ),
                ),
                topTitles: AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                rightTitles: AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
              ),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: 2,
                getDrawingHorizontalLine: (value) {
                  return FlLine(
                    color: const Color(0xFFE0E0E0),
                    strokeWidth: 1,
                  );
                },
              ),
              borderData: FlBorderData(
                show: false,
              ),
              minX: 0,
              maxX: _monthlyData.length.toDouble() - 1,
              maxY: 10, // Adjust based on your expected max value
            ),
          );
  }

  Widget _buildYearlyContributionChart() {
  // GitHub-style contribution chart
  if (_yearlyData.isEmpty) {
    return const Center(child: Text('No data available'));
  }
  
  // Calculate number of weeks to display (up to 52 weeks - 1 year)
  final int daysInYear = 365;
  final int cellsPerRow = 7; // 7 days per week
  final int numWeeks = (daysInYear / cellsPerRow).ceil();
  
  // Map dates to values for quick lookup
  final Map<String, int> dateValueMap = {};
  for (var data in _yearlyData) {
    final date = data['date'] as DateTime;
    final dateStr = DateFormat('yyyy-MM-dd').format(date);
    dateValueMap[dateStr] = data['value'] as int;
  }
  
  // Create a list of all dates for the year
  final List<DateTime> allDates = [];
  final now = DateTime.now();
  final yearStart = DateTime(now.year, 1, 1);
  
  for (int i = 0; i < daysInYear; i++) {
    final date = yearStart.add(Duration(days: i));
    if (date.isBefore(now.add(const Duration(days: 1)))) {
      allDates.add(date);
    }
  }
  
  return Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      boxShadow: [
        BoxShadow(
          color: Colors.grey.withOpacity(0.2),
          spreadRadius: 1,
          blurRadius: 3,
          offset: const Offset(0, 2),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Practice Contributions',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Color(0xFF324259),
          ),
        ),
        const SizedBox(height: 12),
        
        // Use a constrained box with aspect ratio instead of fixed height
        AspectRatio(
          aspectRatio: 3.5, // Width:Height ratio
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(numWeeks, (weekIndex) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(7, (dayIndex) {
                    final cellIndex = weekIndex * 7 + dayIndex;
                    
                    if (cellIndex >= allDates.length) {
                      return Padding(
                        padding: const EdgeInsets.all(1.0),
                        child: SizedBox(width: 8, height: 8),
                      );
                    }
                    
                    final date = allDates[cellIndex];
                    final dateStr = DateFormat('yyyy-MM-dd').format(date);
                    final value = dateValueMap[dateStr] ?? 0;
                    
                    // Determine contribution color based on value
                    Color cellColor;
                    if (value == 0) {
                      cellColor = const Color(0xFFEEEEEE);
                    } else if (value <= 2) {
                      cellColor = const Color(0xFFAED6F1);
                    } else if (value <= 5) {
                      cellColor = const Color(0xFF5DADE2);
                    } else if (value <= 8) {
                      cellColor = const Color(0xFF3498DB);
                    } else {
                      cellColor = const Color(0xFF2E86C1);
                    }
                    
                    return Padding(
                      padding: const EdgeInsets.all(1.0),
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: cellColor,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    );
                  }),
                );
              }),
            ),
          ),
        ),
        
        const SizedBox(height: 12),
        
        // Use Wrap widget for the color legend
        Wrap(
          spacing: 12.0, // Space between legend items
          runSpacing: 8.0, // Space between rows when wrapped
          children: [
            _buildColorLegendItem('None', const Color(0xFFEEEEEE)),
            _buildColorLegendItem('1-2', const Color(0xFFAED6F1)),
            _buildColorLegendItem('3-5', const Color(0xFF5DADE2)),
            _buildColorLegendItem('6-8', const Color(0xFF3498DB)),
            _buildColorLegendItem('9+', const Color(0xFF2E86C1)),
          ],
        ),
      ],
    ),
  );
}

// Make legend item responsive
Widget _buildColorLegendItem(String label, Color color) {
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 8,  // Smaller fixed size
        height: 8,  // Smaller fixed size
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
      const SizedBox(width: 4),
      Text(
        label,
        style: TextStyle(
          fontSize: 10,
          color: Colors.grey[700],
        ),
      ),
    ],
  );
}

  Widget _buildProgressPieChart() {
    // Calculate percentages for pie chart
    final completedPercentage = _dailyPractices / _totalDailyPractices;
    final remainingPercentage = 1 - completedPercentage;
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.2),
            spreadRadius: 1,
            blurRadius: 3,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Daily Progress',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Color(0xFF324259),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              // Pie chart
              SizedBox(
                width: 120,
                height: 120,
                child: Stack(
                  children: [
                    PieChart(
                      PieChartData(
                        sectionsSpace: 0,
                        centerSpaceRadius: 35,
                        sections: [
                          PieChartSectionData(
                            value: _dailyPractices.toDouble(),
                            color: const Color(0xFF1F5377),
                            title: '',
                            radius: 20,
                          ),
                          PieChartSectionData(
                            value: (_totalDailyPractices - _dailyPractices).toDouble(),
                            color: const Color(0xFFE0E0E0),
                            title: '',
                            radius: 20,
                          ),
                        ],
                      ),
                    ),
                    // Center text
                    Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '$_dailyPractices/$_totalDailyPractices',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF324259),
                            ),
                          ),
                          const Text(
                            'Done',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              
              const SizedBox(width: 20),
              
              // Progress details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Daily Modules',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF324259),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: const Color(0xFF1F5377),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Completed: $_dailyPractices',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[700],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: const Color(0xFFE0E0E0),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Remaining: ${_totalDailyPractices - _dailyPractices}',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[700],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Time spent statistics
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F7FA),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Total Practice Modules This Month',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey[700],
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(
                      Icons.timeline,
                      color: Color(0xFF1F5377),
                      size: 24,
                    ),
                const SizedBox(width: 8),
                    Text(
                      _monthlyData.fold(0, (sum, item) => sum + (item['value'] as int)).toString(),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF324259),
                      ),
                    ),
                    const Text(
                      ' modules',
                      style: TextStyle(
                        fontSize: 16,
                        color: Color(0xFF324259),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}