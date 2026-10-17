import 'dart:io';
import 'package:flutter/material.dart';
import '../models/clip_model.dart';
import '../models/layout_model.dart';
import '../models/subtitle_style_model.dart';
import '../services/youtube_service.dart';
import 'clip_editor_screen.dart';
import 'render_progress_screen.dart';

class ClipSelectionScreen extends StatefulWidget {
  final VideoMetaData videoMeta;
  final File sourceVideoFile;
  final List<ClipSegment> clips;

  const ClipSelectionScreen({
    super.key,
    required this.videoMeta,
    required this.sourceVideoFile,
    required this.clips,
  });

  @override
  State<ClipSelectionScreen> createState() => _ClipSelectionScreenState();
}

class _ClipSelectionScreenState extends State<ClipSelectionScreen> {
  late Set<String> _selectedClipIds;

  @override
  void initState() {
    super.initState();
    // Default: Semua klip dicentang untuk kemudahan user
    _selectedClipIds = widget.clips.map((c) => c.id).toSet();
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  void _toggleSelectAll() {
    setState(() {
      if (_selectedClipIds.length == widget.clips.length) {
        _selectedClipIds.clear();
      } else {
        _selectedClipIds = widget.clips.map((c) => c.id).toSet();
      }
    });
  }

  void _proceedToRender() {
    final selectedClips = widget.clips.where((c) => _selectedClipIds.contains(c.id)).toList();
    if (selectedClips.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Silakan pilih minimal 1 klip untuk dirender!')),
      );
      return;
    }

    // Default configuration for batch render
    final defaultLayout = LayoutConfig(
      template: KomposisiTemplate.layarPenuh,
      cropPosition: 0.50,
      hook: HookConfig(text: selectedClips.first.hook, color: Colors.white, durationSeconds: 2.5),
      watermark: WatermarkConfig(text: '@channelmu', position: 'Bawah'),
    );

    final defaultStyle = SubtitleStyleConfig(
      preset: SubtitlePresetType.bold,
      fontFamily: SubtitleFontFamily.anton,
      fontSize: 90.0,
      textColor: Colors.white,
      activeWordColor: const Color(0xFFFFDF00),
      strokeColor: Colors.black,
      strokeWidth: 3.5,
      position: SubtitlePosition.bawah,
      bgType: SubtitleBgType.solid,
      bgColor: const Color(0xFFFFD600),
      wordByWord: false,
      selectedStyleId: 'beast',
    );

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => RenderProgressScreen(
          sourceVideoFile: widget.sourceVideoFile,
          clip: selectedClips.first,
          layout: defaultLayout,
          subtitleStyle: defaultStyle,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final allSelected = _selectedClipIds.length == widget.clips.length;

    return Scaffold(
      backgroundColor: const Color(0xFF111118),
      appBar: AppBar(
        title: const Text('Review Klip yang Mau Dirender', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
        backgroundColor: const Color(0xFF191924),
        actions: [
          TextButton(
            onPressed: _toggleSelectAll,
            child: Text(
              allSelected ? 'Batal Semua' : 'Pilih Semua',
              style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Header Info Card
            Container(
              padding: const EdgeInsets.all(16),
              margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E2C),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white12),
              ),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.network(
                      widget.videoMeta.thumbnailUrl,
                      width: 90,
                      height: 60,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 90,
                        height: 60,
                        color: Colors.black26,
                        child: const Icon(Icons.movie, color: Colors.white54),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.videoMeta.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${widget.videoMeta.author} • ${widget.clips.length} Klip Siap Dirender',
                          style: const TextStyle(color: Colors.amber, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Instruction Banner
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.check_box_outlined, color: Colors.amber, size: 18),
                  const SizedBox(width: 8),
                  const Text(
                    'Centang klip yang ingin dirender, lalu klik Continue:',
                    style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                ],
              ),
            ),

            // Clips List
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: widget.clips.length,
                itemBuilder: (context, index) {
                  final clip = widget.clips[index];
                  final isChecked = _selectedClipIds.contains(clip.id);
                  final duration = clip.endTime - clip.startTime;

                  return InkWell(
                    onTap: () {
                      setState(() {
                        if (isChecked) {
                          _selectedClipIds.remove(clip.id);
                        } else {
                          _selectedClipIds.add(clip.id);
                        }
                      });
                    },
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 14),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1B1B26),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isChecked
                              ? Colors.amber
                              : Colors.white12,
                          width: isChecked ? 1.8 : 1.0,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Top Row: Checkbox, Viral Score Badge, Durasi
                          Row(
                            children: [
                              // Checkbox
                              SizedBox(
                                width: 24,
                                height: 24,
                                child: Checkbox(
                                  value: isChecked,
                                  activeColor: Colors.amber,
                                  checkColor: Colors.black,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
                                  onChanged: (val) {
                                    setState(() {
                                      if (val == true) {
                                        _selectedClipIds.add(clip.id);
                                      } else {
                                        _selectedClipIds.remove(clip.id);
                                      }
                                    });
                                  },
                                ),
                              ),
                              const SizedBox(width: 10),

                              // Virality Score Badge
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.amber.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.local_fire_department, color: Colors.amber, size: 16),
                                    const SizedBox(width: 4),
                                    Text(
                                      '${(clip.viralityScore * 10).toInt()} / 100 Skor Viral AI',
                                      style: const TextStyle(
                                        color: Colors.amber,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Spacer(),

                              // Durasi (menit berapa sampai menit berapa)
                              Text(
                                '${_formatDuration(clip.startTime)} - ${_formatDuration(clip.endTime)} (${duration.inSeconds}s)',
                                style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),

                          // Judul Klip
                          Text(
                            clip.title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 6),

                          // Ringkasan / Hook
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.black38,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'Hook: ${clip.hook}',
                              style: const TextStyle(
                                color: Colors.amberAccent,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),

                          // Ringkasan Viral Reason
                          Text(
                            clip.viralReason,
                            style: const TextStyle(color: Colors.white60, fontSize: 13),
                          ),
                          const SizedBox(height: 12),

                          // Quick Studio Editor Button
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.amber,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              ),
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => ClipEditorScreen(
                                      sourceVideoFile: widget.sourceVideoFile,
                                      clip: clip,
                                      totalVideoDuration: widget.videoMeta.duration,
                                    ),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.tune_rounded, size: 18),
                              label: const Text(
                                'Edit Teks & Gaya di Studio',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

            // Bottom Sticky Bar with CONTINUE Button
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF191924),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.4),
                    blurRadius: 10,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Klip Dipilih:',
                        style: TextStyle(color: Colors.white60, fontSize: 11),
                      ),
                      Text(
                        '${_selectedClipIds.length} dari ${widget.clips.length} Klip',
                        style: const TextStyle(
                          color: Colors.amber,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.amber,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 4,
                      ),
                      onPressed: _selectedClipIds.isNotEmpty ? _proceedToRender : null,
                      icon: const Icon(Icons.arrow_forward_rounded, size: 20),
                      label: const Text(
                        'CONTINUE (LANJUT RENDER)',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
