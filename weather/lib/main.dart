import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(const WeatherApp());
}

const _ink = Color(0xFF17284B);
const _muted = Color(0xFF8190A9);
const _blue = Color(0xFF4776E6);
const _pale = Color(0xFFF3F6FC);

class WeatherApp extends StatelessWidget {
  const WeatherApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Погода рядом',
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: _pale,
        colorScheme: ColorScheme.fromSeed(seedColor: _blue),
        fontFamily: 'Roboto',
      ),
      home: const WeatherHomePage(),
    );
  }
}

class City {
  const City({
    required this.name,
    required this.latitude,
    required this.longitude,
    this.region,
    this.country,
  });

  final String name;
  final double latitude;
  final double longitude;
  final String? region;
  final String? country;

  String get subtitle => [
    region,
    country,
  ].whereType<String>().where((e) => e.isNotEmpty).join(', ');
  String get fullName => subtitle.isEmpty ? name : '$name, $subtitle';

  factory City.fromJson(Map<String, dynamic> json) => City(
    name: json['name'] as String? ?? 'Неизвестный город',
    latitude: (json['latitude'] as num).toDouble(),
    longitude: (json['longitude'] as num).toDouble(),
    region: json['admin1'] as String?,
    country: json['country'] as String?,
  );
}

class WeatherSnapshot {
  const WeatherSnapshot({
    required this.city,
    required this.temperature,
    required this.feelsLike,
    required this.humidity,
    required this.wind,
    required this.code,
    required this.isDay,
    required this.updatedAt,
    required this.hourly,
    required this.daily,
    required this.uvIndex,
    required this.sunrise,
    required this.sunset,
  });

  final City city;
  final double temperature;
  final double feelsLike;
  final int humidity;
  final double wind;
  final int code;
  final bool isDay;
  final DateTime updatedAt;
  final List<HourForecast> hourly;
  final List<DayForecast> daily;
  final double uvIndex;
  final String sunrise;
  final String sunset;
}

class HourForecast {
  const HourForecast(
    this.time,
    this.temperature,
    this.code,
    this.precipitation,
  );
  final String time;
  final double temperature;
  final int code;
  final int precipitation;
}

class DayForecast {
  const DayForecast(this.date, this.max, this.min, this.code);
  final DateTime date;
  final double max;
  final double min;
  final int code;
}

