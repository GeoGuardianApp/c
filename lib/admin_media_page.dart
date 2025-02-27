import 'dart:io'; // Import the dart:io library for file system operations

import 'package:flutter/material.dart'; // Import Flutter's material design library
import 'package:cloud_firestore/cloud_firestore.dart'; // Import Cloud Firestore for database interaction
import 'package:excel/excel.dart'; // Import the excel package for creating Excel files
import 'package:path_provider/path_provider.dart'; // Import path_provider for getting device file paths
import 'package:open_file/open_file.dart'; // Import open_file for opening files

import 'media_viewer.dart'; // Import url_launcher to open URLs

// This is the admin page for viewing all pictures and media uploaded by users
class AdminMediaPage extends StatefulWidget {
  // Constructor that requires a key for widget identification
  const AdminMediaPage({super.key});

  // Creates the state object that contains the actual functionality
  @override
  State<AdminMediaPage> createState() => _AdminMediaPageState();
}

class _AdminMediaPageState extends State<AdminMediaPage>
    with AutomaticKeepAliveClientMixin {
  // This will hold our continuously updating stream of picture data
  late final Stream<List<PictureData>> _picturesStream;

  // Adding a key to help Flutter track and preserve the ListView's state
  final GlobalKey<_MediaListViewState> _listViewKey = GlobalKey();

  // Keep this page alive to prevent rebuilding when coming back from a media view
  @override
  bool get wantKeepAlive => true;

  // This method runs when the widget is first created
  @override
  void initState() {
    // Call the parent class's initState method
    super.initState();
    // Set up our data stream
    _initializeStream();
  }

  // This method sets up the stream of picture data from Firestore database
  void _initializeStream() {
    _picturesStream = FirebaseFirestore.instance
        // Get the 'user_picture' collection from Firestore
        .collection('user_picture')
        // Sort by timestamp, newest first
        .orderBy('timestamp', descending: true)
        // Listen for real-time updates
        .snapshots()
        // Convert each database snapshot into a list of PictureData objects
        .map((snapshot) => snapshot.docs.map((doc) {
              // Extract the data from each document
              final data = doc.data();
              // Create a PictureData object from the database fields
              return PictureData(
                // Get the URL of the picture/video
                url: data['url'],
                // Get username or use 'Anonymous' if not available
                username: data['username'] ?? 'Anonymous',
                // Convert the Firestore timestamp to a Dart DateTime with null safety
                timestamp: _parseTimestamp(data['timestamp']),
                // Get media type (image/video) or default to 'image'
                mediaType: data['mediaType'] ?? 'image',
              );
            }).toList());
  }

  // Helper method to safely parse timestamps
  DateTime _parseTimestamp(dynamic timestampField) {
    if (timestampField is Timestamp) {
      return timestampField.toDate();
    } else if (timestampField is double) {
      return DateTime.fromMillisecondsSinceEpoch(timestampField.toInt());
    } else {
      return DateTime.now();
    }
  }

  // Export pictures data to Excel
  Future<void> _exportToExcel(BuildContext context) async {
    try {
      // Get all documents from the 'user_picture' collection
      final QuerySnapshot snapshot =
          await FirebaseFirestore.instance.collection('user_picture').get();
      // Create a new Excel workbook
      final Excel excel = Excel.createExcel();
      // Create a sheet named 'Pictures'
      final Sheet sheet = excel['Pictures'];

      // Create headers for the Excel sheet
      sheet.appendRow(['Username', 'Media Type', 'URL', 'Timestamp']);
      // Define the time offset for Oman (4 hours ahead)
      final omaniOffset = const Duration(hours: 4);

      // Loop through each document and add data to the Excel sheet
      for (final doc in snapshot.docs) {
        // Get the data from the document
        final data = doc.data() as Map<String, dynamic>;
        DateTime timestamp =
            _parseTimestamp(data['timestamp']).add(omaniOffset);

        // Add a row with picture data to the Excel sheet
        sheet.appendRow([
          data['username'] ??
              'Anonymous', // Use 'Anonymous' if username is missing
          data['mediaType'] ?? 'image', // Use 'image' if mediaType is missing
          data['url'],
          timestamp.toString(),
        ]);
      }

      // Save the Excel file to the app's documents directory
      final Directory dir = await getApplicationDocumentsDirectory();
      final String path =
          '${dir.path}/pictures_${DateTime.now().millisecondsSinceEpoch}.xlsx';
      await File(path).writeAsBytes(excel.encode()!);
      // Open the Excel file
      await OpenFile.open(path);

      // Show a success message
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Exported to $path')),
      );
    } catch (e) {
      // Show an error message if export fails
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export failed: $e')),
      );
    }
  }

  // Build the admin pictures page UI
  @override
  Widget build(BuildContext context) {
    // Required super.build call for AutomaticKeepAliveClientMixin
    super.build(context);

    return Scaffold(
        appBar: AppBar(
          title: const Text('All Media'),
          backgroundColor: Theme.of(context).colorScheme.inversePrimary,
          foregroundColor: Colors.white, // White text/icons
          actions: [
            // Download button to export data to Excel
            IconButton(
              icon: const Icon(Icons.download),
              onPressed: () => _exportToExcel(context),
            ),
          ],
        ),
        // Use PageStorage to preserve scroll position and state
        body: PageStorage(
          bucket: PageStorageBucket(),
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.black, // Solid black background
            ),
            child: StreamBuilder<List<PictureData>>(
              stream: _picturesStream, // Get the stream of pictures
              builder: (context, snapshot) {
                // Show a loading indicator while waiting for data
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                // Show an error message if there's an error
                if (snapshot.hasError) return Text('Error: ${snapshot.error}');

                // Get the list of pictures from the snapshot
                final pictures = snapshot.data ?? [];

                // Use MediaListView with a key to preserve state
                return MediaListView(
                  key: _listViewKey,
                  pictures: pictures,
                );
              },
            ),
          ),
        ));
  }
}

