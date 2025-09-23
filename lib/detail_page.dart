import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

class DetailPage extends StatefulWidget {
  final String imageUrl;

  const DetailPage({super.key, required this.imageUrl});

  @override
  State<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage> {
  static const MethodChannel _channel = MethodChannel(
    'wallpaper.channel/setter',
  );
  bool _busy = false;

  Future<String> _downloadToFile(String url) async {
    final dir = await getTemporaryDirectory();
    final filePath =
        '${dir.path}/wall_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final dio = Dio();
    await dio.download(url, filePath);
    return filePath;
  }

  Future<void> _setWallpaper(String screen) async {
    setState(() => _busy = true);
    try {
      final localPath = await _downloadToFile(widget.imageUrl);
      await _channel.invokeMethod('setWallpaper', {
        'path': localPath,
        'screen': screen, // 'home' | 'lock' | 'both'
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Wallpaper o\'rnatildi ($screen)')),
        );
      }
    } on PlatformException catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Xatolik: ${e.message}')));
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Xatolik yuz berdi')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black12,
      appBar: AppBar(iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('Preview', style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.black12,
      ),
      body: Column(
        children: [
          Expanded(
            child: Hero(
              tag: widget.imageUrl,
              child: CachedNetworkImage(
                imageUrl: widget.imageUrl,
                fit: BoxFit.cover,
                placeholder: (c, _) =>
                    const Center(child: CircularProgressIndicator()),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: _busy ? null : () => _setWallpaper('home'),
                      child: _busy
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Home screen'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _busy ? null : () => _setWallpaper('lock'),
                      child: const Text('Lock screen'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _busy ? null : () => _setWallpaper('both'),
                      child: const Text('Both'),
                    ),
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
