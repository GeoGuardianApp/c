import 'dart:io'; // Import the dart:io library for file system operations.

import 'package:flutter/material.dart'; // Import the Flutter material library for UI components.
import 'package:cloud_firestore/cloud_firestore.dart'; // Import the Cloud Firestore package for database interaction.
import 'package:excel/excel.dart'; // Import the excel package for creating and manipulating Excel files.
import 'package:path_provider/path_provider.dart'; // Import the path_provider package for getting platform-specific directory paths.
import 'package:open_file/open_file.dart'; // Import the open_file package for opening files with the default system application.

// Admin page for viewing all locations
class AdminLocationsPage extends StatelessWidget {
  const AdminLocationsPage({super.key});

  // Export location data to Excel
  Future<void> _exportToExcel(BuildContext context) async {
    try {
      // Fetch all documents from the 'user_locations' collection in Firestore
      final QuerySnapshot snapshot =
          await FirebaseFirestore.instance.collection('user_locations').get();
      // Create a new Excel workbook
      final Excel excel = Excel.createExcel();
      // Create a new sheet named 'Locations'
      final Sheet sheet = excel['Locations'];

      // Create headers for the Excel sheet
      sheet.appendRow([
        'Username',
        'UUID',
        'Installation Date',
        'Latitude',
        'Longitude',
        'Timestamp'
      ]);

      // Add location data to the Excel sheet
      final omaniOffset = const Duration(hours: 4); // Oman time zone offset
      for (final doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>; // Get document data
        final timestampField = data['timestamp']; // Get timestamp field
        DateTime timestamp;
        // Handle different timestamp field types (Timestamp or double)
        if (timestampField is Timestamp) {
          timestamp = timestampField
              .toDate()
              .add(omaniOffset); // Convert Firestore Timestamp to DateTime
        } else if (timestampField is double) {
          timestamp =
              DateTime.fromMillisecondsSinceEpoch(timestampField.toInt())
                  .add(omaniOffset); // Convert double to DateTime
        } else {
          timestamp = DateTime.now().add(
              omaniOffset); // Default to current time if timestamp is invalid
        }
        // Append a row with location data to the Excel sheet
        sheet.appendRow([
          data['username'] ??
              'Anonymous', // Use 'Anonymous' if username is null
          data['UUID'],
          data['installation_date'],
          data['latitude'],
          data['longitude'],
          timestamp.toString(),
        ]);
      }

      // Save and open the Excel file
      final Directory dir =
          await getApplicationDocumentsDirectory(); // Get app's document directory
      final String path =
          '${dir.path}/locations_${DateTime.now().millisecondsSinceEpoch}.xlsx'; // Create file path
      final File file = File(path); // Create File object
      await file.writeAsBytes(excel.encode()!); // Write Excel data to file
      // Open the file using the default app for Excel files.
      await OpenFile.open(path);
      if (!context.mounted) return; // Check if context is still valid
      // Show a SnackBar to indicate successful export
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Exported to $path')),
      );
    } catch (e) {
      // Show a SnackBar to indicate export failure
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export failed: $e')),
      );
    }
  }

  // Get stream of all location data
  Stream<List<LocationData>> _getAllLocations(FirebaseFirestore firestore) {
    // Get a stream of documents from the 'user_locations' collection, ordered by timestamp
    return firestore
        .collection('user_locations')
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snapshot) {
      // Map each document to a LocationData object
      return snapshot.docs.map((doc) {
        final data = doc.data() as Map; // Get document data
        final timestampField = data['timestamp']; // Get timestamp field
        final timestamp = timestampField is Timestamp
            ? timestampField.toDate() // Convert Firestore Timestamp to DateTime
            : DateTime.now(); // Default to current time if timestamp is invalid

        // Handle potential null installation_date
        final installationDate = data.containsKey('installation_date') &&
                data['installation_date'] != null
            ? data['installation_date'] as String // Get installation date
            : 'Unknown Installation Date'; // Provide a default value

        // Create and return a LocationData object
        return LocationData(
          latitude: data['latitude'] as double,
          longitude: data['longitude'] as double,
          timestamp: timestamp,
          username:
              data.containsKey('username') ? data['username'] as String : null,
          password:
              data.containsKey('password') ? data['password'] as String : null,
          deviceId:
              data.containsKey('UUID') ? data['UUID'] as String : 'unknown',
          installationDate: installationDate,
        );
      }).toList(); // Convert the iterable of LocationData to a list
    });
  }

  // Build the admin locations page UI
  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          title: const Text('All Locations'),
          backgroundColor: Theme.of(context)
              .colorScheme
              .inversePrimary, // Set app bar background color
          actions: [
            IconButton(
              icon: const Icon(Icons.download), // Download icon
              onPressed: () =>
                  _exportToExcel(context), // Export data to Excel on press
            ),
          ],
        ),
        body: Container(
          decoration: const BoxDecoration(
            color: Colors.black, // Solid black background
          ),
          child: StreamBuilder<List<LocationData>>(
            stream: _getAllLocations(
                FirebaseFirestore.instance), // Stream of location data
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                    child:
                        CircularProgressIndicator()); // Show loading indicator
              }
              if (snapshot.hasError) {
                return Center(
                    child:
                        Text('Error: ${snapshot.error}')); // Show error message
              }
              final locations =
                  snapshot.data ?? []; // Get location data or empty list
              return ListView.builder(
                itemCount: locations.length, // Number of items in the list
                itemBuilder: (context, index) => ListTile(
                  leading: const Icon(Icons.location_pin), // Location pin icon
                  title: Text(
                      'User: ${locations[index].username ?? 'Anonymous'}'), // User name or 'Anonymous'
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('UUID: ${locations[index].deviceId}'), // Device UUID
                      Text(
                          'Installed: ${locations[index].installationDate}'), // Installation date
                      Text(
                          'Lat: ${locations[index].latitude.toStringAsFixed(4)}, Long: ${locations[index].longitude.toStringAsFixed(4)}'), // Latitude and longitude
                      Text(
                          'Time: ${locations[index].timestamp.toLocal().toString()}'), // Timestamp
                    ],
                  ),
                ),
              );
            },
          ),
        ));
  }
}

// Data model for location information
class LocationData {
  final double latitude;
  final double longitude;
  final DateTime timestamp;
  final String? username;
  final String? password;
  final String deviceId;
  final String installationDate;

  LocationData({
    required this.latitude,
    required this.longitude,
    required this.timestamp,
    this.username,
    this.password,
    required this.deviceId,
    required this.installationDate,
  });
}
