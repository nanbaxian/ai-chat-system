export class DeepInfraLLM {
  constructor(private apiKey: string) {}

  async stream(prompt: string, onDelta: (t: string) => void, onFinal: (t: string) => void) {
    const res = await fetch('https://api.deepinfra.com/v1/openai/chat/completions', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${this.apiKey}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
        model: 'meta-llama/Meta-Llama-3.1-8B-Instruct-Turbo',
        stream: true,
        messages: [{ role: 'user', content: prompt }]
      })
    });

    const reader = res.body!.getReader();
    const decoder = new TextDecoder();
    let full = '';

    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      const chunk = decoder.decode(value);
      full += chunk;
      onDelta(chunk);
    }

    onFinal(full);
  }
}
