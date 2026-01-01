module.exports = {
  apps: [{
    name: "webrtc-signal",
    script: "server.js",
    env: {
      HOST: "127.0.0.1",
      PORT: 3001
    }
  }]
}