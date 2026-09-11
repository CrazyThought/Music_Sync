// This is a generated file - do not edit.
//
// Generated from musicsync.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:async' as $async;
import 'dart:core' as $core;

import 'package:grpc/service_api.dart' as $grpc;
import 'package:protobuf/protobuf.dart' as $pb;

import 'musicsync.pb.dart' as $0;

export 'musicsync.pb.dart';

/// 数据传输服务：签名拉取 + 文件双向传输。
@$pb.GrpcServiceName('musicsync.MusicSync')
class MusicSyncClient extends $grpc.Client {
  /// The hostname for this service.
  static const $core.String defaultHost = '';

  /// OAuth scopes needed for the client.
  static const $core.List<$core.String> oauthScopes = [
    '',
  ];

  MusicSyncClient(super.channel, {super.options, super.interceptors});

  /// 拉取 PC 端最新特征签名。
  $grpc.ResponseFuture<$0.SignatureResponse> getSignature(
    $0.GetSignatureRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$getSignature, request, options: options);
  }

  /// 下载文件：服务端从 offset 起分块下发，实现断点续传。
  $grpc.ResponseStream<$0.FileChunk> downloadFile(
    $0.DownloadRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createStreamingCall(
        _$downloadFile, $async.Stream.fromIterable([request]),
        options: options);
  }

  /// 上传文件：客户端逐块上传，服务端按 offset 续接写入。
  $grpc.ResponseFuture<$0.UploadResponse> uploadFile(
    $async.Stream<$0.FileChunk> request, {
    $grpc.CallOptions? options,
  }) {
    return $createStreamingCall(_$uploadFile, request, options: options).single;
  }

  /// 查询某文件在服务端已接收的字节数，供上传断点续传定位偏移。
  $grpc.ResponseFuture<$0.UploadResponse> getUploadStatus(
    $0.UploadStatusRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$getUploadStatus, request, options: options);
  }

  // method descriptors

  static final _$getSignature =
      $grpc.ClientMethod<$0.GetSignatureRequest, $0.SignatureResponse>(
          '/musicsync.MusicSync/GetSignature',
          ($0.GetSignatureRequest value) => value.writeToBuffer(),
          $0.SignatureResponse.fromBuffer);
  static final _$downloadFile =
      $grpc.ClientMethod<$0.DownloadRequest, $0.FileChunk>(
          '/musicsync.MusicSync/DownloadFile',
          ($0.DownloadRequest value) => value.writeToBuffer(),
          $0.FileChunk.fromBuffer);
  static final _$uploadFile =
      $grpc.ClientMethod<$0.FileChunk, $0.UploadResponse>(
          '/musicsync.MusicSync/UploadFile',
          ($0.FileChunk value) => value.writeToBuffer(),
          $0.UploadResponse.fromBuffer);
  static final _$getUploadStatus =
      $grpc.ClientMethod<$0.UploadStatusRequest, $0.UploadResponse>(
          '/musicsync.MusicSync/GetUploadStatus',
          ($0.UploadStatusRequest value) => value.writeToBuffer(),
          $0.UploadResponse.fromBuffer);
}

@$pb.GrpcServiceName('musicsync.MusicSync')
abstract class MusicSyncServiceBase extends $grpc.Service {
  $core.String get $name => 'musicsync.MusicSync';

  MusicSyncServiceBase() {
    $addMethod(
        $grpc.ServiceMethod<$0.GetSignatureRequest, $0.SignatureResponse>(
            'GetSignature',
            getSignature_Pre,
            false,
            false,
            ($core.List<$core.int> value) =>
                $0.GetSignatureRequest.fromBuffer(value),
            ($0.SignatureResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.DownloadRequest, $0.FileChunk>(
        'DownloadFile',
        downloadFile_Pre,
        false,
        true,
        ($core.List<$core.int> value) => $0.DownloadRequest.fromBuffer(value),
        ($0.FileChunk value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.FileChunk, $0.UploadResponse>(
        'UploadFile',
        uploadFile,
        true,
        false,
        ($core.List<$core.int> value) => $0.FileChunk.fromBuffer(value),
        ($0.UploadResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.UploadStatusRequest, $0.UploadResponse>(
        'GetUploadStatus',
        getUploadStatus_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.UploadStatusRequest.fromBuffer(value),
        ($0.UploadResponse value) => value.writeToBuffer()));
  }

  $async.Future<$0.SignatureResponse> getSignature_Pre($grpc.ServiceCall $call,
      $async.Future<$0.GetSignatureRequest> $request) async {
    return getSignature($call, await $request);
  }

  $async.Future<$0.SignatureResponse> getSignature(
      $grpc.ServiceCall call, $0.GetSignatureRequest request);

  $async.Stream<$0.FileChunk> downloadFile_Pre($grpc.ServiceCall $call,
      $async.Future<$0.DownloadRequest> $request) async* {
    yield* downloadFile($call, await $request);
  }

  $async.Stream<$0.FileChunk> downloadFile(
      $grpc.ServiceCall call, $0.DownloadRequest request);

  $async.Future<$0.UploadResponse> uploadFile(
      $grpc.ServiceCall call, $async.Stream<$0.FileChunk> request);

  $async.Future<$0.UploadResponse> getUploadStatus_Pre($grpc.ServiceCall $call,
      $async.Future<$0.UploadStatusRequest> $request) async {
    return getUploadStatus($call, await $request);
  }

  $async.Future<$0.UploadResponse> getUploadStatus(
      $grpc.ServiceCall call, $0.UploadStatusRequest request);
}
