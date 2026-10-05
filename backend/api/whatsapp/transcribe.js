// Transcrição de áudios do WhatsApp (OGG/Opus) com a API da OpenAI.
// O Claude não recebe áudio, então o áudio vira texto antes da leitura.

/**
 * @param {{apiKey: string, model?: string}} opts
 */
function createTranscriber({ apiKey, model = 'gpt-4o-mini-transcribe' }) {
  return async function transcribe({ data, mimeType }) {
    const form = new FormData();
    const ext = mimeType.includes('mpeg') ? 'mp3' : mimeType.includes('mp4') ? 'm4a' : 'ogg';
    form.append('file', new Blob([data], { type: mimeType }), `audio.${ext}`);
    form.append('model', model);
    form.append('language', 'pt');
    const res = await fetch('https://api.openai.com/v1/audio/transcriptions', {
      method: 'POST',
      headers: { authorization: `Bearer ${apiKey}` },
      body: form,
    });
    if (!res.ok) {
      throw new Error(`Transcrição falhou: ${res.status} ${(await res.text()).slice(0, 300)}`);
    }
    return String((await res.json()).text ?? '').trim();
  };
}

module.exports = { createTranscriber };