class WeatherApi {
  static Future<List<City>> search(String query) async {
    final parameters = {
      'name': query,
      'count': '7',
      'language': 'ru',
      'format': 'json',
    };
    final uri = _requestUri(
      webPath: '/api/search',
      nativeHost: 'geocoding-api.open-meteo.com',
      parameters: parameters,
    );
    final response = await http.get(uri).timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw Exception('Не удалось найти город. Попробуйте ещё раз.');
    }
    final results =
        jsonDecode(response.body)['results'] as List<dynamic>? ?? [];
    return results
        .map((item) => City.fromJson(item as Map<String, dynamic>))
        .toList(growable: false);
  }

  static Future<WeatherSnapshot> forecast(City city) async {
    final parameters = {
      'latitude': city.latitude.toString(),
      'longitude': city.longitude.toString(),
      'current': 'temperature_2m,relative_humidity_2m,apparent_temperature,is_day,precipitation,weather_code,wind_speed_10m',
      'hourly': 'temperature_2m,precipitation_probability,weather_code',
      'daily': 'weather_code,temperature_2m_max,temperature_2m_min,sunrise,sunset,uv_index_max',
      'forecast_days': '7',
      'timezone': 'auto',
    };
    final uri = _requestUri(
      webPath: '/api/forecast',
      nativeHost: 'api.open-meteo.com',
      parameters: parameters,
    );
    final response = await http.get(uri).timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw Exception(
        'Не удалось получить прогноз. Проверьте подключение к интернету.',
      );
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final current = json['current'] as Map<String, dynamic>;
    final hourly = json['hourly'] as Map<String, dynamic>;
    final daily = json['daily'] as Map<String, dynamic>;
    final times = (hourly['time'] as List<dynamic>).cast<String>();
    final currentTime = (current['time'] as String).substring(0, 13);
    var startIndex = times.indexWhere((time) => time.startsWith(currentTime));
    if (startIndex < 0) startIndex = 0;
    final hourTemps = hourly['temperature_2m'] as List<dynamic>;
    final hourCodes = hourly['weather_code'] as List<dynamic>;
    final precipitation = hourly['precipitation_probability'] as List<dynamic>;
    final hours = <HourForecast>[];
    for (var i = startIndex; i < times.length && hours.length < 24; i++) {
      hours.add(
        HourForecast(
          times[i].substring(11, 16),
          (hourTemps[i] as num).toDouble(),
          hourCodes[i] as int,
          (precipitation[i] as num?)?.toInt() ?? 0,
        ),
      );
    }
    final dates = (daily['time'] as List<dynamic>).cast<String>();
    final maxTemps = daily['temperature_2m_max'] as List<dynamic>;
    final minTemps = daily['temperature_2m_min'] as List<dynamic>;
    final dayCodes = daily['weather_code'] as List<dynamic>;
    final days = List<DayForecast>.generate(
      dates.length,
      (i) => DayForecast(
        DateTime.parse(dates[i]),
        (maxTemps[i] as num).toDouble(),
        (minTemps[i] as num).toDouble(),
        dayCodes[i] as int,
      ),
    );
    final clockTimes = (daily['sunrise'] as List<dynamic>).cast<String>();

    return WeatherSnapshot(
      city: city,
      temperature: (current['temperature_2m'] as num).toDouble(),
      feelsLike: (current['apparent_temperature'] as num).toDouble(),
      humidity: (current['relative_humidity_2m'] as num).toInt(),
      wind: (current['wind_speed_10m'] as num).toDouble(),
      code: current['weather_code'] as int,
      isDay: current['is_day'] == 1,
      updatedAt: DateTime.parse(current['time'] as String),
      hourly: hours,
      daily: days,
      uvIndex: (daily['uv_index_max'][0] as num).toDouble(),
      sunrise: (clockTimes.first).substring(11, 16),
      sunset: (daily['sunset'][0] as String).substring(11, 16),
    );
  }

  static Uri _requestUri({
    required String webPath,
    required String nativeHost,
    required Map<String, String> parameters,
  }) {
    if (kIsWeb) {
      return Uri.base.resolve(webPath).replace(queryParameters: parameters);
    }
    return Uri.https(nativeHost, '/v1/${webPath.split('/').last}', parameters);
  }
}

class WeatherHomePage extends StatefulWidget {
  const WeatherHomePage({super.key});

  @override
  State<WeatherHomePage> createState() => _WeatherHomePageState();
}

class _WeatherHomePageState extends State<WeatherHomePage> {
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  Timer? _searchTimer;
  WeatherSnapshot? _weather;
  List<City> _suggestions = [];
  bool _loading = true;
  bool _searching = false;
  bool _locating = false;
  String? _error;
  String? _searchError;
  String _query = '';
  City _selectedCity = const City(
    name: 'Москва',
    latitude: 55.7558,
    longitude: 37.6173,
    country: 'Россия',
  );

  @override
  void initState() {
    super.initState();
    _loadWeather(_selectedCity);
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _loadWeather(City city) async {
    _selectedCity = city;
    setState(() {
      _loading = true;
      _error = null;
      _suggestions = [];
      _query = '';
      _searchController.clear();
    });
    try {
      final result = await WeatherApi.forecast(city);
      if (!mounted) return;
      setState(() {
        _weather = result;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _networkErrorMessage(error);
      });
    }
  }

  void _onSearchChanged(String value) {
    _searchTimer?.cancel();
    setState(() {
      _query = value;
      _suggestions = [];
      _searchError = null;
    });
    if (value.trim().length < 2) {
      setState(() => _searching = false);
      return;
    }
    _searchTimer = Timer(const Duration(milliseconds: 350), () async {
      if (!mounted) return;
      setState(() => _searching = true);
      try {
        final results = await WeatherApi.search(value.trim());
        if (!mounted || _query != value) return;
        setState(() {
          _suggestions = results;
          _searching = false;
        });
      } catch (error) {
        if (!mounted || _query != value) return;
        setState(() {
          _searching = false;
          _searchError = _networkErrorMessage(error, searching: true);
        });
      }
    });
  }

  Future<void> _submitSearch(String value) async {
    final query = value.trim();
    if (query.length < 2) return;
    _searchTimer?.cancel();
    setState(() {
      _searching = true;
      _searchError = null;
    });
    try {
      final results = await WeatherApi.search(query);
      if (!mounted || _query != value) return;
      setState(() {
        _suggestions = results;
        _searching = false;
      });
      if (results.length == 1) {
        _searchFocus.unfocus();
        await _loadWeather(results.first);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _searching = false;
        _searchError = _networkErrorMessage(error, searching: true);
      });
    }
  }

