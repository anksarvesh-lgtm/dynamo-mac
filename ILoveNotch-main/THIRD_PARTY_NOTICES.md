# Third-party notices

Every dependency added to the project must be listed below with its license and
copyright notice. Allowed licenses: MIT, BSD, Apache-2.0, ISC, and zlib. CI
(`make licenses`) fails when a resolved package or git submodule is missing
from this file.

## mediaremote-adapter (BSD-3-Clause)

https://github.com/ungive/mediaremote-adapter, v0.7.7
(commit e3ff5021eb0875858bd05f48d2e9ba2e962d1cf6), vendored as a git submodule
in `ThirdParty/mediaremote-adapter`. ILoveNotch ships its framework and perl
script and runs them with the system perl to read now-playing information.

```text
BSD 3-Clause License

Copyright (c) 2025, Jonas van den Berg and contributors

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this
   list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.

3. Neither the name of the copyright holder nor the names of its
   contributors may be used to endorse or promote products derived from
   this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```

## Sparkle (MIT)

https://github.com/sparkle-project/Sparkle, 2.10.0 and later 2.x, a Swift
package of the app target. It checks the signed appcast and installs updates in
release builds (docs/updates.md). Its notice follows; the full license, with the
external notices for bsdiff (BSD-2-Clause), sais-lite (MIT), and ed25519
(zlib), is at https://github.com/sparkle-project/Sparkle/blob/2.x/LICENSE.

```text
Copyright (c) 2006-2013 Andy Matuschak.
Copyright (c) 2009-2013 Elgato Systems GmbH.
Copyright (c) 2011-2014 Kornel Lesiński.
Copyright (c) 2015-2017 Mayur Pawashe.
Copyright (c) 2014 C.W. Betts.
Copyright (c) 2014 Petroules Corporation.
Copyright (c) 2014 Big Nerd Ranch.
All rights reserved.

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
the Software, and to permit persons to whom the Software is furnished to do so,
subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
```

## OpenUsage (MIT)

https://github.com/robinebers/openusage at commit
4ce788775e0cb3ec779d353b2ac9f9d7e8765bb4, adapted into
`Sources/NotchUsage/OpenUsage`: the provider integrations, usage models, pricing
engine, and services behind the AI Usage tab. Its price supplement ships as
`Sources/NotchUsage/Resources/pricing_supplement.json`. Each adapted file names
its origin in its header. ILoveNotch's changes: its own cache folder and
User-Agent, no reset-credit claiming, no Antigravity token renewal (it embeds
Antigravity's OAuth client secret), and a rebuilt UI. "OpenUsage" and its
logo are Robin Ebers' trademarks. ILoveNotch doesn't use the logo, and isn't
affiliated with or endorsed by OpenUsage.

```text
MIT License

Copyright (c) 2026 Robin Ebers

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

## LiteLLM price list (MIT)

https://github.com/BerriAI/litellm. `Sources/NotchUsage/Resources/pricing_litellm_snapshot.json`
is a compacted copy of its `model_prices_and_context_window.json`, as bundled
by OpenUsage. The app refreshes it from that file.

```text
MIT License

Copyright (c) 2023 Berri AI

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

## models.dev price list (MIT)

https://github.com/sst/models.dev. `Sources/NotchUsage/Resources/pricing_models_dev_snapshot.json`
is a compacted copy of https://models.dev/api.json, as bundled by OpenUsage.
The app refreshes it from that address.

```text
MIT License

Copyright (c) 2025 models.dev

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

## theSVG provider logos (MIT and CC0-1.0)

https://thesvg.org (https://github.com/glincker/thesvg). The logos in
`Sources/NotchUsage/Resources/Logos` are theSVG's mono icons, under the license
theSVG lists for each:

| File | theSVG icon | License |
| --- | --- | --- |
| `claude.svg` | claude | CC0-1.0 |
| `cursor.svg` | cursor | CC0-1.0 |
| `ollama.svg` | ollama | CC0-1.0 |
| `openrouter.svg` | openrouter | CC0-1.0 |
| `antigravity.svg` | antigravity-google | MIT |
| `codex.svg` | codex-openai | MIT |
| `copilot.svg` | github-copilot | MIT |
| `grok.svg` | grok-xai | MIT |
| `opencode.svg` | opencode | MIT |
| `zai.svg` | zhipu | MIT |

Each logo is its owner's trademark. ILoveNotch shows them only to identify each
provider, and doesn't suggest any endorsement.

```text
MIT License

Copyright (c) 2025 thesvg.org

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

## Tabler Icons (MIT)

https://tabler.io/icons (https://github.com/tabler/tabler-icons)
Copyright (c) 2020-2026 Paweł Kuna

The icons in `Sources/NotchSurface/Resources/Icons` are Tabler Icons 3.48.0's
outline and filled SVGs, unchanged, under their own names (a filled one ends in
`-filled`).

```text
MIT License

Copyright (c) 2020-2026 Paweł Kuna

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

## Quick Share protocol definitions (Apache-2.0)

https://github.com/google/nearby and https://github.com/google/ukey2
Copyright 2020–2023 Google LLC

The messages in `Sources/NotchTransfer/QuickShare` (`Frames.swift` and
`Crypto.swift`) follow the field numbers and values of Nearby Connections'
`offline_wire_formats.proto`, Quick Share's `wire_format.proto`, and UKEY2's
`ukey.proto`, `securemessage.proto`, and `securegcm.proto`, so ILoveNotch can
talk to Android phones. No Google code is included: ILoveNotch encodes these
messages itself.

```text
Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    https://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
```

<!-- Entry format:
## Name (License)
https://github.com/owner/repo
Copyright (c) YEAR Holder
-->
