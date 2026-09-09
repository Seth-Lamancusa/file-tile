import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

const _imageExtensions = {
  'jpg',
  'jpeg',
  'png',
  'gif',
  'webp',
  'bmp',
};

String fileExtension(String name) {
  final ext = p.extension(name);
  if (ext.isEmpty) return '';
  return ext.substring(1).toLowerCase();
}

bool isRasterImageFile(String name) =>
    _imageExtensions.contains(fileExtension(name));

IconData iconForEntry(String name, {required bool isDirectory}) {
  if (isDirectory) return Icons.folder;
  switch (fileExtension(name)) {
    case 'png':
    case 'jpg':
    case 'jpeg':
    case 'gif':
    case 'webp':
    case 'bmp':
    case 'svg':
    case 'ico':
      return Icons.image;
    case 'mp4':
    case 'mkv':
    case 'webm':
    case 'mov':
    case 'avi':
      return Icons.video_file;
    case 'mp3':
    case 'wav':
    case 'flac':
    case 'ogg':
    case 'm4a':
      return Icons.audio_file;
    case 'pdf':
      return Icons.picture_as_pdf;
    case 'zip':
    case 'tar':
    case 'gz':
    case 'tgz':
    case '7z':
    case 'rar':
      return Icons.folder_zip;
    case 'json':
    case 'yaml':
    case 'yml':
    case 'toml':
    case 'xml':
      return Icons.data_object;
    case 'md':
    case 'txt':
    case 'rst':
      return Icons.article;
    case 'html':
    case 'htm':
      return Icons.language;
    case 'css':
    case 'scss':
      return Icons.style;
    case 'sh':
    case 'bash':
    case 'zsh':
      return Icons.terminal;
    case 'dart':
    case 'py':
    case 'js':
    case 'ts':
    case 'jsx':
    case 'tsx':
    case 'c':
    case 'h':
    case 'cc':
    case 'cpp':
    case 'rs':
    case 'go':
    case 'java':
    case 'kt':
    case 'rb':
      return Icons.code;
    default:
      return Icons.description;
  }
}
