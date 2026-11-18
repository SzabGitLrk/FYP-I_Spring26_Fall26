import 'package:flutter/material.dart';
import '../services/camera_adjustments.dart';

Future<CameraAdjustments?> showCameraAdjustments(
  BuildContext context,
  CameraAdjustments initial,
) =>
    showModalBottomSheet<CameraAdjustments>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CameraAdjustmentsSheet(initial: initial),
    );

class _CameraAdjustmentsSheet extends StatefulWidget {
  const _CameraAdjustmentsSheet({required this.initial});
  final CameraAdjustments initial;
  @override
  State<_CameraAdjustmentsSheet> createState() =>
      _CameraAdjustmentsSheetState();
}

class _CameraAdjustmentsSheetState extends State<_CameraAdjustmentsSheet> {
  late CameraAdjustments _value = widget.initial;

  Widget _slider(String label, double value, ValueChanged<double> onChanged) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$label  ${value.toStringAsFixed(1)}'),
          Slider(
              value: value,
              min: -1,
              max: 1,
              divisions: 20,
              label: value.toStringAsFixed(1),
              onChanged: onChanged),
        ],
      );

  @override
  Widget build(BuildContext context) => SafeArea(
        top: false,
        child: Container(
          padding: EdgeInsets.fromLTRB(
              20, 12, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
          decoration: const BoxDecoration(
            color: Color(0xFF121A2F),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SingleChildScrollView(
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Center(
                    child: Container(
                        width: 44,
                        height: 4,
                        decoration: BoxDecoration(
                            color: Colors.white24,
                            borderRadius: BorderRadius.circular(4)))),
                const SizedBox(height: 16),
                const Text('Camera adjustments',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                _slider(
                    'Brightness',
                    _value.brightness,
                    (value) => setState(
                        () => _value = _value.copyWith(brightness: value))),
                _slider(
                    'Contrast',
                    _value.contrast,
                    (value) => setState(
                        () => _value = _value.copyWith(contrast: value))),
                _slider(
                    'Saturation',
                    _value.saturation,
                    (value) => setState(
                        () => _value = _value.copyWith(saturation: value))),
                const SizedBox(height: 4),
                const Text('Filter',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: CameraFilter.values
                        .map((filter) => ChoiceChip(
                              label: Text(filter.label),
                              selected: _value.filter == filter,
                              onSelected: (_) => setState(() =>
                                  _value = _value.copyWith(filter: filter)),
                            ))
                        .toList()),
                const SizedBox(height: 20),
                Row(children: [
                  TextButton(
                      onPressed: () =>
                          setState(() => _value = const CameraAdjustments()),
                      child: const Text('Reset')),
                  const Spacer(),
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel')),
                  const SizedBox(width: 8),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, _value),
                      child: const Text('Apply')),
                ]),
              ])),
        ),
      );
}