  Future<void> _useCurrentLocation() async {
    setState(() {
      _locating = true;
      _error = null;
    });
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        throw Exception('Включите службы геолокации на устройстве.');
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied) {
        throw Exception(
          'Разрешите доступ к местоположению, чтобы увидеть погоду рядом.',
        );
      }
      if (permission == LocationPermission.deniedForever) {
        throw Exception(
          'Доступ к геолокации отключён. Разрешите его в настройках устройства.',
        );
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 15),
        ),
      );
      final city = City(
        name: 'Моё местоположение',
        latitude: position.latitude,
        longitude: position.longitude,
      );
      await _loadWeather(city);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString().replaceFirst('Exception: ', '');
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(_error!)));
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final weather = _weather;
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFEAF1FF), _pale, Color(0xFFF8FAFD)],
            stops: [0, .42, 1],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1080),
              child: CustomScrollView(
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(24, 22, 24, 36),
                    sliver: SliverList.list(
                      children: [
                        _buildHeader(),
                        const SizedBox(height: 20),
                        _searchBox(),
                        const SizedBox(height: 20),
                        if (_query.trim().length >= 2)
                          _buildSearchResults()
                        else if (weather != null) ...[
                          _buildHero(weather),
                          const SizedBox(height: 18),
                          _buildHighlights(weather),
                          const SizedBox(height: 18),
                          _buildHourly(weather),
                          const SizedBox(height: 18),
                          _buildWeekly(weather),
                          const SizedBox(height: 20),
                          Center(
                            child: Text(
                              'Данные: Open-Meteo  ·  Обновлено ${_formatTime(weather.updatedAt)}',
                              style: const TextStyle(
                                color: _muted,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ] else if (_loading) ...[
                          const SizedBox(height: 140),
                          const Center(child: CircularProgressIndicator()),
                          const SizedBox(height: 180),
                        ] else
                          _buildError(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(15),
            boxShadow: [
              BoxShadow(color: _blue.withValues(alpha: .11), blurRadius: 18),
            ],
          ),
          child: const Icon(Icons.wb_sunny_rounded, color: Color(0xFFFFB547)),
        ),
        const SizedBox(width: 12),
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'атмосфера',
              style: TextStyle(
                color: _ink,
                fontSize: 18,
                fontWeight: FontWeight.w800,
                letterSpacing: -.5,
              ),
            ),
            Text(
              'ПОГОДА РЯДОМ',
              style: TextStyle(
                color: _muted,
                fontSize: 9,
                letterSpacing: 1.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const Spacer(),
        if (_loading && _weather != null)
          const Padding(
            padding: EdgeInsets.only(right: 12),
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        IconButton(
          tooltip: 'Обновить прогноз',
          onPressed: _loading ? null : () => _loadWeather(_selectedCity),
          icon: const Icon(Icons.refresh_rounded),
          style: IconButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: _ink,
          ),
        ),
      ],
    );
  }

  Widget _buildHero(WeatherSnapshot weather) {
    final isWide = MediaQuery.sizeOf(context).width > 650;
    return Container(
      padding: EdgeInsets.all(isWide ? 34 : 24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: weather.isDay
              ? const [Color(0xFF6FA4F7), Color(0xFF496FE1), Color(0xFF735DDB)]
              : const [Color(0xFF21385F), Color(0xFF364B83), Color(0xFF514D9B)],
        ),
        boxShadow: [
          BoxShadow(
            color: _blue.withValues(alpha: .22),
            blurRadius: 35,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    const Icon(
                      Icons.location_on_rounded,
                      color: Colors.white70,
                      size: 18,
                    ),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        weather.city.fullName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              _locationButton(),
            ],
          ),
          const SizedBox(height: 28),
          if (isWide)
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(child: _heroTemperature(weather)),
                Padding(
                  padding: const EdgeInsets.only(right: 35),
                  child: _weatherIllustration(
                    weather.code,
                    weather.isDay,
                    size: 142,
                  ),
                ),
              ],
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  heightFactor: .8,
                  child: _weatherIllustration(
                    weather.code,
                    weather.isDay,
                    size: 100,
                  ),
                ),
                Transform.translate(
                  offset: const Offset(0, -8),
                  child: _heroTemperature(weather),
                ),
              ],
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                _weatherDescription(weather.code),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 10),
              const Text('·', style: TextStyle(color: Colors.white70)),
              const SizedBox(width: 10),
              Text(
                'Ощущается как ${weather.feelsLike.round()}°',
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _heroTemperature(WeatherSnapshot weather) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _weekdayAndDate(weather.updatedAt),
          style: const TextStyle(color: Colors.white70, fontSize: 14),
        ),
        const SizedBox(height: 3),
        Text(
          '${weather.temperature.round()}°',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 82,
            height: 1,
            fontWeight: FontWeight.w300,
            letterSpacing: -5,
          ),
        ),
      ],
    );
  }

  Widget _locationButton() {
    return Tooltip(
      message: 'Погода по моему местоположению',
      child: Material(
        color: Colors.white.withValues(alpha: .16),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: _locating ? null : _useCurrentLocation,
          borderRadius: BorderRadius.circular(14),
          child: SizedBox(
            width: 42,
            height: 42,
            child: Center(
              child: _locating
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(
                      Icons.near_me_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _searchBox() {
    return Column(
      children: [
        Container(
          height: 52,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(17),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF243B68).withValues(alpha: .045),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: TextField(
            controller: _searchController,
            focusNode: _searchFocus,
            onChanged: _onSearchChanged,
            onSubmitted: _submitSearch,
            style: const TextStyle(color: _ink, fontSize: 14),
            cursorColor: _blue,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Найти город…',
              hintStyle: const TextStyle(color: _muted, fontSize: 14),
              prefixIcon: const Icon(Icons.search_rounded, color: _blue),
              suffixIcon: _searching
                  ? const Padding(
                      padding: EdgeInsets.all(16),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: _blue,
                        ),
                      ),
                    )
                  : _query.isNotEmpty
                  ? IconButton(
                      onPressed: () {
                        _searchController.clear();
                        _onSearchChanged('');
                      },
                      icon: const Icon(Icons.close_rounded, color: _muted),
                    )
                  : null,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 15),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSearchResults() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconButton(
              onPressed: () {
                _searchController.clear();
                _onSearchChanged('');
              },
              icon: const Icon(Icons.arrow_back_rounded),
            ),
            const SizedBox(width: 4),
            const Text(
              'Результаты поиска',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: _ink,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (_searchError != null)
          _emptyCard('Поиск временно недоступен', _searchError!)
        else if (_searching)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(36),
              child: CircularProgressIndicator(),
            ),
          )
        else if (_suggestions.isEmpty)
          _emptyCard(
            'Города не найдены',
            'Попробуйте изменить запрос или проверьте написание.',
          )
        else
          ..._suggestions.map(
            (city) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 8,
                  ),
                  leading: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEDF2FF),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.location_city_rounded,
                      color: _blue,
                    ),
                  ),
                  title: Text(
                    city.name,
                    style: const TextStyle(
                      color: _ink,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  subtitle: Text(
                    city.subtitle,
                    style: const TextStyle(color: _muted),
                  ),
                  trailing: const Icon(
                    Icons.arrow_forward_ios_rounded,
                    color: _muted,
                    size: 15,
                  ),
                  onTap: () {
                    _searchFocus.unfocus();
                    _loadWeather(city);
                  },
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildHighlights(WeatherSnapshot weather) {
    final items = [
      _HighlightData(
        Icons.air_rounded,
        'Ветер',
        '${weather.wind.round()} км/ч',
      ),
      _HighlightData(
        Icons.water_drop_outlined,
        'Влажность',
        '${weather.humidity}%',
      ),
      _HighlightData(
        Icons.wb_twilight_rounded,
        'УФ-индекс',
        weather.uvIndex.toStringAsFixed(0),
      ),
      _HighlightData(Icons.wb_sunny_outlined, 'Восход', weather.sunrise),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth > 680 ? 4 : 2;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: items.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            mainAxisExtent: 90,
          ),
          itemBuilder: (context, index) {
            final item = items[index];
            return _Surface(
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEDF2FF),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(item.icon, color: _blue, size: 21),
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.label,
                          style: const TextStyle(color: _muted, fontSize: 12),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          item.value,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _ink,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildHourly(WeatherSnapshot weather) {
    return _Surface(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('На сегодня', 'ПОЧАСОВОЙ ПРОГНОЗ'),
          const SizedBox(height: 18),
          SizedBox(
            height: 125,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: weather.hourly.length,
              separatorBuilder: (context, index) => const SizedBox(width: 22),
              itemBuilder: (context, index) {
                final hour = weather.hourly[index];
                return SizedBox(
                  width: 45,
                  child: Column(
                    children: [
                      Text(
                        index == 0 ? 'Сейчас' : hour.time,
                        style: TextStyle(
                          color: index == 0 ? _blue : _muted,
                          fontSize: 11,
                          fontWeight: index == 0
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Icon(
                        _weatherIcon(hour.code, true),
                        color: _weatherColor(hour.code),
                        size: 22,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '${hour.temperature.round()}°',
                        style: const TextStyle(
                          color: _ink,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      if (hour.precipitation > 0)
                        Text(
                          '${hour.precipitation}%',
                          style: const TextStyle(color: _blue, fontSize: 10),
                        )
                      else
                        const SizedBox(height: 12),
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

  Widget _buildWeekly(WeatherSnapshot weather) {
    return _Surface(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Ближайшие дни', 'ПРОГНОЗ НА 7 ДНЕЙ'),
          const SizedBox(height: 12),
          ...weather.daily.asMap().entries.map((entry) {
            final index = entry.key;
            final day = entry.value;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 9),
              child: Row(
                children: [
                  SizedBox(
                    width: 84,
                    child: Text(
                      index == 0 ? 'Сегодня' : _weekday(day.date),
                      style: TextStyle(
                        color: index == 0 ? _ink : const Color(0xFF52617C),
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    _weatherIcon(day.code, true),
                    color: _weatherColor(day.code),
                    size: 21,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _weatherDescription(day.code),
                      style: const TextStyle(color: _muted, fontSize: 12),
                    ),
                  ),
                  Text(
                    '${day.min.round()}°',
                    style: const TextStyle(color: _muted, fontSize: 13),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 82,
                    child: Row(
                      children: [
                        Expanded(
                          child: Container(
                            height: 5,
                            decoration: BoxDecoration(
                              color: const Color(0xFFE8EDF6),
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${day.max.round()}°',
                          style: const TextStyle(
                            color: _ink,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title, String eyebrow) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: _ink,
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
        const Spacer(),
        Text(
          eyebrow,
          style: const TextStyle(
            color: _muted,
            fontSize: 9,
            letterSpacing: 1,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _buildError() {
    return _emptyCard(
      _error ?? 'Что-то пошло не так',
      'Проверьте интернет и попробуйте обновить прогноз.',
      action: true,
    );
  }

  Widget _emptyCard(String title, String subtitle, {bool action = false}) {
    return _Surface(
      padding: const EdgeInsets.all(26),
      child: Column(
        children: [
          const Icon(Icons.cloud_off_rounded, color: _blue, size: 38),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: _ink,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(color: _muted, fontSize: 13),
          ),
          if (action) ...[
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => _loadWeather(_selectedCity),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Попробовать снова'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _weatherIllustration(int code, bool isDay, {required double size}) {
    final icon = _weatherIcon(code, isDay);
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: size * .82,
            height: size * .82,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: .10),
            ),
          ),
          Icon(
            icon,
            color: _weatherColor(code),
            size: size * .68,
            shadows: const [
              Shadow(
                color: Colors.black12,
                blurRadius: 12,
                offset: Offset(0, 5),
              ),
            ],
          ),
          if (code < 3 && isDay)
            Positioned(
              top: size * .12,
              right: size * .12,
              child: Icon(
                Icons.auto_awesome_rounded,
                color: Colors.white.withValues(alpha: .85),
                size: size * .15,
              ),
            ),
        ],
      ),
    );
  }
}

class _Surface extends StatelessWidget {
  const _Surface({
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      boxShadow: [
        BoxShadow(
          color: const Color(0xFF243B68).withValues(alpha: .045),
          blurRadius: 20,
          offset: const Offset(0, 8),
        ),
      ],
    ),
    child: child,
  );
}

class _HighlightData {
  const _HighlightData(this.icon, this.label, this.value);
  final IconData icon;
  final String label;
  final String value;
}

IconData _weatherIcon(int code, bool isDay) {
  if (code == 0) return isDay ? Icons.wb_sunny_rounded : Icons.nightlight_round;
  if (code <= 2) return isDay ? Icons.cloud_rounded : Icons.nights_stay_rounded;
  if (code == 3) return Icons.cloud_rounded;
  if (code == 45 || code == 48) return Icons.foggy;
  if (code >= 51 && code <= 67 || code >= 80 && code <= 82) {
    return Icons.umbrella_rounded;
  }
  if (code >= 71 && code <= 77 || code >= 85 && code <= 86) {
    return Icons.ac_unit_rounded;
  }
  if (code >= 95) {
    return Icons.thunderstorm_rounded;
  }
  return Icons.cloud_rounded;
}

Color _weatherColor(int code) {
  if (code == 0) return const Color(0xFFFFC85A);
  if (code <= 3) return const Color(0xFF9DAFC9);
  if (code >= 71 && code <= 77 || code >= 85 && code <= 86) {
    return const Color(0xFF72BCEB);
  }
  if (code >= 95) {
    return const Color(0xFF8294E5);
  }
  return const Color(0xFF6F9DD6);
}

String _weatherDescription(int code) {
  if (code == 0) return 'Ясно';
  if (code == 1) return 'Преимущественно ясно';
  if (code == 2) return 'Переменная облачность';
  if (code == 3) return 'Пасмурно';
  if (code == 45 || code == 48) return 'Туман';
  if (code >= 51 && code <= 55) return 'Морось';
  if (code >= 56 && code <= 57) return 'Ледяная морось';
  if (code >= 61 && code <= 65) return 'Дождь';
  if (code >= 66 && code <= 67) return 'Ледяной дождь';
  if (code >= 71 && code <= 77) return 'Снег';
  if (code >= 80 && code <= 82) return 'Ливень';
  if (code >= 85 && code <= 86) return 'Снегопад';
  if (code >= 95) return 'Гроза';
  return 'Переменная облачность';
}

String _weekdayAndDate(DateTime date) {
  const weekdays = [
    'Понедельник',
    'Вторник',
    'Среда',
    'Четверг',
    'Пятница',
    'Суббота',
    'Воскресенье',
  ];
  const months = [
    'января',
    'февраля',
    'марта',
    'апреля',
    'мая',
    'июня',
    'июля',
    'августа',
    'сентября',
    'октября',
    'ноября',
    'декабря',
  ];
  return '${weekdays[date.weekday - 1]}, ${date.day} ${months[date.month - 1]}';
}

String _weekday(DateTime date) {
  const weekdays = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];
  return weekdays[date.weekday - 1];
}

String _formatTime(DateTime date) =>
    '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

String _networkErrorMessage(Object error, {bool searching = false}) {
  if (error is TimeoutException) {
    return searching
        ? 'Поиск города занял больше времени, чем обычно. Проверьте интернет и попробуйте ещё раз.'
        : 'Прогноз загружается дольше обычного. Проверьте интернет и попробуйте ещё раз.';
  }
  if (error is http.ClientException) {
    return searching
        ? 'Не удалось выполнить поиск. Проверьте интернет и попробуйте ещё раз.'
        : 'Не удалось подключиться к сервису погоды. Проверьте интернет и попробуйте ещё раз.';
  }
  return error.toString().replaceFirst('Exception: ', '');
}
