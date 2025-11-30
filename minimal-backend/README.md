# Minimal OMI Backend

Simple FastAPI WebSocket server that receives audio from the OMI device and saves it as WAV files.

## Setup

```bash
cd minimal-backend
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate
pip install -r requirements.txt
```

## Run

```bash
python main.py
```

Server starts at `http://localhost:8000`

## Endpoints

- `GET /` - Health check
- `GET /test` - WebSocket test page
- `WS /ws/audio` - Audio WebSocket endpoint

### WebSocket Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| sample_rate | 16000 | Audio sample rate |
| codec | pcm16 | Audio codec (pcm8, pcm16, opus, opus_fs320) |

## Recordings

Audio files are saved to `./recordings/` as WAV files with timestamp.

## Example

Connect from Flutter app with:
```
ws://YOUR_IP:8000/ws/audio?sample_rate=16000&codec=pcm16
```

For Android emulator, use `10.0.2.2` instead of `localhost`.

