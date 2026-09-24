import 'dart:io';

import 'package:flutter/material.dart';
import 'package:mi_finca_app/app/theme/app_theme.dart';

/// Local photo rendering; the optional fallback is mounted only when needed.
class LocalAnimalPhotoAvatar extends StatelessWidget {
  const LocalAnimalPhotoAvatar({
    super.key,
    required this.localPhotoPath,
    required this.radius,
    required this.placeholder,
    this.fallback,
  });

  final String? localPhotoPath;
  final double radius;
  final Widget placeholder;
  final Widget? fallback;

  @override
  Widget build(BuildContext context) {
    final file = localPhotoPath == null ? null : File(localPhotoPath!);
    var exists = false;
    try {
      exists = file?.existsSync() ?? false;
    } on FileSystemException {
      // A stale/inaccessible local reference behaves like a missing photo.
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: AppColors.primaryLight,
      child: exists
          ? ClipOval(
              child: Image(
                image: FileImage(file!),
                width: radius * 2,
                height: radius * 2,
                fit: BoxFit.cover,
                errorBuilder: (_, error, stackTrace) => fallback ?? placeholder,
              ),
            )
          : fallback ?? placeholder,
    );
  }
}
