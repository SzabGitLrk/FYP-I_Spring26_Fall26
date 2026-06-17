import 'package:flutter/services.dart';

class CityConfig {
  final String name;

  CityConfig(this.name);

  String get placesAsset => 'assets/cities/$name/places.json';
  String get tilesAsset => 'assets/cities/$name/tiles.mbtiles';
  String routeAsset(String slug) => 'assets/cities/$name/routes/$slug.json';

  static Future<CityConfig> load() async {
    final raw = await rootBundle.loadString('assets/active_city.txt');
    return CityConfig(raw.trim());
  }
}