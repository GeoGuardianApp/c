import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';

class MediaViewer extends StatefulWidget {
  final String mediaUrl;
  final String mediaType;

  const MediaViewer({Key? key, required this.mediaUrl, required this.mediaType})
      : super(key: key);

  @override
  _MediaViewerState createState() => _MediaViewerState();
}

class _MediaViewerState extends State<MediaViewer> {
  VideoPlayerController? _videoController;
  ChewieController? _chewieController;

  @override
  void initState() {
    super.initState();
    if (widget.mediaType == 'video') {
      _videoController = VideoPlayerController.network(widget.mediaUrl)
        ..initialize().then((_) {
          setState(() {
            _chewieController = ChewieController(
              videoPlayerController: _videoController!,
              autoPlay: true,
              looping: false,
              aspectRatio: _videoController!.value.aspectRatio,
            );
          });
        });
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    _chewieController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text("Media Viewer"),
        backgroundColor: Colors.black,
      ),
      body: Center(
        child: widget.mediaType == 'image'
            ? PhotoView(
                imageProvider: NetworkImage(widget.mediaUrl),
                backgroundDecoration: const BoxDecoration(color: Colors.black),
              )
            : _chewieController != null
                ? Chewie(controller: _chewieController!)
                : const CircularProgressIndicator(),
      ),
    );
  }
}
