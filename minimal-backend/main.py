import os
import sys
if sys.platform == "darwin":
    os.environ.setdefault("DYLD_LIBRARY_PATH", "/opt/homebrew/lib:/usr/local/lib")
import time
import uuid
from datetime import datetime
from fastapi import FastAPI, WebSocket, WebSocketDisconnect, Query
from fastapi.responses import HTMLResponse
from audio_handler import AudioHandler, OPUS_AVAILABLE

app = FastAPI(title="Minimal OMI Backend")

recordings_dir = "./recordings"
os.makedirs(recordings_dir, exist_ok=True)

@app.get("/")
async def root():
    return {"status": "ok", "message": "Minimal OMI Backend - WebSocket at /ws/audio", "opus_available": OPUS_AVAILABLE}

@app.get("/test", response_class=HTMLResponse)
async def test_page():
    return """
    <!DOCTYPE html>
    <html>
    <head><title>WebSocket Test</title></head>
    <body>
        <h1>WebSocket Audio Test</h1>
        <p>Status: <span id="status">Disconnected</span></p>
        <p>Bytes received: <span id="bytes">0</span></p>
        <button onclick="connect()">Connect</button>
        <button onclick="disconnect()">Disconnect</button>
        <script>
            let ws = null;
            let bytesReceived = 0;
            function connect() {
                ws = new WebSocket(`ws://${location.host}/ws/audio?sample_rate=16000&codec=pcm16`);
                ws.onopen = () => { document.getElementById('status').textContent = 'Connected'; };
                ws.onclose = () => { document.getElementById('status').textContent = 'Disconnected'; };
                ws.onmessage = (e) => { console.log('Message:', e.data); };
                ws.onerror = (e) => { console.error('Error:', e); };
            }
            function disconnect() { if (ws) ws.close(); }
        </script>
    </body>
    </html>
    """

@app.websocket("/ws/audio")
async def websocket_audio(
    websocket: WebSocket,
    sample_rate: int = Query(default=16000),
    codec: str = Query(default="pcm16"),
):
    await websocket.accept()
    session_id = str(uuid.uuid4())[:8]
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    filename = f"{timestamp}_{session_id}"
    print(f"[{session_id}] WebSocket connected - codec={codec}, sample_rate={sample_rate}")
    audio_handler = AudioHandler(
        output_dir=recordings_dir,
        filename=filename,
        sample_rate=sample_rate,
        codec=codec,
    )
    bytes_received = 0
    last_log_time = time.time()
    try:
        while True:
            data = await websocket.receive_bytes()
            if len(data) <= 2:
                continue
            bytes_received += len(data)
            audio_handler.process_audio_bytes(data)
            if time.time() - last_log_time > 5:
                print(f"[{session_id}] Received {bytes_received} bytes total")
                last_log_time = time.time()
    except WebSocketDisconnect:
        print(f"[{session_id}] WebSocket disconnected")
    except Exception as e:
        print(f"[{session_id}] Error: {e}")
    finally:
        filepath = audio_handler.finalize()
        print(f"[{session_id}] Audio saved to: {filepath}")
        print(f"[{session_id}] Total bytes received: {bytes_received}")

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)

