import 'package:shared_preferences/shared_preferences.dart';

enum CameraFilter {
  normal,
  warm,
  cool,
  blackAndWhite,
  sepia,
  vintage,
  highContrast
}

extension CameraFilterLabel on CameraFilter {
  String get label => switch (this) {
        CameraFilter.normal => 'Normal',
        CameraFilter.warm => 'Warm',
        CameraFilter.cool => 'Cool',
        CameraFilter.blackAndWhite => 'Black & White',
        CameraFilter.sepia => 'Sepia',
        CameraFilter.vintage => 'Vintage',
        CameraFilter.highContrast => 'High Contrast',
      };
}

class CameraAdjustments {
  const CameraAdjustments({
    this.brightness = 0,
    this.contrast = 0,
    this.saturation = 0,
    this.filter = CameraFilter.normal,
  });

  final double brightness;
  final double contrast;
  final double saturation;
  final CameraFilter filter;

  CameraAdjustments copyWith(
          {double? brightness,
          double? contrast,
          double? saturation,
          CameraFilter? filter}) =>
      CameraAdjustments(
        brightness: brightness ?? this.brightness,
        contrast: contrast ?? this.contrast,
        saturation: saturation ?? this.saturation,
        filter: filter ?? this.filter,
      );

  static Future<CameraAdjustments> load() async {
    final prefs = await SharedPreferences.getInstance();
    final filterIndex = prefs.getInt('camera_filter') ?? 0;
    return CameraAdjustments(
      brightness: (prefs.getDouble('camera_brightness') ?? 0).clamp(-1, 1),
      contrast: (prefs.getDouble('camera_contrast') ?? 0).clamp(-1, 1),
      saturation: (prefs.getDouble('camera_saturation') ?? 0).clamp(-1, 1),
      filter: CameraFilter
          .values[filterIndex.clamp(0, CameraFilter.values.length - 1)],
    );
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.setDouble('camera_brightness', brightness),
      prefs.setDouble('camera_contrast', contrast),
      prefs.setDouble('camera_saturation', saturation),
      prefs.setInt('camera_filter', filter.index),
    ]);
  }

  static const _identity = <double>[
    1,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
    0,
    0,
    0,
    0,
    1,
    0
  ];

  List<double> get colorMatrix {
    final contrastFactor = 1 + contrast;
    final contrastOffset = 128 * (1 - contrastFactor);
    final saturationFactor = 1 + saturation;
    final inv = 1 - saturationFactor;
    final adjustment = <double>[
      contrastFactor * (0.213 * inv + saturationFactor),
      contrastFactor * 0.715 * inv,
      contrastFactor * 0.072 * inv,
      0,
      contrastOffset + brightness * 255,
      contrastFactor * 0.213 * inv,
      contrastFactor * (0.715 * inv + saturationFactor),
      contrastFactor * 0.072 * inv,
      0,
      contrastOffset + brightness * 255,
      contrastFactor * 0.213 * inv,
      contrastFactor * 0.715 * inv,
      contrastFactor * (0.072 * inv + saturationFactor),
      0,
      contrastOffset + brightness * 255,
      0,
      0,
      0,
      1,
      0,
    ];
    return _multiply(_filterMatrix, adjustment);
  }

  List<double> get _filterMatrix => switch (filter) {
        CameraFilter.normal => _identity,
        CameraFilter.warm => <double>[
            1.12,
            0,
            0,
            0,
            8,
            0,
            1.02,
            0,
            0,
            2,
            0,
            0,
            .90,
            0,
            -4,
            0,
            0,
            0,
            1,
            0
          ],
        CameraFilter.cool => <double>[
            .90,
            0,
            0,
            0,
            -4,
            0,
            1.02,
            0,
            0,
            2,
            0,
            0,
            1.12,
            0,
            8,
            0,
            0,
            0,
            1,
            0
          ],
        CameraFilter.blackAndWhite => <double>[
            .213,
            .715,
            .072,
            0,
            0,
            .213,
            .715,
            .072,
            0,
            0,
            .213,
            .715,
            .072,
            0,
            0,
            0,
            0,
            0,
            1,
            0
          ],
        CameraFilter.sepia => <double>[
            .393,
            .769,
            .189,
            0,
            0,
            .349,
            .686,
            .168,
            0,
            0,
            .272,
            .534,
            .131,
            0,
            0,
            0,
            0,
            0,
            1,
            0
          ],
        CameraFilter.vintage => <double>[
            .9,
            .5,
            .1,
            0,
            12,
            .3,
            .8,
            .1,
            0,
            8,
            .2,
            .3,
            .5,
            0,
            -2,
            0,
            0,
            0,
            1,
            0
          ],
        CameraFilter.highContrast => <double>[
            1.5,
            0,
            0,
            0,
            -64,
            0,
            1.5,
            0,
            0,
            -64,
            0,
            0,
            1.5,
            0,
            -64,
            0,
            0,
            0,
            1,
            0
          ],
      };

  static List<double> _multiply(List<double> left, List<double> right) {
    final result = List<double>.filled(20, 0);
    for (var row = 0; row < 4; row++) {
      for (var column = 0; column < 5; column++) {
        var value = column == 4 ? left[row * 5 + 4] : 0.0;
        for (var index = 0; index < 4; index++) {
          value += left[row * 5 + index] * right[index * 5 + column];
        }
        result[row * 5 + column] = value;
      }
    }
    return result;
  }
}
