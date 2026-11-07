# Privacy

Island runs locally. It has no accounts, analytics, telemetry, or servers.

- **Media, timers, downloads, battery, devices, mic/camera, calendar, clipboard** are read on your Mac and only shown in the island. Nothing is stored beyond what's on screen.
- **Mic/camera detection** only checks *whether* a device is in use. Island never records audio or video.
- **Clipboard** (off by default) shows a short preview for 2.5 seconds. Items marked concealed by password managers are ignored. Nothing is saved.
- **Web search** sends your query directly to the providers you enable (Wikipedia, DuckDuckGo, or Brave with your own key). Album art may be fetched from the URL the media app provides.
- **AI** (off by default) sends your question and fetched page text to the provider you choose (Anthropic, OpenAI) using your own API key, or to a local Ollama model. Keys are stored in your macOS Keychain.
- **Settings** are stored in Island's UserDefaults.
