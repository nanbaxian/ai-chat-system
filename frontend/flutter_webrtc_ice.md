# Flutter WebRTC – ICE via DataChannel

## On PeerConnection

pc.onIceCandidate = (candidate) {
  dataChannel.send(jsonEncode({
    type: 'ice',
    payload: candidate.toMap(),
  }));
};

## On DataChannel message

if (event.type == 'ice') {
  pc.addCandidate(RTCIceCandidate(
    event.payload['candidate'],
    event.payload['sdpMid'],
    event.payload['sdpMLineIndex'],
  ));
}
