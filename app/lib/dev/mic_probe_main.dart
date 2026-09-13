// Minimal microphone probe — its own entrypoint, so none of the app runs.
//
//   flutter run -t lib/dev/mic_probe_main.dart
//
// Why this exists: on device the room reports a local audio track that is
// enabled and attached, yet delivers `totalSamples=0.0` — a live microphone
// producing silence. Everything in the room path (socket, peers, TURN, seats,
// listen-only transitions) is a candidate, and testing through it costs a
// twenty-minute build per guess.
//
// So this removes all of it. One getUserMedia, one local RTCPeerConnection to
// make getStats produce a media-source entry, and the numbers on screen once a
// second. If totalSamples climbs here, capture is fine and the fault is in the
// room lifecycle. If it stays at zero, the fault is the capture itself and has
// nothing to do with rooms at all.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';

void main() => runApp(const MicProbeApp());

class MicProbeApp extends StatelessWidget {
  const MicProbeApp({super.key});

  @override
  Widget build(BuildContext context) => const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: MicProbePage(),
      );
}

class MicProbePage extends StatefulWidget {
  const MicProbePage({super.key});

  @override
  State<MicProbePage> createState() => _MicProbePageState();
}

class _MicProbePageState extends State<MicProbePage> {
  final List<String> _lines = [];
  MediaStream? _stream;
  RTCPeerConnection? _pc;
  Timer? _poll;

  void _log(String s) {
    // ignore: avoid_print
    print('🔬 MIC_PROBE | $s');
    if (!mounted) return;
    setState(() {
      _lines.insert(0, s);
      if (_lines.length > 40) _lines.removeLast();
    });
  }

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      final perm = await Permission.microphone.request();
      _log('permission: $perm');
      if (!perm.isGranted) return;

      // Exactly the constraints the app uses, so this reproduces its capture.
      _stream = await navigator.mediaDevices.getUserMedia({
        'audio': {
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
          'googEchoCancellation': true,
          'googEchoCancellation2': true,
          'googDAEchoCancellation': true,
          'googNoiseSuppression': true,
          'googAutoGainControl': true,
          'googHighpassFilter': true,
          'channelCount': 1,
        },
        'video': false,
      });

      final tracks = _stream!.getAudioTracks();
      _log('tracks=${tracks.length}');
      if (tracks.isEmpty) return;
      final t = tracks.first;
      _log('id=${t.id} enabled=${t.enabled} muted=${t.muted}');

      // getStats only reports a media-source once the track is attached to a
      // peer connection. No remote end is needed for that.
      _pc = await createPeerConnection({
        'iceServers': <Map<String, dynamic>>[],
        'sdpSemantics': 'unified-plan',
      });
      await _pc!.addTrack(t, _stream!);
      _log('attached to a local peer connection');

      _poll = Timer.periodic(const Duration(seconds: 1), (_) => _sample());
    } catch (e) {
      _log('FAILED: $e');
    }
  }

  Future<void> _sample() async {
    final pc = _pc;
    if (pc == null) return;
    try {
      for (final r in await pc.getStats()) {
        if (r.type == 'media-source') {
          // Print the WHOLE map: the key names differ between plugin versions
          // and guessing them is how the first run produced four nulls.
          _log(r.values.toString());
          return;
        }
      }
      _log('no media-source in stats yet');
    } catch (e) {
      _log('stats error: $e');
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    _pc?.close();
    for (final t in _stream?.getTracks() ?? const <MediaStreamTrack>[]) {
      t.stop();
    }
    _stream?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: const Color(0xFF14082B),
        appBar: AppBar(
          backgroundColor: const Color(0xFF2A1655),
          title: const Text('Mic probe'),
        ),
        body: ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: _lines.length,
          itemBuilder: (_, i) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Text(
              _lines[i],
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ),
      );
}
