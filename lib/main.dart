import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:csv/csv.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:shared_preferences/shared_preferences.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tz.initializeTimeZones();
  tz.setLocalLocation(tz.getLocation('Europe/Paris'));

  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  const iosInit = DarwinInitializationSettings();
  const initSettings = InitializationSettings(android: androidInit, iOS: iosInit);
  await flutterLocalNotificationsPlugin.initialize(initSettings);

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
      ?.requestPermissions(alert: true, badge: true, sound: true);

  runApp(YangaTrackerApp());
}

class YangaTrackerApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Yanga Tracker',
      theme: ThemeData.dark(),
      home: YangaHomePage(),
    );
  }
}

class YangaEntry {
  final String flavor;
  final DateTime timestamp;

  YangaEntry(this.flavor, this.timestamp);

  Map<String, dynamic> toJson() => {
        'flavor': flavor,
        'timestamp': timestamp.toIso8601String(),
      };

  factory YangaEntry.fromJson(Map<String, dynamic> json) => YangaEntry(
        json['flavor'],
        DateTime.parse(json['timestamp']),
      );
}

class YangaHomePage extends StatefulWidget {
  @override
  _YangaHomePageState createState() => _YangaHomePageState();
}

class _YangaHomePageState extends State<YangaHomePage> {
  final List<YangaEntry> _entries = [];
  Timer? _timer;
  DateTime? _nextTime;
  final _flavors = ['Coco‑Ananas', 'Citron', 'Boost de Baies', 'Pêche', 'Fruits de la Passion', 'Cassis'];
  String _selectedFlavor = 'Coco‑Ananas';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    final entriesJson = prefs.getString('entries');
    final nextTimeStr = prefs.getString('nextTime');

    if (entriesJson != null) {
      final List list = jsonDecode(entriesJson);
      setState(() {
        _entries.addAll(list.map((e) => YangaEntry.fromJson(e)));
      });
    }

    if (nextTimeStr != null) {
      final next = DateTime.tryParse(nextTimeStr);
      if (next != null && next.isAfter(DateTime.now())) {
        setState(() => _nextTime = next);
        _startTimer();
      }
    }
  }

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    final entriesJson = jsonEncode(_entries.map((e) => e.toJson()).toList());
    await prefs.setString('entries', entriesJson);
    await prefs.setString('nextTime', _nextTime?.toIso8601String() ?? '');
  }

  void _addEntry() async {
    final entry = YangaEntry(_selectedFlavor, DateTime.now());
    setState(() {
      _entries.add(entry);
      _nextTime = DateTime.now().add(Duration(minutes: 20));
    });
    await _saveData();
    _startTimer();

    await flutterLocalNotificationsPlugin.zonedSchedule(
      0,
      'Yanga prête !',
      'Il est temps de boire ta prochaine Yanga ($_selectedFlavor)',
      tz.TZDateTime.now(tz.local).add(Duration(minutes: 20)),
      const NotificationDetails(
        android: AndroidNotificationDetails('yanga_channel', 'Yanga Tracker'),
      ),
      androidAllowWhileIdle: true,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(Duration(seconds: 1), (timer) {
      if (_nextTime == null || _nextTime!.isBefore(DateTime.now())) {
        timer.cancel();
      }
      setState(() {});
    });
  }

  Future<void> _exportCSV() async {
    final rows = [
      ['Goût', 'Horodatage'],
      ..._entries.map((e) => [e.flavor, e.timestamp.toIso8601String()]),
    ];
    final csv = const ListToCsvConverter().convert(rows);
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/yanga_log.csv');
    await file.writeAsString(csv);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Exporté vers ${file.path}'),
    ));
  }

  String _remainingTime() {
    if (_nextTime == null) return 'Prêt pour une Yanga';
    final diff = _nextTime!.difference(DateTime.now());
    if (diff.isNegative) return 'Prêt pour une Yanga';
    final hours = diff.inHours.toString().padLeft(2, '0');
    final min = diff.inMinutes.remainder(60).toString().padLeft(2, '0');
    final sec = diff.inSeconds.remainder(60).toString().padLeft(2, '0');
    return 'Prochaine Yanga dans $min:$sec';
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Yanga Tracker'),
        actions: [
          IconButton(
            icon: Icon(Icons.save_alt),
            onPressed: _exportCSV,
          )
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            DropdownButton<String>(
              value: _selectedFlavor,
              items: _flavors.map((f) => DropdownMenuItem(
                child: Text(f),
                value: f,
              )).toList(),
              onChanged: (val) => setState(() => _selectedFlavor = val!),
            ),
            ElevatedButton(
              onPressed: _addEntry,
              child: Text('Ajouter une Yanga'),
            ),
            SizedBox(height: 20),
            Text(_remainingTime(), style: TextStyle(fontSize: 18)),
            Divider(height: 40),
            Expanded(
              child: ListView.builder(
                itemCount: _entries.length,
                itemBuilder: (context, index) {
                  final e = _entries[index];
                  return ListTile(
                    title: Text(e.flavor),
                    subtitle: Text(e.timestamp.toLocal().toString()),
                  );
                },
              ),
            )
          ],
        ),
      ),
    );
  }
}
