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

class _Place {
  final String name;
  final double lat;
  final double lon;
  const _Place(this.name, this.lat, this.lon);
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  static const native = MethodChannel('maghrib_silent/native');
  static const places = <_Place>[
    _Place('مینودشت، گلستان', 37.2289, 55.3725),
    _Place('گرگان، گلستان', 36.8456, 54.4393),
    _Place('ساری، مازندران', 36.5633, 53.0601),
    _Place('تهران', 35.6892, 51.3890),
    _Place('مشهد، خراسان رضوی', 36.2972, 59.6067),
    _Place('اصفهان', 32.6546, 51.6680),
    _Place('شیراز', 29.5918, 52.5837),
    _Place('تبریز', 38.0962, 46.2738),
  ];

  final city = TextEditingController(text: 'مینودشت، گلستان');
  final lat = TextEditingController(text: '37.2289');
  final lon = TextEditingController(text: '55.3725');
  String selectedPlace = 'مینودشت، گلستان';
  DateTime? maghrib;
  DateTime? sunset;
  DateTime? sunrise;
  String status = 'در حال بررسی مجوزها...';
  Map<String, dynamic> permissions = {};
  bool busy = false;
  bool testRunning = false;

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
    if (state == AppLifecycleState.resumed) {
      _checkPermissions();
      _calculateAndSchedule();
    }
  }

  Future<void> _initialize() async {
    final p = await SharedPreferences.getInstance();
    city.text = p.getString('city') ?? city.text;
    lat.text = (p.getDouble('lat') ?? 37.2289).toString();
    lon.text = (p.getDouble('lon') ?? 55.3725).toString();
    selectedPlace = p.getString('place') ?? 'custom';
    if (!places.any((p) => p.name == selectedPlace)) selectedPlace = 'custom';
    if (mounted) setState(() {});
    await _checkPermissions(prompt: true);
    await _calculateAndSchedule();
  }

  void _selectPlace(String? value) {
    if (value == null) return;
    setState(() {
      selectedPlace = value;
      if (value != 'custom') {
        final place = places.firstWhere((p) => p.name == value);
        city.text = '${place.name}، ایران';
        lat.text = place.lat.toString();
        lon.text = place.lon.toString();
      } else {
        city.text = '';
        lat.text = '';
        lon.text = '';
      }
    });
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
      await prefs.setString('place', selectedPlace);
      await prefs.setDouble('lat', latitude);
      await prefs.setDouble('lon', longitude);

      final now = DateTime.now();
      final times = <int>[];
      DateTime? nextMaghrib;
      DateTime? nextSunset;
      DateTime? nextSunrise;

      // Tehran method: Maghrib is calculated when the Sun's centre is 4.5 degrees
      // below the horizon. Sunrise/sunset are the apparent horizon crossing.
      // Store a rolling year of exact local-device timestamps.
      for (var day = 0; day < 366; day++) {
        final date = now.add(Duration(days: day));
        final iranMethod = _prayers(date, latitude, longitude, CalculationMethod.tehran);
        final prayerTime = iranMethod.maghrib;
        if (prayerTime.isAfter(now)) {
          times.add(prayerTime.millisecondsSinceEpoch);
          if (nextMaghrib == null) {
            nextMaghrib = prayerTime;
            nextSunrise = iranMethod.sunrise;
            nextSunset = _prayers(date, latitude, longitude, CalculationMethod.muslim_world_league).maghrib;
          }
        }
      }
      if (times.isEmpty) throw StateError('زمان مغرب محاسبه نشد.');
      final p = Map<String, dynamic>.from(await native.invokeMethod('permissions'));
      if (p['dnd'] == true && p['exact'] == true) {
        await native.invokeMethod('scheduleQueue', {'times': times});
        if (mounted) setState(() {
          maghrib = nextMaghrib;
          sunset = nextSunset;
          sunrise = nextSunrise;
          status = 'زمان‌بندی اذان مغرب برای یک سال آینده ثبت شد.';
        });
      } else {
        if (mounted) setState(() {
          maghrib = nextMaghrib;
          sunset = nextSunset;
          sunrise = nextSunrise;
          status = 'برای زمان‌بندی خودکار، مجوزهای DND و هشدار دقیق را فعال کنید.';
        });
      }
    } catch (e) {
      if (mounted) setState(() => status = 'خطا: $e');
    } finally {
      busy = false;
    }
  }

  Future<void> _testSilence() async {
    try {
      final ok = await native.invokeMethod<bool>('testDnd') ?? false;
      if (!mounted) return;
      setState(() {
        testRunning = ok;
        status = ok
          ? 'آزمایش شروع شد: گوشی باید ۳۰ ثانیه ساکت بماند و سپس وضعیت قبلی برگردد.'
          : 'آزمایش انجام نشد. دسترسی DND را بررسی کنید یا آزمایش قبلی هنوز فعال است.';
      });
      if (ok) {
        await Future<void>.delayed(const Duration(seconds: 31));
        if (mounted) {
          setState(() {
            testRunning = false;
            status = 'آزمایش ۳۰ ثانیه‌ای تمام شد. وضعیت زنگ گوشی را بررسی کنید.';
          });
        }
      }
    } catch (e) {
      if (mounted) setState(() => status = 'خطا در آزمایش: $e');
    }
  }

  String _clock(DateTime? value) {
    if (value == null) return '—';
    final t = value.toLocal();
    return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  String _gap() {
    if (sunset == null || maghrib == null) return '—';
    final minutes = maghrib!.difference(sunset!).inMinutes;
    if (minutes < 0) return '—';
    return '$minutes دقیقه';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Maghrib Silent 🌙')),
    body: ListView(padding: const EdgeInsets.all(20), children: [
      const Text('مکان محاسبه', style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
      DropdownButtonFormField<String>(
        value: selectedPlace,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'انتخاب دستی شهر یا مختصات دلخواه'),
        items: [
          ...places.map((p) => DropdownMenuItem(value: p.name, child: Text(p.name))),
          const DropdownMenuItem(value: 'custom', child: Text('مکان دلخواه / ورود مختصات')),
        ],
        onChanged: _selectPlace,
      ),
      TextField(controller: city, decoration: const InputDecoration(labelText: 'نام شهر / کشور')),
      TextField(controller: lat, keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true), decoration: const InputDecoration(labelText: 'عرض جغرافیایی')),
      TextField(controller: lon, keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true), decoration: const InputDecoration(labelText: 'طول جغرافیایی')),
      const SizedBox(height: 20),
      FilledButton(onPressed: busy ? null : _calculateAndSchedule, child: const Text('ذخیره مکان و زمان‌بندی')),
      OutlinedButton(onPressed: () async { await _checkPermissions(prompt: true); await _calculateAndSchedule(); }, child: const Text('بررسی مجوزها')),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: testRunning ? null : _testSilence,
        icon: const Icon(Icons.volume_off),
        label: const Text('آزمایش سکوت و بازگشت صدا (۳۰ ثانیه)'),
      ),
      const SizedBox(height: 20),
      Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('طلوع آفتاب: ${_clock(sunrise)}'),
        const SizedBox(height: 8),
        Text('غروب آفتاب: ${_clock(sunset)}'),
        const SizedBox(height: 8),
        Text('اذان مغرب: ${_clock(maghrib)}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text('فاصله غروب تا اذان مغرب: ${_gap()}'),
        const SizedBox(height: 8),
        const Text('مدت سکوت: ۳۰ دقیقه'),
        const Divider(),
        const Text('روش ایران: مؤسسه ژئوفیزیک دانشگاه تهران، زاویه مغرب ۴٫۵ درجه زیر افق.'),
      ]))),
      for (final item in [('battery', 'بهینه‌سازی باتری'), ('dnd', 'دسترسی DND'), ('exact', 'هشدار دقیق')])
        ListTile(title: Text(item.$2), trailing: Icon(
          permissions[item.$1] == true ? Icons.check_circle : Icons.warning_amber,
          color: permissions[item.$1] == true ? Colors.green : Colors.orange,
        )),
      Text(status),
      const SizedBox(height: 12),
      const Text('برای شهرهای ایران از منطقه زمانی ایران استفاده کنید. برای مختصات خارج از منطقه زمانی گوشی، ساعت و منطقه زمانی دستگاه را نیز متناسب با محل انتخاب‌شده تنظیم کنید.'),
    ]),
  );
}
