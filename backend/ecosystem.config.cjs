module.exports = {
  apps: [{
    name: "webrtc-signal",
    script: "webrtc-service/src/server.ts",
    interpreter: "./node_modules/.bin/tsx",
    env: {
      HOST: "127.0.0.1",
      PORT: 3001
    }
  }]
}
