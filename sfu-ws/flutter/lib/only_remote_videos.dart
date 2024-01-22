// SPDX-FileCopyrightText: 2023 The Pion community <https://pion.ly>
// SPDX-License-Identifier: MIT

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class OnlyRemoteVideosApp extends StatefulWidget {
  @override
  _OnlyRemoteVideosAppState createState() => _OnlyRemoteVideosAppState();
}

class _OnlyRemoteVideosAppState extends State<OnlyRemoteVideosApp> {
  List _remoteRenderers = [];

  late WebSocketChannel _wsChannel;

  late RTCPeerConnection _peerConnection;

  @override
  void initState() {
    super.initState();
    connect();
  }

  Future<void> connect() async {
    _peerConnection = await createPeerConnection({}, {});

    _peerConnection.onIceCandidate = (candidate) {
      _wsChannel.sink.add(JsonEncoder().convert({
        "event": "candidate",
        "data": JsonEncoder().convert({
          'sdpMLineIndex': candidate.sdpMLineIndex,
          'sdpMid': candidate.sdpMid,
          'candidate': candidate.candidate,
        })
      }));
    };

    _peerConnection.onTrack = (event) async {
      if (event.track.kind == 'video' && event.streams.isNotEmpty) {
        var renderer = RTCVideoRenderer();
        await renderer.initialize();
        renderer.srcObject = event.streams[0];

        setState(() {
          _remoteRenderers.add(renderer);
        });
      }
    };

    _peerConnection.onRemoveStream = (stream) {
      var rendererToRemove;
      var newRenderList = [];

      // Filter existing renderers for the stream that has been stopped
      _remoteRenderers.forEach((r) {
        if (r.srcObject.id == stream.id) {
          rendererToRemove = r;
        } else {
          newRenderList.add(r);
        }
      });

      // Set the new renderer list
      setState(() {
        _remoteRenderers = newRenderList;
      });

      // Dispose the renderer we are done with
      if (rendererToRemove != null) {
        rendererToRemove.dispose();
      }
    };

    _wsChannel =
        IOWebSocketChannel.connect("ws://localhost:8080/websocket");
    await _wsChannel.ready;

    _wsChannel.stream.listen((raw) async {

      Map<String, dynamic> msg = jsonDecode(raw);

      switch (msg['event']) {
        case 'candidate':
          Map<String, dynamic> parsed = jsonDecode(msg['data']);
          _peerConnection
              .addCandidate(RTCIceCandidate(parsed['candidate'], parsed['sdpMid'], parsed['sdpMLineIndex']));
          return;
        case 'offer':
          Map<String, dynamic> offer = jsonDecode(msg['data']);

          // SetRemoteDescription and create answer
          await _peerConnection.setRemoteDescription(
              RTCSessionDescription(offer['sdp'], offer['type']));
          RTCSessionDescription answer =
          await _peerConnection.createAnswer({});
          await _peerConnection.setLocalDescription(answer);

          // Send answer over WebSocket
          _wsChannel.sink.add(JsonEncoder().convert({
            'event': 'answer',
            'data':
            JsonEncoder().convert({'type': answer.type, 'sdp': answer.sdp})
          }));
          return;
      }
    }, onDone: () {
      print('Closed by server!');
    });
  }

  @override
  Widget build(BuildContext context) {
    double aspectRatio = 1920/1080;
    double width = MediaQuery.of(context).size.width;
    double height = width / aspectRatio;
    return MaterialApp(
        title: 'sfu-ws',
        home: Scaffold(
            appBar: AppBar(
              title: Text('sfu-ws'),
            ),
            body: OrientationBuilder(builder: (context, orientation) {
              return Column(
                children: [
                  Row(
                    children: [
                      Text('Remote Video', style: TextStyle(fontSize: 50.0))
                    ],
                  ),
                  Row(
                    children: [
                      ..._remoteRenderers.map((remoteRenderer) {
                        return SizedBox(
                            width: width,
                            height: height,
                            child: RTCVideoView(remoteRenderer));
                      }).toList(),
                    ],
                  ),
                  Row(
                    children: [
                      Text('Logs Video', style: TextStyle(fontSize: 50.0))
                    ],
                  ),
                ],
              );
            })));
  }
}
