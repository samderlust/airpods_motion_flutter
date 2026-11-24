import 'dart:async';

import 'package:airpods_motion_flutter/airpods_motion_flutter.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(const AirPodsMotionExampleApp());
}

class AirPodsMotionExampleApp extends StatelessWidget {
  const AirPodsMotionExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AirPods Motion Telemetry',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: const TelemetryDashboardPage(),
    );
  }
}

class TelemetryDashboardPage extends StatefulWidget {
  const TelemetryDashboardPage({super.key});

  @override
  State<TelemetryDashboardPage> createState() => _TelemetryDashboardPageState();
}

class _TelemetryDashboardPageState extends State<TelemetryDashboardPage> {
  final AirPodsMotion _motion = AirPodsMotion();

  StreamSubscription<HeadphoneMotionSample>? _motionSub;
  StreamSubscription<HeadphoneDevice>? _deviceSub;

  HeadphoneDevice _device = HeadphoneDevice.disconnected;
  HeadphoneMotionSample? _sample;
  AirPodsFilterMode _filterMode = AirPodsFilterMode.oneEuro;
  int _sampleRateHz = 15;
  double _manualPitchDeg = 0;
  double _manualYawDeg = 0;

  @override
  void initState() {
    super.initState();
    _motionSub = _motion.motionStream.listen((sample) {
      if (mounted) {
        setState(() => _sample = sample);
      }
    });
    _deviceSub = _motion.deviceStream.listen((device) {
      if (mounted) {
        setState(() => _device = device);
      }
    });
    _refreshDevice();
  }

  @override
  void dispose() {
    _motionSub?.cancel();
    _deviceSub?.cancel();
    _motion.dispose();
    super.dispose();
  }

  Future<void> _refreshDevice() async {
    final device = await _motion.getDeviceInfo();
    if (mounted) {
      setState(() => _device = device);
    }
  }

