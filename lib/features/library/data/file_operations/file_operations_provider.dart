/// Providers for the library file operations (Phase 7.3).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavely/features/library/data/file_operations/file_operations.dart';

/// Filesystem operations used by the selection bar. Overridden in tests.
final fileOperationsProvider = Provider<FileOperations>(
  (ref) => const LocalFileOperations(),
);
