import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grisha_launcher/models/launcher_settings.dart';
import 'package:grisha_launcher/ui/wallpaper_background.dart';

void main() {
  testWidgets('image settings renders image wallpaper layer', (tester) async {
    final imageFile = File(
      '${Directory.systemTemp.path}/grisha_wallpaper_test.png',
    );
    imageFile.writeAsBytesSync(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: WallpaperBackground(
          settings: LauncherSettings(
            wallpaperType: WallpaperType.image,
            wallpaperPath: imageFile.path,
          ),
          overlayOpacity: 0.48,
          child: const SizedBox.shrink(),
        ),
      ),
    );

    expect(find.byKey(const Key('image-wallpaper-background')), findsOneWidget);
  });

  testWidgets('none settings renders gradient fallback', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: WallpaperBackground(
          settings: LauncherSettings(),
          overlayOpacity: 0.48,
          child: SizedBox.shrink(),
        ),
      ),
    );

    expect(
      find.byKey(const Key('gradient-wallpaper-background')),
      findsWidgets,
    );
  });
}
