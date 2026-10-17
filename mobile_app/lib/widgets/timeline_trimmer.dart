import 'package:flutter/material.dart';

class TimelineTrimmer extends StatelessWidget {
  final Duration videoTotalDuration;
  final Duration startTrim;
  final Duration endTrim;
  final Duration currentPosition;
  final Function(Duration start, Duration end) onTrimChanged;
  final Function(Duration seekTo)? onSeek;

  const TimelineTrimmer({
    super.key,
    required this.videoTotalDuration,
    required this.startTrim,
    required this.endTrim,
    required this.currentPosition,
    required this.onTrimChanged,
    this.onSeek,
  });

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final totalSec = videoTotalDuration.inSeconds.toDouble().clamp(1.0, 7200.0);
    final startSec = startTrim.inSeconds.toDouble().clamp(0.0, totalSec - 5.0);
    final endSec = endTrim.inSeconds.toDouble().clamp(startSec + 5.0, totalSec);
    final clipDuration = endTrim - startTrim;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2C),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.content_cut_rounded, color: Colors.amber, size: 18),
                  const SizedBox(width: 8),
                  const Text(
                    'Trim Durasi Klip',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.amber.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.amber.withOpacity(0.5)),
                ),
                child: Text(
                  '${clipDuration.inSeconds} detik',
                  style: const TextStyle(
                    color: Colors.amber,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Range Slider
          RangeSlider(
            values: RangeValues(startSec, endSec),
            min: 0.0,
            max: totalSec,
            activeColor: Colors.amber,
            inactiveColor: Colors.white24,
            labels: RangeLabels(
              _formatDuration(Duration(seconds: startSec.round())),
              _formatDuration(Duration(seconds: endSec.round())),
            ),
            onChanged: (RangeValues values) {
              if (values.end - values.start >= 5.0) {
                final newStart = Duration(seconds: values.start.round());
                final newEnd = Duration(seconds: values.end.round());
                onTrimChanged(newStart, newEnd);
                onSeek?.call(newStart);
              }
            },
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Mulai: ${_formatDuration(startTrim)}',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              Text(
                'Posisi: ${_formatDuration(currentPosition)}',
                style: const TextStyle(color: Colors.amber, fontSize: 12, fontWeight: FontWeight.bold),
              ),
              Text(
                'Selesai: ${_formatDuration(endTrim)}',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
