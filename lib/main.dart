import 'package:adhan/adhan.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const MaghribApp());

class MaghribApp extends StatelessWidget {
  const MaghribApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Maghrib Silent',
    theme: ThemeData(useMaterial3: true, colorSchemeSeed: const Color(0xff505b91), fontFamily: 'FarNazanin'),
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
  bool gpsLoading = false;

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

  Future<void> _useGps() async {
    if (gpsLoading) return;
    setState(() { gpsLoading = true; status = 'در حال دریافت موقعیت GPS...'; });
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw Exception('سرویس موقعیت مکانی گوشی خاموش است.');
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw Exception('دسترسی موقعیت مکانی داده نشده است.');
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      if (!mounted) return;
      setState(() {
        selectedPlace = 'custom';
        city.text = 'موقعیت فعلی GPS';
        lat.text = pos.latitude.toStringAsFixed(6);
        lon.text = pos.longitude.toStringAsFixed(6);
      });
      await _calculateAndSchedule();
    } catch (e) {
      if (mounted) setState(() => status = 'خطا در GPS: $e');
    } finally {
      if (mounted) setState(() => gpsLoading = false);
    }
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

  Future<void> _openPermission(String key) async {
    final method = {'battery': 'openBattery', 'dnd': 'openDnd', 'exact': 'openExact'}[key];
    if (method == null) return;
    try {
      final opened = await native.invokeMethod<bool>(method) ?? false;
      if (!opened && mounted) setState(() => status = 'تنظیمات این مجوز در گوشی باز نشد. از بخش تنظیمات برنامه به صورت دستی وارد شوید.');
    } catch (e) {
      if (mounted) setState(() => status = 'خطا در باز کردن تنظیمات: $e');
    }
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
                    await _openPermission(item.$1);
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
          ? 'آزمایش شروع شد: گوشی باید ۱۵ ثانیه ساکت بماند و سپس وضعیت قبلی برگردد.'
          : 'آزمایش انجام نشد. دسترسی DND را بررسی کنید یا آزمایش قبلی هنوز فعال است.';
      });
      if (ok) {
        await Future<void>.delayed(const Duration(seconds: 16));
        if (mounted) {
          setState(() {
            testRunning = false;
            status = 'آزمایش ۱۵ ثانیه‌ای تمام شد. وضعیت زنگ گوشی را بررسی کنید.';
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
  Widget build(BuildContext context) {
    final h = MediaQuery.sizeOf(context).height;
    final compact = h < 760;
    final pad = compact ? 8.0 : 12.0;
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: compact ? 44 : 52,
        title: const Text('سکوت اذان مغرب 🌙', style: TextStyle(fontSize: 19)),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: compact ? 3 : 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                const Expanded(child: Text('موقعیت مکانی', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold))),
                TextButton.icon(
                  onPressed: gpsLoading ? null : _useGps,
                  icon: const Icon(Icons.my_location, size: 18),
                  label: Text(gpsLoading ? 'دریافت...' : 'تشخیص خودکار GPS'),
                ),
              ]),
              SizedBox(height: pad / 2),
              SizedBox(height: 48, child: DropdownButtonFormField<String>(
                value: selectedPlace,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'انتخاب شهر یا مختصات', border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 5)),
                items: [
                  ...places.map((p) => DropdownMenuItem(value: p.name, child: Text(p.name))),
                  const DropdownMenuItem(value: 'custom', child: Text('مکان دلخواه / GPS')),
                ],
                onChanged: _selectPlace,
              )),
              SizedBox(height: pad),
              Row(children: [
                Expanded(flex: 3, child: _field(city, 'شهر / کشور')),
                const SizedBox(width: 6),
                Expanded(flex: 2, child: _field(lat, 'عرض', numeric: true)),
                const SizedBox(width: 6),
                Expanded(flex: 2, child: _field(lon, 'طول', numeric: true)),
              ]),
              SizedBox(height: pad),
              FilledButton(
                onPressed: busy ? null : _calculateAndSchedule,
                child: const Text('ذخیره مکان و زمان‌بندی'),
              ),
              Card(
                margin: EdgeInsets.symmetric(vertical: pad / 2),
                child: Padding(
                  padding: EdgeInsets.all(compact ? 9 : 13),
                  child: Column(children: [
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      _timeItem('طلوع', _clock(sunrise)),
                      _timeItem('غروب', _clock(sunset)),
                      _timeItem('اذان مغرب', _clock(maghrib), highlight: true),
                    ]),
                    const SizedBox(height: 5),
                    Text('فاصله غروب تا اذان: ${_gap()}     |     سکوت: ۳۰ دقیقه',
                      textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)),
                  ]),
                ),
              ),
              Row(children: [
                Expanded(child: OutlinedButton.icon(
                  onPressed: () async { await _checkPermissions(prompt: true); await _calculateAndSchedule(); },
                  icon: const Icon(Icons.verified_user_outlined, size: 17),
                  label: const Text('مجوزها', style: TextStyle(fontSize: 12)),
                )),
                const SizedBox(width: 6),
                Expanded(flex: 2, child: OutlinedButton.icon(
                  onPressed: testRunning ? null : _testSilence,
                  icon: const Icon(Icons.volume_off, size: 17),
                  label: const Text('آزمایش ۱۵ ثانیه‌ای', style: TextStyle(fontSize: 12)),
                )),
              ]),
              Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                _permission('باتری', 'battery'),
                _permission('DND', 'dnd'),
                _permission('آلارم دقیق', 'exact'),
              ]),
              Text(status, textAlign: TextAlign.center, maxLines: 2,
                overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, fontFamily: 'ARooznameh')),
              if (!compact) const Spacer(),
              const Text('روش محاسبه تهران: مغرب ۴٫۵ درجه زیر افق',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 10)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(TextEditingController controller, String label, {bool numeric = false}) {
    return SizedBox(height: 48, child: TextField(
      controller: controller,
      keyboardType: numeric ? const TextInputType.numberWithOptions(decimal: true, signed: true) : TextInputType.text,
      style: const TextStyle(fontSize: 12),
      decoration: InputDecoration(
        labelText: label, labelStyle: const TextStyle(fontSize: 11),
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      ),
    ));
  }

  Widget _timeItem(String title, String time, {bool highlight = false}) {
    return Column(children: [
      Text(title, style: TextStyle(fontSize: 11, fontWeight: highlight ? FontWeight.bold : FontWeight.normal)),
      Text(time, style: TextStyle(fontSize: highlight ? 23 : 17,
        fontWeight: highlight ? FontWeight.bold : FontWeight.w500)),
    ]);
  }

  Widget _permission(String label, String key) {
    final ok = permissions[key] == true;
    return InkWell(onTap: () => _openPermission(key), child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(ok ? Icons.check_circle : Icons.warning_amber, color: ok ? Colors.green : Colors.orange, size: 15),
      const SizedBox(width: 3),
      Text(label, style: const TextStyle(fontSize: 10)),
    ]));
  }
}
