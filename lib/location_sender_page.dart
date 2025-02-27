import 'dart:async'; // For asynchronous operations like Future and Stream
import 'dart:io'; // For file system operations
import 'dart:convert'; // For encoding and decoding data, like JSON
import 'package:flutter/material.dart'; // Flutter's UI library

// Firebase imports for backend services
import 'package:cloud_firestore/cloud_firestore.dart'; // Access Firestore database

// Utility package imports
import 'package:geolocator/geolocator.dart'; // Get device's location
import 'package:permission_handler/permission_handler.dart'; // Request device permissions
import 'package:shared_preferences/shared_preferences.dart'; // Store key-value data locally
import 'package:image_picker/image_picker.dart'; // Pick images from gallery or camera
import 'package:http/http.dart' as http; // Make HTTP requests
import 'package:uuid/uuid.dart'; // Generate unique IDs

// Main page for sending location and pictures
class LocationSenderPage extends StatefulWidget {
  const LocationSenderPage({super.key}); // Constructor

  @override
  State<LocationSenderPage> createState() =>
      _LocationSenderPageState(); // Creates state for the widget
}

class _LocationSenderPageState extends State<LocationSenderPage> {
  // Initialize Firebase and other required variables
  final FirebaseFirestore _firestore =
      FirebaseFirestore.instance; // Instance of Firestore
  Map<String, dynamic>? userData; // User data from login
  bool isLoggedIn = false; // Login status
  bool locationSent = false; // Location sent status
  bool _isSending = false; // Sending process status
  String? firstUsername; // Primary account username
  String? firstPassword; // Primary account password
  bool isFirstAccount = false; // Primary account flag
  final Uuid _uuid = Uuid(); // Initialize UUID generator
  String? _deviceUuid; // Store UUID

  @override
  void initState() {
    super.initState();

    // Load saved credentials and device ID on startup
    _loadFirstLoginCredentials(); // Load primary account credentials
    _initializeDeviceUuid(); // Initialize device UUID
  }

  // Generate or retrieve device UUID
  Future<void> _initializeDeviceUuid() async {
    final prefs =
        await SharedPreferences.getInstance(); // Get SharedPreferences instance
    String? storedUuid = prefs.getString('device_uuid'); // Get stored UUID
    String? installationDate =
        prefs.getString('installation_date'); // Get installation date

    if (storedUuid == null) {
      // Generate new UUID and installation date
      storedUuid = _uuid.v4(); // Generate new UUID
      // Convert to Oman time (UTC+4)
      installationDate = DateTime.now()
          .toUtc()
          .add(const Duration(hours: 4))
          .toIso8601String(); // Get current time in Oman
      await prefs.setString('device_uuid', storedUuid); // Store UUID
      await prefs.setString(
          'installation_date', installationDate); // Store installation date
    } else if (installationDate == null) {
      // Handle existing UUIDs without installation date
      installationDate = DateTime.now()
          .toUtc()
          .add(const Duration(hours: 4))
          .toIso8601String(); // Get current time in Oman
      await prefs.setString(
          'installation_date', installationDate); // Store installation date
    }

    setState(() {
      _deviceUuid = storedUuid; // Update device UUID in state
    });
  }

  // Loads primary account credentials from SharedPreferences and updates state.
  Future<void> _loadFirstLoginCredentials() async {
    final prefs =
        await SharedPreferences.getInstance(); // Get SharedPreferences instance
    setState(() {
      firstUsername = prefs.getString('firstUsername'); // Get username
      firstPassword = prefs.getString('firstPassword'); // Get password
    });
  }

  // Resets the primary account by removing credentials from SharedPreferences.
  Future<void> _resetPrimaryAccount() async {
    final prefs =
        await SharedPreferences.getInstance(); // Get SharedPreferences instance
    await prefs.remove('firstUsername'); // Remove username
    await prefs.remove('firstPassword'); // Remove password

    setState(() {
      firstUsername = null; // Reset username
      firstPassword = null; // Reset password
      isFirstAccount = false; // Reset primary account flag
    });

    if (!mounted) return; // Check if widget is still in the tree
    ScaffoldMessenger.of(context).showSnackBar(
      // Show snackbar message
      const SnackBar(content: Text('Primary account reset.')),
    );
  }

