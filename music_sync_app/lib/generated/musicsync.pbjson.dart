// This is a generated file - do not edit.
//
// Generated from musicsync.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports
// ignore_for_file: unused_import

import 'dart:convert' as $convert;
import 'dart:core' as $core;
import 'dart:typed_data' as $typed_data;

@$core.Deprecated('Use getSignatureRequestDescriptor instead')
const GetSignatureRequest$json = {
  '1': 'GetSignatureRequest',
};

/// Descriptor for `GetSignatureRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List getSignatureRequestDescriptor =
    $convert.base64Decode('ChNHZXRTaWduYXR1cmVSZXF1ZXN0');

@$core.Deprecated('Use signatureResponseDescriptor instead')
const SignatureResponse$json = {
  '1': 'SignatureResponse',
  '2': [
    {'1': 'json', '3': 1, '4': 1, '5': 12, '10': 'json'},
  ],
};

/// Descriptor for `SignatureResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List signatureResponseDescriptor = $convert
    .base64Decode('ChFTaWduYXR1cmVSZXNwb25zZRISCgRqc29uGAEgASgMUgRqc29u');

@$core.Deprecated('Use downloadRequestDescriptor instead')
const DownloadRequest$json = {
  '1': 'DownloadRequest',
  '2': [
    {'1': 'relative_path', '3': 1, '4': 1, '5': 9, '10': 'relativePath'},
    {'1': 'offset', '3': 2, '4': 1, '5': 3, '10': 'offset'},
  ],
};

/// Descriptor for `DownloadRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List downloadRequestDescriptor = $convert.base64Decode(
    'Cg9Eb3dubG9hZFJlcXVlc3QSIwoNcmVsYXRpdmVfcGF0aBgBIAEoCVIMcmVsYXRpdmVQYXRoEh'
    'YKBm9mZnNldBgCIAEoA1IGb2Zmc2V0');

@$core.Deprecated('Use fileChunkDescriptor instead')
const FileChunk$json = {
  '1': 'FileChunk',
  '2': [
    {'1': 'relative_path', '3': 1, '4': 1, '5': 9, '10': 'relativePath'},
    {'1': 'offset', '3': 2, '4': 1, '5': 3, '10': 'offset'},
    {'1': 'data', '3': 3, '4': 1, '5': 12, '10': 'data'},
    {'1': 'total_size', '3': 4, '4': 1, '5': 3, '10': 'totalSize'},
  ],
};

/// Descriptor for `FileChunk`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List fileChunkDescriptor = $convert.base64Decode(
    'CglGaWxlQ2h1bmsSIwoNcmVsYXRpdmVfcGF0aBgBIAEoCVIMcmVsYXRpdmVQYXRoEhYKBm9mZn'
    'NldBgCIAEoA1IGb2Zmc2V0EhIKBGRhdGEYAyABKAxSBGRhdGESHQoKdG90YWxfc2l6ZRgEIAEo'
    'A1IJdG90YWxTaXpl');

@$core.Deprecated('Use uploadResponseDescriptor instead')
const UploadResponse$json = {
  '1': 'UploadResponse',
  '2': [
    {'1': 'relative_path', '3': 1, '4': 1, '5': 9, '10': 'relativePath'},
    {'1': 'received_bytes', '3': 2, '4': 1, '5': 3, '10': 'receivedBytes'},
    {'1': 'completed', '3': 3, '4': 1, '5': 8, '10': 'completed'},
    {'1': 'content_hash', '3': 4, '4': 1, '5': 9, '10': 'contentHash'},
  ],
};

/// Descriptor for `UploadResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List uploadResponseDescriptor = $convert.base64Decode(
    'Cg5VcGxvYWRSZXNwb25zZRIjCg1yZWxhdGl2ZV9wYXRoGAEgASgJUgxyZWxhdGl2ZVBhdGgSJQ'
    'oOcmVjZWl2ZWRfYnl0ZXMYAiABKANSDXJlY2VpdmVkQnl0ZXMSHAoJY29tcGxldGVkGAMgASgI'
    'Ugljb21wbGV0ZWQSIQoMY29udGVudF9oYXNoGAQgASgJUgtjb250ZW50SGFzaA==');

@$core.Deprecated('Use uploadStatusRequestDescriptor instead')
const UploadStatusRequest$json = {
  '1': 'UploadStatusRequest',
  '2': [
    {'1': 'relative_path', '3': 1, '4': 1, '5': 9, '10': 'relativePath'},
  ],
};

/// Descriptor for `UploadStatusRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List uploadStatusRequestDescriptor = $convert.base64Decode(
    'ChNVcGxvYWRTdGF0dXNSZXF1ZXN0EiMKDXJlbGF0aXZlX3BhdGgYASABKAlSDHJlbGF0aXZlUG'
    'F0aA==');
