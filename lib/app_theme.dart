// lib/app_theme.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:async';
import 'package:light/light.dart';

class AppTheme {
  static final ValueNotifier<ThemeMode> themeMode = ValueNotifier(ThemeMode.system);
  static StreamSubscription? _lightSubscription;

  static final light = ThemeData(
    brightness: Brightness.light,
    textTheme: GoogleFonts.ptMonoTextTheme(),
    scaffoldBackgroundColor: Colors.indigo[200],
    appBarTheme: AppBarTheme(backgroundColor: Colors.indigo[300]),
    cardColor: Colors.white,
  );

  static final dark = ThemeData(
    brightness: Brightness.dark,
    textTheme: GoogleFonts.ptMonoTextTheme().apply(bodyColor: Colors.white),
    scaffoldBackgroundColor: Colors.grey[900],
    appBarTheme: AppBarTheme(backgroundColor: Colors.grey[800]),
    cardColor: Colors.grey[850],
  );


  static void init() {
    _lightSubscription = lightSensorEvents.listen((LightSensorEvent event) {
      final lux = event.lux;
      final isDark = lux < 20;
      themeMode.value = isDark ? ThemeMode.dark : ThemeMode.light;
    });
  }



  // static void init()  {
  //   _lightSubscription = Light().lightSensorStream.listen((event) {
  //     final lux = event;
  //     final isDark = lux < 10; // Ajuste: < 20 lux = escuro
  //     // if (kDebugMode) print('..................LUX: $lux');
  //     themeMode.value = isDark ? ThemeMode.dark : ThemeMode.light;
  //   });
  // }

  static void dispose() {
    _lightSubscription?.cancel();
  }
}
