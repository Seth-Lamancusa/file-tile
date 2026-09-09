import 'dart:io';

import '../models/directory_layout_issue.dart';

/// Linux/macOS EPERM
const int _eperm = 1;

/// Linux/macOS EACCES
const int _eacces = 13;

/// Linux/macOS EROFS
const int _erofs = 30;

/// Windows ERROR_ACCESS_DENIED
const int _winAccessDenied = 5;

bool isPermissionDenied(Object error) {
  if (error is PathAccessException) return true;
  if (error is FileSystemException) {
    final code = error.osError?.errorCode;
    if (code == _eacces || code == _eperm || code == _erofs) {
      return true;
    }
    if (Platform.isWindows && code == _winAccessDenied) {
      return true;
    }
    final message = error.osError?.message ?? error.message;
    return message.toLowerCase().contains('permission denied');
  }
  return false;
}

DirectoryLayoutIssueKind classifyLayoutIoError(Object error) {
  if (error is FormatException) {
    return DirectoryLayoutIssueKind.corrupt;
  }
  if (isPermissionDenied(error)) {
    return DirectoryLayoutIssueKind.permissionDenied;
  }
  return DirectoryLayoutIssueKind.unreadable;
}
