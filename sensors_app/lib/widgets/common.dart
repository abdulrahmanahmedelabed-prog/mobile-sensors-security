import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../platform/device.dart';

/// Arabic text for an error coming from a native stream.
String describeStreamError(Object error) {
  if (error is PlatformException) {
    return switch (error.code) {
      'UNAVAILABLE' => 'هذا الحساس غير موجود في جوالك.',
      'PERMISSION' => 'لم يُمنح الإذن المطلوب.',
      'DISABLED' => 'خدمة الموقع مغلقة. شغّلها من إعدادات الجوال.',
      _ => 'تعذّرت القراءة.',
    };
  }
  if (error is MissingPluginException) return 'هذه الميزة تعمل على جوال أندرويد فقط.';
  return 'تعذّرت القراءة.';
}

/// Listens to [stream] for as long as the widget is on screen, and rebuilds
/// with the latest value. The subscription (and so the native sensor) stops
/// when the page closes.
class LiveValue<T> extends StatefulWidget {
  const LiveValue({super.key, required this.stream, required this.builder, this.waiting});
  final Stream<T> stream;
  final Widget Function(BuildContext context, T value) builder;
  final Widget? waiting;

  @override
  State<LiveValue<T>> createState() => _LiveValueState<T>();
}

class _LiveValueState<T> extends State<LiveValue<T>> {
  late final Stream<T> _stream = widget.stream;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<T>(
      stream: _stream,
      builder: (context, snap) {
        if (snap.hasError) return Unavailable(message: describeStreamError(snap.error!));
        if (!snap.hasData) {
          return widget.waiting ??
              const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
        }
        return widget.builder(context, snap.data as T);
      },
    );
  }
}

class Unavailable extends StatelessWidget {
  const Unavailable({super.key, required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(children: [
        Icon(Icons.info_outline, color: Theme.of(context).colorScheme.error),
        const SizedBox(width: 12),
        Expanded(child: Text(message)),
      ]),
    );
  }
}

/// Shows [child] only once [permission] is granted; before that it explains
/// why the permission is needed and asks for it when the user taps.
class PermissionGate extends StatefulWidget {
  const PermissionGate({super.key, required this.permission, required this.reason, required this.child});
  final AppPermission permission;
  final String reason;
  final Widget child;

  @override
  State<PermissionGate> createState() => _PermissionGateState();
}

class _PermissionGateState extends State<PermissionGate> {
  bool? _granted;
  bool _denied = false;

  @override
  void initState() {
    super.initState();
    Device.instance.isGranted(widget.permission).then((g) {
      if (mounted) setState(() => _granted = g);
    }, onError: (_) {
      if (mounted) setState(() => _granted = false);
    });
  }

  Future<void> _ask() async {
    bool ok;
    try {
      ok = await Device.instance.request(widget.permission);
    } on PlatformException {
      ok = false;
    } on MissingPluginException {
      ok = false;
    }
    if (!mounted) return;
    setState(() {
      _granted = ok;
      _denied = !ok;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_granted == null) return const Center(child: CircularProgressIndicator());
    if (_granted!) return widget.child;
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Icon(Icons.lock_open, size: 40),
          const SizedBox(height: 8),
          Text('لماذا نحتاج هذا الإذن؟', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(widget.reason),
          const SizedBox(height: 8),
          const Text('القراءات تبقى في جوالك ولا تُحفظ ولا تُرسل إلى أي مكان.',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          FilledButton(onPressed: _ask, child: const Text('السماح')),
          if (_denied) ...[
            const SizedBox(height: 8),
            const Text('إذا رفضت مرتين فلن يظهر طلب الإذن مجددًا؛ يمكنك تفعيله من الإعدادات.'),
            TextButton(onPressed: Device.instance.openAppSettings, child: const Text('فتح إعدادات التطبيق')),
          ],
        ]),
      ),
    );
  }
}

/// A big reading with its unit and a label.
class Reading extends StatelessWidget {
  const Reading({super.key, required this.label, required this.value, this.unit = ''});
  final String label;
  final String value;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(children: [
      Text(label, style: t.labelLarge),
      Directionality(
        textDirection: TextDirection.ltr,
        child: Text.rich(TextSpan(children: [
          TextSpan(text: value, style: t.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
          if (unit.isNotEmpty) TextSpan(text: ' $unit', style: t.titleSmall),
        ])),
      ),
    ]);
  }
}

/// x / y / z readings in one row.
class AxesRow extends StatelessWidget {
  const AxesRow({super.key, required this.values, required this.unit, this.digits = 2});
  final List<double> values;
  final String unit;
  final int digits;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
        for (final (i, axis) in ['X', 'Y', 'Z'].indexed)
          if (i < values.length) Reading(label: axis, value: values[i].toStringAsFixed(digits), unit: unit),
      ]),
    );
  }
}

/// A horizontal meter from [min] to [max].
class Meter extends StatelessWidget {
  const Meter({super.key, required this.value, required this.min, required this.max, this.color});
  final double value;
  final double min;
  final double max;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final f = ((value - min) / (max - min)).clamp(0.0, 1.0);
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: LinearProgressIndicator(value: f, minHeight: 16, color: color),
    );
  }
}

/// Chips naming the sensors a feature uses.
class SensorChips extends StatelessWidget {
  const SensorChips({super.key, required this.names});
  final List<String> names;

  @override
  Widget build(BuildContext context) {
    return Wrap(spacing: 6, runSpacing: 4, children: [
      for (final n in names)
        Chip(
          label: Text(n, style: const TextStyle(fontSize: 12)),
          visualDensity: VisualDensity.compact,
          avatar: const Icon(Icons.sensors, size: 16),
        ),
    ]);
  }
}

class DemoScaffold extends StatelessWidget {
  const DemoScaffold({super.key, required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(padding: const EdgeInsets.all(16), children: children),
    );
  }
}

/// Subscriptions tied to a State's lifetime: data and errors trigger a
/// rebuild, and everything is cancelled (stopping the native sensors) on dispose.
mixin Listens<W extends StatefulWidget> on State<W> {
  final _subs = <StreamSubscription<Object?>>[];
  final errors = <String, Object>{};

  void listen<E>(String key, Stream<E> stream, void Function(E value) onData) {
    _subs.add(stream.listen(
      (e) {
        if (mounted) setState(() => onData(e));
      },
      onError: (Object e) {
        if (mounted) setState(() => errors[key] = e);
      },
    ));
  }

  Widget? errorFor(String key) {
    final e = errors[key];
    return e == null ? null : Unavailable(message: describeStreamError(e));
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }
}
