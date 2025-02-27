// Main Flutter imports for UI and core functionality
import 'package:flutter/material.dart'; // Imports the Flutter Material Design library for UI elements.
import 'package:firebase_core/firebase_core.dart'; // Imports Firebase core functionality for initializing Firebase.
import 'location_sender_page.dart'; // Imports the Location Sender Page widget from its file.
import 'admin_locations_page.dart'; // Imports the Admin Locations Page widget from its file.
import 'admin_media_page.dart'; // Imports the Admin Pictures Page widget from its file.

// Initialize Firebase and start the app
void main() async {
  WidgetsFlutterBinding
      .ensureInitialized(); // Ensure Flutter bindings are initialized
  await Firebase.initializeApp(); // Initialize Firebase services
  runApp(const MyApp()); // Start the app with the MyApp widget
}

// Main app configuration
class MyApp extends StatelessWidget {
  const MyApp({super.key}); // Constructor

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      // Main app widget
      title: 'Location Tracker', // App title
      theme: ThemeData(
        // App theme settings
        fontFamily: 'Roboto', // Default font
        colorScheme: ColorScheme.fromSeed(
          // Color scheme for Material 3
          seedColor: Colors.blueGrey, // Darker accent color
          brightness: Brightness.dark, // Dark theme
        ),
        useMaterial3: true, // Use Material 3 design
      ),
      home: const LocationSenderPage(), // Main page
      routes: {
        // Named routes for navigation
        '/admin': (context) =>
            const AdminLocationsPage(), // Admin locations page route
        '/adminPictures': (context) =>
            const AdminMediaPage(), // Admin pictures page route
      },
    );
  }
}