// This is a specialized widget that displays the media list and prevents glitching
// when navigating back to this page after viewing an item
class MediaListView extends StatefulWidget {
  // This widget needs a list of PictureData objects to display
  final List<PictureData> pictures;

  // Constructor that requires a key and the pictures list
  const MediaListView({Key? key, required this.pictures}) : super(key: key);

  // Creates the state object that manages the list view
  @override
  State<MediaListView> createState() => _MediaListViewState();
}

// The state class for MediaListView that includes AutomaticKeepAliveClientMixin
// to prevent the widget from being destroyed when it's not visible
class _MediaListViewState extends State<MediaListView>
    with AutomaticKeepAliveClientMixin {
  // This tells Flutter to keep this widget's state alive even when not visible
  @override
  bool get wantKeepAlive => true;

  // Build method that creates the actual UI
  @override
  Widget build(BuildContext context) {
    // Required call for the mixin to work properly
    super.build(context);

    // Create a scrollable list of items with a PageStorageKey to preserve state
    return ListView.builder(
      // Add a key to maintain the scroll position
      key: PageStorageKey<String>('mediaListView'),
      // The number of items equals the number of pictures
      itemCount: widget.pictures.length,
      // Adding physics for better scrolling experience
      physics: const AlwaysScrollableScrollPhysics(),
      // Function that builds each item in the list
      itemBuilder: (context, index) {
        // Get the current picture data
        final picture = widget.pictures[index];
        // Create a card for better visual appearance
        return Hero(
          // Use the URL as a unique tag for the Hero animation
          tag: 'media_${picture.url}',
          child: Card(
            // Add spacing around each card
            margin: const EdgeInsets.symmetric(vertical: 5, horizontal: 10),
            // Dark gray background color for the card
            color: Colors.grey[900],
            // ListTile provides a standard layout for items in a list
            child: ListTile(
              // Add padding inside the list tile
              contentPadding: const EdgeInsets.all(8),
              // Show a video or image icon based on media type
              leading: Icon(
                picture.mediaType == 'video' ? Icons.videocam : Icons.image,
                color: Colors.white,
                size: 32,
              ),
              // Show the username as the title
              title: Text(
                'User: ${picture.username}',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              // Show additional details in the subtitle
              subtitle: Column(
                // Align text to the left
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Show the media type
                  Text(
                    'Type: ${picture.mediaType}',
                    style: const TextStyle(color: Colors.white70),
                  ),
                  // Show the timestamp
                  Text(
                    picture.timestamp.toLocal().toString(),
                    style: const TextStyle(color: Colors.white70),
                  ),
                  // Show the URL as selectable text so users can copy it
                  SelectableText(
                    picture.url,
                    style: const TextStyle(color: Colors.blue),
                  ),
                ],
              ),
              // Add a button to open the media in a browser or app
              trailing: IconButton(
                icon: const Icon(Icons.open_in_new, color: Colors.white),
                // When the button is pressed, open the URL
                onPressed: () => _openMedia(context, picture),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _openMedia(BuildContext context, PictureData picture) async {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => MediaViewer(
          mediaUrl: picture.url,
          mediaType: picture.mediaType,
        ),
      ),
    );
  }
}

// Data model for picture information
class PictureData {
  final String url;
  final String username;
  final DateTime timestamp;
  final String mediaType;

  PictureData({
    required this.url,
    required this.username,
    required this.timestamp,
    required this.mediaType,
  });
}
