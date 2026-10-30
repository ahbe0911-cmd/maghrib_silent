import 'package:adhan/adhan.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaghribApp());
}

class MaghribApp extends StatelessWidget {
  const MaghribApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Maghrib Silent',
        theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
        home: const HomePage(),
      );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  static const native = MethodChannel('maghrib_silent/native');
  final city = TextEditingController(text: 'Minoudasht, Golestan, Iran');
  final lat = TextEditingController(text: '37.2289');
  final lon = TextEditingController(text: '55.3725');
  DateTime? maghrib;
  String status = 'Checking permissions...';
  Map<String, dynamic> permissions = {};
  bool openingSettings = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    city.dispose();
    lat.dispose();
    lon.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _initialize() async {
    final prefs = await SharedPreferences.getInstance();
    city.text = prefs.getString('city') ?? city.text;
    lat.text = (prefs.getDouble('lat') ?? 37.2289).toString();
    lon.text = (prefs.getDouble('lon') ?? 55.3725).toString();
    await _refresh(prompt: true);
  }

  Future<void> _refresh({bool prompt = false}) async {
    try {
      final p = Map<String, dynamic>.from(
        await native.invokeMethod('permissions'),
      );
      if (!mounted) return;
      setState(() => permissions = p);
      if (prompt && !openingSettings) {
        for (final entry in [
          ('battery', 'openBattery'),
          ('dnd', 'openDnd'),
          ('exact', 'openExact'),
        ]) {
          if (p[entry.$1] != true) {
            openingSettings = true;
            await _showPermissionDialog(entry.$1, entry.$2);
            openingSettings = false;
            break;
          }
        }
      }
      if (p.values.every((value) => value == true)) {
        await _saveAndSchedule();
      } else if (mounted) {
        setState(() => status =
            'Grant the permissions, then tap Check permissions.');
      }
    } catch (e) {
      if (mounted) setState(() => status = 'Error: $e');
    }
  }

  Future<void> _showPermissionDialog(String key, String method) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Permission needed: $key'),
        content: Text(
          key == 'battery'
              ? 'Set this app to Unrestricted in battery settings to improve background reliability.'
              : key == 'dnd'
                  ? 'Allow Do Not Disturb access for this app.'
                  : 'Allow exact alarms for this app.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Later'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              await native.invokeMethod(method);
            },
            child: const Text('Open settings'),
          ),
        ],
      ),
    );
  }

  DateTime _maghribFor(DateTime date, double latitude, double longitude) {
    final params = CalculationMethod.muslim_world_league.getParameters();
    params.madhab = Madhab.shafi;
    final prayers = PrayerTimes(
      Coordinates(latitude, longitude),
      DateComponents(date.year, date.month, date.day),
      params,
    );
    return prayers.maghrib;
  }

  Future<void> _saveAndSchedule() async {
    final latitude = double.tryParse(lat.text.trim());
    final longitude = double.tryParse(lon.text.trim());
    if (latitude == null ||
        longitude == null ||
        latitude < -90 ||
        latitude > 90 ||
        longitude < -180 ||
        longitude > 180) {
      if (mounted) setState(() => status = 'Invalid latitude or longitude.');
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('city', city.text.trim());
    await prefs.setDouble('lat', latitude);
    await prefs.setDouble('lon', longitude);

    final now = DateTime.now();
    final today = _maghribFor(now, latitude, longitude);
    final tomorrow =
        _maghribFor(now.add(const Duration(days: 1)), latitude, longitude);
    final dayAfter =
        _maghribFor(now.add(const Duration(days: 2)), latitude, longitude);

    final start =
        today.add(const Duration(minutes: 30)).isAfter(now) ? today : tomorrow;
    final next = start == today ? tomorrow : dayAfter;

    await native.invokeMethod('schedule', {
      'start': start.millisecondsSinceEpoch,
      'next': next.millisecondsSinceEpoch,
    });

    if (mounted) {
      setState(() {
        maghrib = start;
        status =
            'Alarms scheduled. Keep automatic date/time and time zone enabled.';
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Maghrib Silent 🌙')),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'Location',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            TextField(
              controller: city,
              decoration: const InputDecoration(
                labelText: 'City / Country (label only)',
              ),
            ),
            TextField(
              controller: lat,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              decoration: const InputDecoration(labelText: 'Latitude'),
            ),
            TextField(
              controller: lon,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              decoration: const InputDecoration(labelText: 'Longitude'),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _saveAndSchedule,
              child: const Text('Save location and schedule'),
            ),
            OutlinedButton(
              onPressed: () => _refresh(prompt: true),
              child: const Text('Check permissions'),
            ),
            const SizedBox(height: 20),
            Text('Next Maghrib: ${maghrib?.toLocal().toString() ?? "Not scheduled"}'),
            const Text('Silent / DND duration: 30 minutes'),
            const SizedBox(height: 12),
            for (final key in ['battery', 'dnd', 'exact'])
              ListTile(
                title: Text('$key permission'),
                trailing: Icon(
                  permissions[key] == true
                      ? Icons.check_circle
                      : Icons.warning_amber,
                  color: permissions[key] == true
                      ? Colors.green
                      : Colors.orange,
                ),
              ),
            const SizedBox(height: 12),
            Text(status),
            const SizedBox(height: 20),
            const Text(
              'Note: City names are labels; enter coordinates for a new location. '
              'The device time zone must match the selected location for accurate '
              'local prayer-time calculation. Reopen the app periodically to refresh future dates.',
            ),
          ],
        ),
      );
}
