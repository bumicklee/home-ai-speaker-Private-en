# Third-party notices

The firmware and assets in this repository are based on, or reference, the projects below. Copyright and license for each project belong to its original authors.

## waveshare-ai-speaker-assistant

- Source: https://github.com/KMX415/waveshare-ai-speaker-assistant
- License: MIT License, Copyright (c) 2026 KMX415
- What was taken: codec and I2S initialization, AEC, the playback queue, wake word lifecycle management, OpenAI real-time conversation handling, delegation and hang-up phrase handling
  - Those files carry a `Based on waveshare-ai-speaker-assistant …` line at the top
  - `firmware/components/board`, `audio_core`, `wake`, `live_voice`, `assistant`, `firmware/main/dev_console.c`
- Full text:

```text
MIT License

Copyright (c) 2026 KMX415

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## esphome-waveshare-esp32-s3-audio-va

- Source: https://github.com/MichalZaniewicz/esphome-waveshare-esp32-s3-audio-va
- License: MIT License, Copyright (c) 2026 Michał Zaniewicz
- What was taken
  - Code: none. The hardware initialization order and LED effect design were used as references (`docs/HARDWARE.md`, `base/core.yaml`)
  - Sound: `firmware/components/audio_core/assets/startup.mp3` is the same file as `base/sounds/startup.mp3` in that repository
- Full text:

```text
MIT License

Copyright (c) 2026 Michał Zaniewicz

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

### Source of the startup.mp3 Sound

The README of the repository above names Home Assistant Voice Preview Edition as the source of the sound. The Home Assistant Voice Preview Edition sounds are published under the following terms.

- [Home Assistant Voice Preview Edition Sounds](https://github.com/esphome/home-assistant-voice-pe/tree/dev/sounds) © 2024 [Clayton Charles Tapp](https://www.cctaudio.com/)
- License: [Creative Commons Attribution 4.0 International (CC BY 4.0)](https://creativecommons.org/licenses/by/4.0/)

## Sound Files in This Repository

| File | Source |
|:--|:--|
| `firmware/components/audio_core/assets/startup.mp3` | See the esphome-waveshare-esp32-s3-audio-va entry above |
| `firmware/components/audio_core/assets/ready.mp3` | A notification sound prepared by the author (Bumick Lee). Covered by this repository's LICENSE (MIT) |

## Waveshare ESP32-S3-AUDIO-Board Demo

- Source: https://www.waveshare.com/wiki/ESP32-S3-AUDIO-Board (Resources)
- License: no license file stated (the terms of use of the Waveshare wiki and product pages apply)
- What was taken: no code. The button, LED and MP3 playback driver structure and the pin constants were used as references

## Espressif

- ESP-IDF v5.5: Apache-2.0
- esp-sr 2.1.5: ESPRESSIF MIT License, Copyright (c) 2018 Espressif Systems (Shanghai)
- Other managed components: see `firmware/dependencies.lock`. Check each license on the component's page (https://components.espressif.com)
- Managed components and ESP-IDF are downloaded at build time and are not included in this repository

## Flutter Packages

- See `flutter/pubspec.lock`. Check each package's license on its pub.dev page