  Future<void> _toggleTracking() async {
    if (_motion.isTracking) {
      await _motion.stopTracking();
    } else {
      await _motion.startTracking(
        config: AirPodsMotionConfig(
          sampleRateHz: _sampleRateHz,
          filterMode: _filterMode,
        ),
      );
    }
    await _refreshDevice();
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _updateConfig({
    AirPodsFilterMode? filterMode,
    int? sampleRateHz,
  }) async {
    setState(() {
      if (filterMode != null) _filterMode = filterMode;
      if (sampleRateHz != null) _sampleRateHz = sampleRateHz;
    });
    if (_motion.isTracking) {
      await _motion.startTracking(
        config: AirPodsMotionConfig(
          sampleRateHz: _sampleRateHz,
          filterMode: _filterMode,
        ),
      );
    }
  }

  Future<void> _replayDemoTrace() async {
    final baseMs = DateTime.now().millisecondsSinceEpoch;
    final trace = <HeadphoneMotionSample>[
      for (var i = 0; i < 8; i++)
        HeadphoneMotionSample(
          pitchDeg: (i - 3) * 4.0,
          rollDeg: 0,
          yawDeg: (i.isEven ? 1 : -1) * 8.0,
          accelerationMagnitude: 0.03,
          isCalibrated: true,
          isSimulated: true,
          timestampMs: baseMs + i * 80,
        ),
    ];
    await _motion.simulator.replayTrace(trace);
  }

  @override
  Widget build(BuildContext context) {
    final sample = _sample;
    return Scaffold(
      appBar: AppBar(
        title: const Text('AirPods Motion 6-DoF'),
        actions: [
          IconButton(
            onPressed: _refreshDevice,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh device info',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _DeviceStatusCard(
            device: _device,
            isSimulating: _motion.isSimulating,
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Controls & Filtering',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: _toggleTracking,
                        icon: Icon(
                          _motion.isTracking ? Icons.stop : Icons.play_arrow,
                        ),
                        label: Text(
                          _motion.isTracking
                              ? 'Stop Tracking'
                              : 'Start Tracking',
                        ),
                      ),
                      OutlinedButton(
                        onPressed: () async {
                          await _motion.calibrate();
                          await _refreshDevice();
                        },
                        child: const Text('Calibrate Zero'),
                      ),
                      TextButton(
                        onPressed: () async {
                          await _motion.resetCalibration();
                          await _refreshDevice();
                        },
                        child: const Text('Reset Calibration'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SegmentedButton<AirPodsFilterMode>(
                    segments: const [
                      ButtonSegment(
                        value: AirPodsFilterMode.none,
                        label: Text('Raw'),
                      ),
                      ButtonSegment(
                        value: AirPodsFilterMode.ema,
                        label: Text('EMA'),
                      ),
                      ButtonSegment(
                        value: AirPodsFilterMode.oneEuro,
                        label: Text('1-Euro'),
                      ),
                    ],
                    selected: {_filterMode},
                    onSelectionChanged: (selection) {
                      _updateConfig(filterMode: selection.first);
                    },
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children:
                        [10, 15, 30, 60].map((hz) {
                          return ChoiceChip(
                            label: Text('$hz Hz'),
                            selected: _sampleRateHz == hz,
                            onSelected: (_) => _updateConfig(sampleRateHz: hz),
                          );
                        }).toList(),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          _TelemetryCards(sample: sample),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Simulator & Replay',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton(
                        onPressed: () {
                          if (_motion.simulator.isRunning) {
                            _motion.simulator.stop();
                          } else {
                            _motion.simulator.startSyntheticLoop(
                              sampleRateHz: _sampleRateHz,
                            );
                          }
                          setState(() {});
                        },
                        child: Text(
                          _motion.simulator.isRunning
                              ? 'Stop Synthetic Loop'
                              : 'Start Synthetic Loop',
                        ),
                      ),
                      OutlinedButton(
                        onPressed: _replayDemoTrace,
                        child: const Text('Replay Demo Trace'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text('Manual Pitch: ${_manualPitchDeg.toStringAsFixed(1)}°'),
                  Slider(
                    value: _manualPitchDeg,
                    min: -45,
                    max: 45,
                    onChanged: (value) {
                      setState(() => _manualPitchDeg = value);
                      _motion.simulator.emitEuler(
                        pitchDeg: _manualPitchDeg,
                        yawDeg: _manualYawDeg,
                      );
                    },
                  ),
                  Text('Manual Yaw: ${_manualYawDeg.toStringAsFixed(1)}°'),
                  Slider(
                    value: _manualYawDeg,
                    min: -60,
                    max: 60,
                    onChanged: (value) {
                      setState(() => _manualYawDeg = value);
                      _motion.simulator.emitEuler(
                        pitchDeg: _manualPitchDeg,
                        yawDeg: _manualYawDeg,
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DeviceStatusCard extends StatelessWidget {
  const _DeviceStatusCard({required this.device, required this.isSimulating});

  final HeadphoneDevice device;
  final bool isSimulating;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.headphones),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    device.name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (device.isSimulated || isSimulating)
                  const Chip(label: Text('Simulated')),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                Chip(label: Text('Model: ${device.model.name}')),
                Chip(label: Text('Connected: ${device.isConnected}')),
                Chip(label: Text('Active: ${device.isActive}')),
                Chip(label: Text('Calibrated: ${device.isCalibrated}')),
                Chip(label: Text('Location: ${device.sensorLocation.name}')),
                Chip(label: Text('Rate: ${device.sampleRateHz} Hz')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TelemetryCards extends StatelessWidget {
  const _TelemetryCards({required this.sample});

  final HeadphoneMotionSample? sample;

  @override
  Widget build(BuildContext context) {
    final s = sample;
    if (s == null) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'No motion frames received yet. Start tracking or use the simulator.',
          ),
        ),
      );
    }

    String fmt(double v) => v.toStringAsFixed(2);
    String vec(HeadphoneVector3 v) => '(${fmt(v.x)}, ${fmt(v.y)}, ${fmt(v.z)})';

    return Column(
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Orientation (Euler Degrees)',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Pitch: ${fmt(s.pitchDeg)}°'),
                    Text('Roll: ${fmt(s.rollDeg)}°'),
                    Text('Yaw: ${fmt(s.yawDeg)}°'),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '6-DoF Vectors & Quaternion',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'Quaternion: (${fmt(s.quaternion.x)}, ${fmt(s.quaternion.y)}, '
                  '${fmt(s.quaternion.z)}, ${fmt(s.quaternion.w)})',
                ),
                Text('Rotation Rate (rad/s): ${vec(s.rotationRate)}'),
                Text('User Accel (G): ${vec(s.userAcceleration)}'),
                Text('Gravity (G): ${vec(s.gravity)}'),
                Text(
                  'Accel Magnitude: ${s.accelerationMagnitude.toStringAsFixed(3)} G',
                ),
                Text(
                  'Sensor: ${s.sensorLocation.name} • Calibrated: ${s.isCalibrated}',
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
