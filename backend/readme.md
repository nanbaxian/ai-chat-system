cd backend
npm install -g tsx
pm2 start --name voice-webrtc --interpreter=tsx webrtc-service/src/server.ts

为方便持久化并开机自启：pm2 save 然后 pm2 startup 会输出一条命令（比如 sudo env PATH=$PATH:/usr/bin pm2 startup systemd -u root --hp /root）照着执行即可。
你可以用 pm2 status/pm2 logs voice-webrtc/pm2 restart voice-webrtc 来查看状态、日志和重启；若需要用不同 env，记得在命令前设置 WEBRTC_PORT、NODE_ENV=production 等变量或者写一个 .env.production 并在 pm2 start --env production … 里指定。 