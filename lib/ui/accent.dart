import 'package:flutter/material.dart';

/// The app's own colour and the lighter end of its gradient — one place for
/// the brand purple, so no screen restates the hex. Collections that wear a
/// colour of their own are in `home/collection_accent.dart`.
const kAccent = Color(0xFF6C5CE7);
const kAccentLight = Color(0xFF8E7BF5);
const kAccentGradient = LinearGradient(colors: [kAccent, kAccentLight]);