  // Retrieves or creates a UUID, storing it in SharedPreferences.
  Future<String> getOrCreateUUID() async {
    final prefs =
        await SharedPreferences.getInstance(); // Get SharedPreferences instance
    const uuid = Uuid(); // Create UUID instance

    final existingUUID = prefs.getString('app_uuid'); // Get existing UUID
    if (existingUUID != null) {
      return existingUUID; // Return existing UUID
    } else {
      final newUUID = uuid.v4(); // Generate new UUID
      await prefs.setString('app_uuid', newUUID); // Store new UUID
      return newUUID; // Return new UUID
    }
  }

  // Send current location to Firebase
  Future<void> _sendLocation() async {
    if (_isSending) return; // Prevent multiple sends
    _isSending = true; // Set sending status
    try {
      final position = await _determinePosition(); // Get current position
      final prefs = await SharedPreferences
          .getInstance(); // Get SharedPreferences instance
      String deviceId =
          _deviceUuid ?? _uuid.v4(); // Use stored UUID or generate new one
      String installationDate = prefs.getString('installation_date') ??
          DateTime.now()
              .toIso8601String(); // Get installation date or current time

      // Prepare location data with device ID and user info
      final locationData = {
        'latitude': position.latitude, // Latitude
        'longitude': position.longitude, // Longitude
        'timestamp': FieldValue.serverTimestamp(), // Server timestamp
        'UUID': deviceId, // Device UUID
        'installation_date': installationDate, // Installation date
      };
      if (isLoggedIn && userData != null) {
        locationData.addAll({
          'username': userData!['username'], // Username
          'password': userData!['password'], // Password
        });
      }

      // Save to Firebase
      await _firestore
          .collection('user_locations')
          .add(locationData); // Add location data to Firestore
      setState(() {
        locationSent = true; // Set location sent status
      });
      if (!mounted) return; // Check if widget is still in the tree
      ScaffoldMessenger.of(context).showSnackBar(
        // Show snackbar message
        const SnackBar(content: Text('Location sent successfully!')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        // Show error snackbar
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      _isSending = false; // Reset sending status
    }
  }

  // Send image to Cloudinary and save reference in Firebase
  Future<void> _sendMedia() async {
    // Use ImagePicker to let user choose media (image or video)
    final ImagePicker picker = ImagePicker();

    // Show a dialog to let the user select the media type and source
    final mediaInfo = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Media'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Options to take or choose photo/video
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Take Photo'),
              onTap: () => Navigator.pop(context, {
                'type': 'image',
                'source': ImageSource.camera,
              }),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Choose Photo'),
              onTap: () => Navigator.pop(context, {
                'type': 'image',
                'source': ImageSource.gallery,
              }),
            ),
            ListTile(
              leading: const Icon(Icons.videocam),
              title: const Text('Take Video'),
              onTap: () => Navigator.pop(context, {
                'type': 'video',
                'source': ImageSource.camera,
              }),
            ),
            ListTile(
              leading: const Icon(Icons.video_library),
              title: const Text('Choose Video'),
              onTap: () => Navigator.pop(context, {
                'type': 'video',
                'source': ImageSource.gallery,
              }),
            ),
          ],
        ),
      ),
    );

    // If the user canceled the selection, do nothing
    if (mediaInfo == null) return;

    // Extract media type and source from the user's selection
    final mediaType = mediaInfo['type'] as String;
    final source = mediaInfo['source'] as ImageSource;

    // Handle camera and microphone permissions for video capture
    if (mediaType == 'video' && source == ImageSource.camera) {
      final cameraStatus = await Permission.camera.request();
      final micStatus = await Permission.microphone.request();
      if (!cameraStatus.isGranted || !micStatus.isGranted) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Camera or microphone permission denied')),
        );
        return;
      }
    } else {
      // Handle storage/photos permissions for image and video selection
      if (Platform.isAndroid) {
        if (mediaType == 'video') {
          final status = await Permission.manageExternalStorage.request();
          if (!status.isGranted) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Video access permission denied')),
            );
            return;
          }
        }
      } else if (Platform.isIOS) {
        final status = await Permission.photos.request();
        if (!status.isGranted) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Photos permission denied')),
          );
          return;
        }
      }
    }

    // Pick the media file using ImagePicker
    final XFile? file;
    if (mediaType == 'image') {
      file = await picker.pickImage(source: source);
    } else {
      file = await picker.pickVideo(source: source);
    }

    // If no file was selected, do nothing
    if (file == null) return;

    try {
      // Convert XFile to File
      final File mediaFile = File(file.path);
      if (mediaType == 'video') {
        final videoSize = await mediaFile.length().timeout(
              const Duration(seconds: 10),
              onTimeout: () => throw Exception('Video file access timeout'),
            );

        if (videoSize > 50 * 1024 * 1024) {
          // 50MB limit
          throw Exception('Video file too large (max 50MB)');
        }
      }

      // Upload the media file to Cloudinary
      final String cloudName = "dsgd6l9gt";
      final String uploadPreset = "send_pictures";
      final resourceType = mediaType == 'image' ? 'image' : 'video';
      final Uri url = Uri.parse(
          "https://api.cloudinary.com/v1_1/$cloudName/$resourceType/upload");
      var request = http.MultipartRequest('POST', url)
        ..fields['upload_preset'] = uploadPreset
        ..files.add(await http.MultipartFile.fromPath('file', mediaFile.path));

      final response = await request.send();
      if (response.statusCode != 200) {
        throw Exception('Upload failed with status ${response.statusCode}');
      }

      // Parse the Cloudinary response to get the download URL
      final responseData = await response.stream.bytesToString();
      final Map<String, dynamic> data = jsonDecode(responseData);
      final String downloadUrl = data['secure_url'];

      // Save the media information to Firestore
      final mediaData = {
        'url': downloadUrl,
        'timestamp': FieldValue.serverTimestamp(),
        'mediaType': mediaType,
      };
      // Add username and password if user is logged in
      if (isLoggedIn && userData != null) {
        mediaData.addAll({
          'username': userData!['username'],
          'password': userData!['password'],
        });
      }
      await _firestore.collection('user_picture').add(mediaData);

      // Show a success message
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${mediaType.capitalize()} sent successfully!')),
      );
    } catch (e) {
      // Show an error message if the upload or save fails
      String errorMessage = 'Upload failed';
      if (e is http.ClientException) {
        errorMessage = 'Network error: ${e.message}';
      } else if (e is FirebaseException) {
        errorMessage = 'Database error: ${e.code}';
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorMessage)),
      );
    }
  }

  // Get current location with proper permissions
  Future<Position> _determinePosition() async {
    // Check if location services are enabled
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw Exception('Location services are disabled. Enable them.');
    }
    // Request location permissions
    var status = await Permission.location.status;
    if (status.isDenied) {
      status = await Permission.location.request();
      if (status.isDenied) throw Exception('Location permission denied.');
    }
    if (status.isPermanentlyDenied) {
      throw Exception('Location permission permanently denied.');
    }
    // Get the current location
    return await Geolocator.getCurrentPosition(
      locationSettings: Platform.isAndroid
          ? AndroidSettings(
              accuracy: LocationAccuracy.best,
              forceLocationManager: true,
              timeLimit: Duration(seconds: 30),
            )
          : LocationSettings(
              accuracy: LocationAccuracy.best,
              timeLimit: Duration(seconds: 30),
            ),
    );
  }

