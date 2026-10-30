import 'package:adhan/adhan.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const MaghribApp());

class MaghribApp extends StatelessWidget {
  const MaghribApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Maghrib Silent',
    theme: ThemeData(useMaterial3: true, colorSchemeSeed: const Color(0xff505b91)),
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
  DateTime? sunset;
  String status = 'در حال بررسی مجوزها...';
  Map<String, dynamic> permissions = {};
  bool busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    city.dispose(); lat.dispose(); lon.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkPermissions();
  }

  Future<void> _initialize() async {
    final p = await SharedPreferences.getInstance();
    city.text = p.getString('city') ?? city.text;
    lat.text = (p.getDouble('lat') ?? 37.2289).toString();
    lon.text = (p.getDouble('lon') ?? 55.3725).toString();
    await _checkPermissions(prompt: true);
    await _calculateAndSchedule();
  }

  Future<void> _checkPermissions({bool prompt = false}) async {
    try {
      final p = Map<String, dynamic>.from(await native.invokeMethod('permissions'));
      if (!mounted) return;
      setState(() => permissions = p);
      if (prompt) {
        for (final item in [
          ('battery', 'openBattery', 'بهینه‌سازی باتری'),
          ('dnd', 'openDnd', 'دسترسی مزاحم نشوید'),
          ('exact', 'openExact', 'هشدار دقیق'),
        ]) {
          if (p[item.$1] != true) {
            if (!mounted) return;
            await showDialog<void>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: Text('فعال‌سازی ${item.$3}'),
                content: const Text('برای اجرای خودکار برنامه، این دسترسی را در تنظیمات اندروید فعال کنید.'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('بعداً')),
                  FilledButton(onPressed: () async {
                    Navigator.pop(ctx);
                    await native.invokeMethod(item.$2);
                  }, child: const Text('باز کردن تنظیمات')),
                ],
              ),
            );
            break;
          }
        }
      }
    } catch (e) {
      if (mounted) setState(() => status = 'خطا در بررسی مجوزها: $e');
    }
  }

  PrayerTimes _prayers(DateTime date, double latitude, double longitude, CalculationMethod method) {
    final params = method.getParameters()..madhab = Madhab.shafi;
    return PrayerTimes(
      Coordinates(latitude, longitude, validate: true),
      DateComponents(date.year, date.month, date.day),
      params,
    );
  }

  Future<void> _calculateAndSchedule() async {
    if (busy) return;
    busy = true;
    try {
      final latitude = double.tryParse(lat.text.trim());
      final longitude = double.tryParse(lon.text.trim());
      if (latitude == null || longitude == null || latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180) {
        throw const FormatException('مختصات جغرافیایی معتبر نیست.');
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('city', city.text.trim());
      await prefs.setDouble('lat', latitude);
      await prefs.setDouble('lon', longitude);

      final now = DateTime.now();
      final tehranToday = _prayers(now, latitude, longitude, CalculationMethod.tehran);
      final sunsetToday = _prayers(now, latitude, longitude, CalculationMethod.muslim_world_league).maghrib;
      final times = <int>[];
      DateTime? nextMaghrib;
      DateTime? nextSunset;

      // Rolling one-year schedule. Native AlarmManager advances one day at a time,
      // and restores the queue after reboot. Reopen the app yearly or after changing location.
      for (var day = 0; day < 366; day++) {
        final date = now.add(Duration(days: day));
        final prayers = _prayers(date, latitude, longitude, CalculationMethod.tehran);
        final prayerTime = prayers.maghrib;
        if (prayerTime.isAfter(now)) {
          times.add(prayerTime.millisecondsSinceEpoch);
          nextMaghrib ??= prayerTime;
          if (day == 0) nextSunset = sunsetToday;
        }
      }
      if (times.isEmpty) throw StateError('زمان مغرب محاسبه نشد.');
      final p = Map<String, dynamic>.from(await native.invokeMethod('permissions'));
      if (p['dnd'] == true && p['exact'] == true) {
        await native.invokeMethod('scheduleQueue', {'times': times});
        if (mounted) setState(() {
          maghrib = nextMaghrib;
          sunset = nextSunset;
          status = 'زمان‌بندی مغرب برای یک سال آینده ثبت شد. پس از تغییر مکان، دوباره ذخیره کنید.';
        });
      } else {
        if (mounted) setState(() {
          maghrib = nextMaghrib;
          sunset = nextSunset;
          status = 'برای زمان‌بندی خودکار، مجوزهای DND و هشدار دقیق را فعال کنید.';
        });
      }
    } catch (e) {
      if (mounted) setState(() => status = 'خطا: $e');
    } finally {
      busy = false;
    }
  }

  String _clock(DateTime? value) {
    if (value == null) return '—';
    final t = value.toLocal();
    return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Maghrib Silent 🌙')),
    body: ListView(padding: const EdgeInsets.all(20), children: [
      const Text('مکان محاسبه', style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
      TextField(controller: city, decoration: const InputDecoration(labelText: 'شهر / کشور (عنوان نمایشی)')),
      TextField(controller: lat, keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true), decoration: const InputDecoration(labelText: 'عرض جغرافیایی')),
      TextField(controller: lon, keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true), decoration: const InputDecoration(labelText: 'طول جغرافیایی')),
      const SizedBox(height: 20),
      FilledButton(onPressed: busy ? null : _calculateAndSchedule, child: const Text('ذخیره مکان و زمان‌بندی')),
      OutlinedButton(onPressed: () async { await _checkPermissions(prompt: true); await _calculateAndSchedule(); }, child: const Text('بررسی مجوزها')),
      const SizedBox(height: 20),
      Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('غروب آفتاب: ${_clock(sunset)}'),
        const SizedBox(height: 8),
        Text('اذان مغرب: ${_clock(maghrib)}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        const Text('مدت سکوت: ۳۰ دقیقه'),
        const Divider(),
        const Text('روش محاسبه: مؤسسه ژئوفیزیک دانشگاه تهران (زاویه مغرب ۴٫۵ درجه زیر افق)'),
      ]))),
      for (final item in [('battery', 'بهینه‌سازی باتری'), ('dnd', 'دسترسی DND'), ('exact', 'هشدار دقیق')])
        ListTile(title: Text(item.$2), trailing: Icon(
          permissions[item.$1] == true ? Icons.check_circle : Icons.warning_amber,
          color: permissions[item.$1] == true ? Colors.green : Colors.orange,
        )),
      Text(status),
      const SizedBox(height: 12),
      const Text('نکته: نام شهر فقط برچسب است و محاسبه بر اساس مختصات انجام می‌شود. منطقه زمانی گوشی باید با مکان انتخاب‌شده مطابقت داشته باشد. زمان اذان مغرب با غروب نجومی آفتاب یکسان نیست.'),
    ]),
  );
}
