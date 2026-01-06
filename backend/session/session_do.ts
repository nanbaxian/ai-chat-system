import { SessionState } from './state';

export class SessionDO {
  state: DurableObjectState;
  pc: RTCPeerConnection | null = null;
  dc: RTCDataChannel | null = null;

  // --- Session State ---
  sessionState: SessionState = SessionState.LISTENING;
  metrics = {
    startTime: 0,
    sttFirstToken: 0,
    llmFirstToken: 0,
    ttsFirstAudio: 0,
    interrupts: 0,
  };

  constructor(state: DurableObjectState) {
    this.state = state;
  }

  async ensurePC() {
    if (this.pc) return;

    this.pc = new RTCPeerConnection({
      iceServers: [{ urls: 'stun:stun.l.google.com:19302' }]
    });

    this.pc.ondatachannel = (e) => {
      this.dc = e.channel;
      this.bindDataChannel();
    };

    this.pc.onicecandidate = (e) => {
      if (e.candidate && this.dc) {
        this.dc.send(JSON.stringify({ type: 'ice', payload: e.candidate }));
      }
    };
  }

  bindDataChannel() {
    if (!this.dc) return;

    this.dc.onmessage = (e) => {
      const event = JSON.parse(e.data);
      if (event.type === 'audio_in') {
        if (this.sessionState === SessionState.SPEAKING) {
          this.metrics.interrupts++;
          this.cancelCurrentTurn();
        }
        // send audio to STT adapter here
      }

      if (event.type === 'cancel') {
        this.cancelCurrentTurn();
      }
    };
  }

  cancelCurrentTurn() {
    // llm.cancel(); tts.cancel();
    this.sessionState = SessionState.LISTENING;
    this.emit({ type: 'ui.thinking', value: false });
  }

  emit(evt: any) {
    this.dc?.send(JSON.stringify(evt));
  }

  async fetch(req: Request) {
    const { type, payload } = await req.json();
    await this.ensurePC();

    if (type === 'offer') {
      await this.pc!.setRemoteDescription(payload);
      const answer = await this.pc!.createAnswer();
      await this.pc!.setLocalDescription(answer);
      return new Response(JSON.stringify(answer));
    }

    if (type === 'ice') {
      await this.pc!.addIceCandidate(payload);
      return new Response('ok');
    }

    return new Response('unknown');
  }
}