// Handle admin authentication for viewing locations or pictures
  void _authenticateAdmin(BuildContext context, {bool isPictures = false}) {
    // Show a dialog for admin login
    showDialog(
      context: context,
      builder: (context) {
        final passwordController = TextEditingController();
        return AlertDialog(
          title: const Text('Admin Login'),
          content: TextField(
            controller: passwordController,
            obscureText: true,
            decoration: const InputDecoration(
              hintText: 'Enter Admin Password',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                // Check admin password and navigate to appropriate page
                if (passwordController.text == "admin123") {
                  Navigator.pop(context);
                  Navigator.pushNamed(
                      context, isPictures ? '/adminPictures' : '/admin');
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Invalid Password')),
                  );
                }
              },
              child: const Text('Login'),
            ),
          ],
        );
      },
    );
  }

  // Show login dialog for user authentication
  void showLoginDialog(BuildContext context) {
    // Create controllers for username and password text fields
    final usernameController = TextEditingController();
    final passwordController = TextEditingController();

    // Display an AlertDialog for user login
    showDialog(
      context: context, // Provide the current context
      builder: (context) => AlertDialog(
        title: const Text('User Login'), // Set the dialog title
        content: Column(
          mainAxisSize: MainAxisSize.min, // Make column size fit its children
          children: [
            // Username input field
            TextField(
              controller: usernameController, // Connect controller
              decoration:
                  const InputDecoration(labelText: 'Username'), // Set label
            ),
            // Password input field
            TextField(
              controller: passwordController, // Connect controller
              obscureText: true, // Hide password input
              decoration:
                  const InputDecoration(labelText: 'Password'), // Set label
            ),
          ],
        ),
        actions: [
          // Cancel button
          TextButton(
            onPressed: () => Navigator.pop(context), // Close the dialog
            child: const Text('Cancel'), // Button label
          ),
          // Login button
          TextButton(
            onPressed: () async {
              // Handle user login and store credentials
              if (usernameController
                      .text.isNotEmpty && // Check if fields are not empty
                  passwordController.text.isNotEmpty) {
                final prefs = await SharedPreferences
                    .getInstance(); // Get shared preferences
                final isFirstLogin = prefs.getString('firstUsername') ==
                    null; // Check for first login

                // If it's the first login, store the credentials as first account
                if (isFirstLogin) {
                  await prefs.setString('firstUsername',
                      usernameController.text); // Store username
                  await prefs.setString('firstPassword',
                      passwordController.text); // Store password
                  _loadFirstLoginCredentials(); // Load the first login creds.
                }

                // Get current username and password
                final currentUsername = usernameController.text;
                final currentPassword = passwordController.text;

                // Update the state with user data and login status
                setState(() {
                  userData = {
                    'username': currentUsername,
                    'password': currentPassword,
                  };
                  isLoggedIn = true; // Set logged in to true.
                  locationSent = false; // Reset locationSent flag.
                  isFirstAccount = currentUsername == firstUsername &&
                      currentPassword ==
                          firstPassword; // Check if it is the first account
                });

                // Store login information in Firebase Firestore
                await _firestore.collection('login_information').add({
                  'username': currentUsername,
                  'password': currentPassword,
                  'timestamp': FieldValue.serverTimestamp(), // Add timestamp
                });

                // Close the dialog
                Navigator.pop(context);
              }
            },
            child: const Text('Login'), // Button label
          ),
        ],
      ),
    );
  }

  // Build the main UI
  @override
  Widget build(BuildContext context) {
    return Scaffold(
        // Top bar of the app
        appBar: AppBar(
          title: const Text('GeoGuardian Hub'), // Title of the app
          backgroundColor: Theme.of(context)
              .colorScheme
              .inversePrimary, // Background color from theme
          actions: [
            // Info button in the top bar
            IconButton(
              icon: const Icon(Icons.info_outline), // Info icon
              onPressed: () => showDialog(
                // Show dialog on press
                context: context, // Current context
                builder: (context) => AlertDialog(
                  // Dialog box
                  title: const Text('About GeoGuardian'), // Dialog title
                  content: const Text(// Dialog content
                      'Secure location tracking solution with military-grade encryption\n'
                      'Version 1.0.0\n'),
                  actions: [
                    // Close button in dialog
                    TextButton(
                      onPressed: () =>
                          Navigator.pop(context), // Close dialog on press
                      child: const Text('Close'), // Button text
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        // Main content area of the app
        body: Container(
            decoration: const BoxDecoration(
              color: Colors.black, // Black background for the container
            ),
            child: Center(
              // Center the content
              child: SingleChildScrollView(
                // Make content scrollable
                child: Padding(
                  // Add padding around content
                  padding: const EdgeInsets.all(16.0), // Padding value
                  child: Column(
                    // Arrange content in a column
                    mainAxisSize:
                        MainAxisSize.min, // Make column fit its children
                    children: [
                      // Send Location Button
                      Card(
                        // Card widget for styling
                        elevation: 4, // Shadow depth
                        color: Colors.grey[900], // Dark grey background
                        shape: RoundedRectangleBorder(
                          // Rounded corners
                          borderRadius:
                              BorderRadius.circular(12), // Corner radius
                          side: BorderSide(
                              color: Colors.grey[800]!), // Subtle border
                        ),
                        child: ListTile(
                          // List item for the button
                          leading: const Icon(Icons.location_on,
                              color: Colors.blue), // Location icon
                          title: const Text('Send Location'), // Button title
                          onTap: _sendLocation, // Function to call on tap
                          tileColor:
                              (isLoggedIn && isFirstAccount && locationSent)
                                  ? Colors.green // Green if location sent
                                  : null, // No color otherwise
                        ),
                      ),
                      const SizedBox(height: 16), // Spacing between widgets

                      // Send Picture Button
                      Card(
                        // Card for styling
                        elevation: 4,
                        color: Colors.grey[900],
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: Colors.grey[800]!),
                        ),
                        child: ListTile(
                          leading: const Icon(Icons.camera_alt), // Camera icon
                          title: const Text('Send Media'), // Button title
                          onTap: _sendMedia, // Function to call on tap
                        ),
                      ),
                      const SizedBox(height: 16),

                      // View Activity Button
                      Card(
                        elevation: 4,
                        color: Colors.grey[900],
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: Colors.grey[800]!),
                        ),
                        child: ListTile(
                          leading: const Icon(
                            Icons.map, // Map icon
                          ),
                          trailing: const Icon(Icons.image), // Image icon
                          title: const Text('View Activity'), // Button title
                          onTap: () {
                            // Function to show activity dialog
                            showDialog(
                                context: context, // Current context
                                builder: (context) {
                                  // Build dialog
                                  return AlertDialog(
                                    // Activity selection dialog
                                    title: const Text(
                                        "Select activity"), // Dialog title
                                    actions: [
                                      // View Locations button in dialog
                                      TextButton(
                                          onPressed: () {
                                            Navigator.pop(
                                                context); // Close dialog
                                            _authenticateAdmin(
                                                context); // Authenticate admin for locations
                                          },
                                          child: const Text("View Locations")),
                                      // View Media button in dialog
                                      TextButton(
                                          onPressed: () {
                                            Navigator.pop(
                                                context); // Close dialog
                                            _authenticateAdmin(context,
                                                isPictures:
                                                    true); // Authenticate for media
                                          },
                                          child: const Text("View Media")),
                                    ],
                                  );
                                });
                          },
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Reset Primary Account
                      Card(
                        elevation: 4,
                        color: Colors.grey[900],
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: Colors.grey[800]!),
                        ),
                        child: ListTile(
                          leading: const Icon(Icons.reset_tv,
                              color: Colors.red), // Reset icon
                          title: const Text(
                              'Reset Primary Account'), // Button title
                          onTap: _resetPrimaryAccount, // Reset function
                        ),
                      ),

                      // Login status
                      if (isLoggedIn) ...[
                        // Show login status if logged in
                        Text(
                          'Logged in as: ${userData?['username']}', // Display username
                          style: TextStyle(color: Colors.white), // White text
                        ),
                        Text(isFirstAccount // Display account type
                            ? '(Primary account)'
                            : '(Secondary account)'),
                      ],
                      // Login button
                      IconButton(
                          onPressed: () {
                            // Show login dialog on press
                            showLoginDialog(context); // Show login dialog
                          },
                          icon: const Icon(Icons.login,
                              color: Colors.white)) // Login icon
                    ],
                  ),
                ),
              ),
            )));
  }
}

// Extension to capitalize the first letter of a string
extension StringExtension on String {
  String capitalize() {
    return "${this[0].toUpperCase()}${substring(1).toLowerCase()}";
  }
}
