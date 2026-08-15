import 'package:flutter/widgets.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import 'app.dart';

Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: '.env');

  final mapboxToken = dotenv.env['MAPBOX_ACCESS_TOKEN'] ?? '';
  MapboxOptions.setAccessToken(mapboxToken);

  MobileAds.instance.initialize();

  runApp(const ProviderScope(child: TerrangoApp()));
}
