/// Formatting of what the device reports about itself, for the settings screen.
library;

/// How long the device has been running: "Under a minute", "12 min",
/// "4 h 5 min", "3 d 4 h". Null when it isn't reported, since zero isn't sent.
String? formatRunningTime(int seconds) {
  if (seconds <= 0) return null;
  final time = Duration(seconds: seconds);
  if (time.inMinutes < 1) return 'Under a minute';
  if (time.inHours < 1) return '${time.inMinutes} min';
  if (time.inDays < 1) {
    return '${time.inHours} h ${time.inMinutes.remainder(60)} min';
  }
  return '${time.inDays} d ${time.inHours.remainder(24)} h';
}

/// The LTE signal in words, from its RSSI in dBm. Null when it isn't reported:
/// zero isn't sent, and a real RSSI is always negative.
String? formatMobileSignal(int rssiDbm) {
  if (rssiDbm >= 0) return null;
  if (rssiDbm >= -65) return 'Excellent';
  if (rssiDbm >= -75) return 'Good';
  if (rssiDbm >= -85) return 'Fair';
  return 'Poor';
}
