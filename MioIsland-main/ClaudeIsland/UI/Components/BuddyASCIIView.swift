//
//  BuddyASCIIView.swift
//  ClaudeIsland
//
//  Renders Claude Code buddy ASCII art sprites with idle animation.
//  All 18 species sprite data is self-contained in this file.
//

import Combine
import SwiftUI

// MARK: - Sprite Data

/// Each species has 3 frames, each frame is 5 lines of ~12 chars.
/// The `{E}` placeholder gets replaced with the actual eye character.
private let spriteBodies: [BuddySpecies: [[String]]] = [
    .duck: [
        [
            "            ",
            "    __      ",
            "  <({E} )___  ",
            "   (  ._>   ",
            "    `--\u{00B4}    ",
        ],
        [
            "            ",
            "    __      ",
            "  <({E} )___  ",
            "   (  ._>   ",
            "    `--\u{00B4}~   ",
        ],
        [
            "            ",
            "    __      ",
            "  <({E} )___  ",
            "   (  .__>  ",
            "    `--\u{00B4}    ",
        ],
    ],
    .goose: [
        [
            "            ",
            "     ({E}>    ",
            "     ||     ",
            "   _(__)_   ",
            "    ^^^^    ",
        ],
        [
            "            ",
            "    ({E}>     ",
            "     ||     ",
            "   _(__)_   ",
            "    ^^^^    ",
        ],
        [
            "            ",
            "     ({E}>>   ",
            "     ||     ",
            "   _(__)_   ",
            "    ^^^^    ",
        ],
    ],
    .blob: [
        [
            "            ",
            "   .----.   ",
            "  ( {E}  {E} )  ",
            "  (      )  ",
            "   `----\u{00B4}   ",
        ],
        [
            "            ",
            "  .------.  ",
            " (  {E}  {E}  ) ",
            " (        ) ",
            "  `------\u{00B4}  ",
        ],
        [
            "            ",
            "    .--.    ",
            "   ({E}  {E})   ",
            "   (    )   ",
            "    `--\u{00B4}    ",
        ],
    ],
    .cat: [
        [
            "            ",
            "   /\\_/\\    ",
            "  ( {E}   {E})  ",
            "  (  \u{03C9}  )   ",
            "  (\")_(\")   ",
        ],
        [
            "            ",
            "   /\\_/\\    ",
            "  ( {E}   {E})  ",
            "  (  \u{03C9}  )   ",
            "  (\")_(\")~  ",
        ],
        [
            "            ",
            "   /\\-/\\    ",
            "  ( {E}   {E})  ",
            "  (  \u{03C9}  )   ",
            "  (\")_(\")   ",
        ],
    ],
    .dragon: [
        [
            "            ",
            "  /^\\  /^\\  ",
            " <  {E}  {E}  > ",
            " (   ~~   ) ",
            "  `-vvvv-\u{00B4}  ",
        ],
        [
            "            ",
            "  /^\\  /^\\  ",
            " <  {E}  {E}  > ",
            " (        ) ",
            "  `-vvvv-\u{00B4}  ",
        ],
        [
            "   ~    ~   ",
            "  /^\\  /^\\  ",
            " <  {E}  {E}  > ",
            " (   ~~   ) ",
            "  `-vvvv-\u{00B4}  ",
        ],
    ],
    .octopus: [
        [
            "            ",
            "   .----.   ",
            "  ( {E}  {E} )  ",
            "  (______)  ",
            "  /\\/\\/\\/\\  ",
        ],
        [
            "            ",
            "   .----.   ",
            "  ( {E}  {E} )  ",
            "  (______)  ",
            "  \\/\\/\\/\\/  ",
        ],
        [
            "     o      ",
            "   .----.   ",
            "  ( {E}  {E} )  ",
            "  (______)  ",
            "  /\\/\\/\\/\\  ",
        ],
    ],
    .owl: [
        [
            "            ",
            "   /\\  /\\   ",
            "  (({E})({E}))  ",
            "  (  ><  )  ",
            "   `----\u{00B4}   ",
        ],
        [
            "            ",
            "   /\\  /\\   ",
            "  (({E})({E}))  ",
            "  (  ><  )  ",
            "   .----.   ",
        ],
        [
            "            ",
            "   /\\  /\\   ",
            "  (({E})(-))  ",
            "  (  ><  )  ",
            "   `----\u{00B4}   ",
        ],
    ],
    .penguin: [
        [
            "            ",
            "  .---.     ",
            "  ({E}>{E})     ",
            " /(   )\\    ",
            "  `---\u{00B4}     ",
        ],
        [
            "            ",
            "  .---.     ",
            "  ({E}>{E})     ",
            " |(   )|    ",
            "  `---\u{00B4}     ",
        ],
        [
            "  .---.     ",
            "  ({E}>{E})     ",
            " /(   )\\    ",
            "  `---\u{00B4}     ",
            "   ~ ~      ",
        ],
    ],
    .turtle: [
        [
            "            ",
            "   _,--._   ",
            "  ( {E}  {E} )  ",
            " /[______]\\ ",
            "  ``    ``  ",
        ],
        [
            "            ",
            "   _,--._   ",
            "  ( {E}  {E} )  ",
            " /[______]\\ ",
            "   ``  ``   ",
        ],
        [
            "            ",
            "   _,--._   ",
            "  ( {E}  {E} )  ",
            " /[======]\\ ",
            "  ``    ``  ",
        ],
    ],
    .snail: [
        [
            "            ",
            " {E}    .--.  ",
            "  \\  ( @ )  ",
            "   \\_`--\u{00B4}   ",
            "  ~~~~~~~   ",
        ],
        [
            "            ",
            "  {E}   .--.  ",
            "  |  ( @ )  ",
            "   \\_`--\u{00B4}   ",
            "  ~~~~~~~   ",
        ],
        [
            "            ",
            " {E}    .--.  ",
            "  \\  ( @  ) ",
            "   \\_`--\u{00B4}   ",
            "   ~~~~~~   ",
        ],
    ],
    .ghost: [
        [
            "            ",
            "   .----.   ",
            "  / {E}  {E} \\  ",
            "  |      |  ",
            "  ~`~``~`~  ",
        ],
        [
            "            ",
            "   .----.   ",
            "  / {E}  {E} \\  ",
            "  |      |  ",
            "  `~`~~`~`  ",
        ],
        [
            "    ~  ~    ",
            "   .----.   ",
            "  / {E}  {E} \\  ",
            "  |      |  ",
            "  ~~`~~`~~  ",
        ],
    ],
    .axolotl: [
        [
            "            ",
            "}~(______)~{",
            "}~({E} .. {E})~{",
            "  ( .--. )  ",
            "  (_/  \\_)  ",
        ],
        [
            "            ",
            "~}(______){~",
            "~}({E} .. {E}){~",
            "  ( .--. )  ",
            "  (_/  \\_)  ",
        ],
        [
            "            ",
            "}~(______)~{",
            "}~({E} .. {E})~{",
            "  (  --  )  ",
            "  ~_/  \\_~  ",
        ],
    ],
    .capybara: [
        [
            "            ",
            "  n______n  ",
            " ( {E}    {E} ) ",
            " (   oo   ) ",
            "  `------\u{00B4}  ",
        ],
        [
            "            ",
            "  n______n  ",
            " ( {E}    {E} ) ",
            " (   Oo   ) ",
            "  `------\u{00B4}  ",
        ],
        [
            "    ~  ~    ",
            "  u______n  ",
            " ( {E}    {E} ) ",
            " (   oo   ) ",
            "  `------\u{00B4}  ",
        ],
    ],
    .cactus: [
        [
            "            ",
            " n  ____  n ",
            " | |{E}  {E}| | ",
            " |_|    |_| ",
            "   |    |   ",
        ],
        [
            "            ",
            "    ____    ",
            " n |{E}  {E}| n ",
            " |_|    |_| ",
            "   |    |   ",
        ],
        [
            " n        n ",
            " |  ____  | ",
            " | |{E}  {E}| | ",
            " |_|    |_| ",
            "   |    |   ",
        ],
    ],
    .robot: [
        [
            "            ",
            "   .[||].   ",
            "  [ {E}  {E} ]  ",
            "  [ ==== ]  ",
            "  `------\u{00B4}  ",
        ],
        [
            "            ",
            "   .[||].   ",
            "  [ {E}  {E} ]  ",
            "  [ -==- ]  ",
            "  `------\u{00B4}  ",
        ],
        [
            "     *      ",
            "   .[||].   ",
            "  [ {E}  {E} ]  ",
            "  [ ==== ]  ",
            "  `------\u{00B4}  ",
        ],
    ],
    .rabbit: [
        [
            "            ",
            "   (\\__/)   ",
            "  ( {E}  {E} )  ",
            " =(  ..  )= ",
            "  (\")__(\")" + "  ",
        ],
        [
            "            ",
            "   (|__/)   ",
            "  ( {E}  {E} )  ",
            " =(  ..  )= ",
            "  (\")__(\")" + "  ",
        ],
        [
            "            ",
            "   (\\__/)   ",
            "  ( {E}  {E} )  ",
            " =( .  . )= ",
            "  (\")__(\")" + "  ",
        ],
    ],
    .mushroom: [
        [
            "            ",
            " .-o-OO-o-. ",
            "(__________)",
            "   |{E}  {E}|   ",
            "   |____|   ",
        ],
        [
            "            ",
            " .-O-oo-O-. ",
            "(__________)",
            "   |{E}  {E}|   ",
            "   |____|   ",
        ],
        [
            "   . o  .   ",
            " .-o-OO-o-. ",
            "(__________)",
            "   |{E}  {E}|   ",
            "   |____|   ",
        ],
    ],
    .chonk: [
        [
            "            ",
            "  /\\    /\\  ",
            " ( {E}    {E} ) ",
            " (   ..   ) ",
            "  `------\u{00B4}  ",
        ],
        [
            "            ",
            "  /\\    /|  ",
            " ( {E}    {E} ) ",
            " (   ..   ) ",
            "  `------\u{00B4}  ",
        ],
        [
            "            ",
            "  /\\    /\\  ",
            " ( {E}    {E} ) ",
            " (   ..   ) ",
            "  `------\u{00B4}~ ",
        ],
    ],
    .unknown: [
        [
            "            ",
            "   .----.   ",
            "  ( {E}  {E} )  ",
            "  (  ..  )  ",
            "   `----\u{00B4}   ",
        ],
        [
            "            ",
            "   .----.   ",
            "  ( {E}  {E} )  ",
            "  ( .  . )  ",
            "   `----\u{00B4}   ",
        ],
        [
            "            ",
            "   .----.   ",
            "  ( -  - )  ",
            "  (  ..  )  ",
            "   `----\u{00B4}   ",
        ],
    ],
]

// MARK: - Hat Lines

private let hatLines: [String: String] = [
    "crown":     "   \\^^^/    ",
    "tophat":    "   [___]    ",
    "propeller": "    -+-     ",
    "halo":      "   (   )    ",
    "wizard":    "    /^\\     ",
    "beanie":    "   (___)    ",
    "tinyduck":  "    ,>      ",
]

// MARK: - Animation Constants

/// Idle sequence from CompanionSprite.tsx.
/// Most frames show frame 0 (static). Occasional fidget (frames 1, 2).
/// -1 means blink (replace eye char with `-`).
private let idleSequence: [Int] = [0, 0, 0, 0, 1, 0, 0, 0, -1, 0, 0, 2, 0, 0, 0]

/// Hearts float up-and-out over 5 ticks (~2.5s). Prepended above the sprite.
private let petHearts: [String] = [
    "   \u{2764}    \u{2764}   ",
    "  \u{2764}  \u{2764}   \u{2764}  ",
    " \u{2764}   \u{2764}  \u{2764}   ",
    "\u{2764}  \u{2764}      \u{2764} ",
    "\u{00B7}    \u{00B7}   \u{00B7}  ",
]

// MARK: - BuddyASCIIView

struct BuddyASCIIView: View {
    let buddy: BuddyInfo

    /// When true, hearts float above the sprite.
    var isPetting: Bool = false

    @State private var tick: Int = 0
    @State private var petTick: Int = 0

    private let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            // Hearts overlay when petting
            if isPetting {
                Text(petHearts[petTick % petHearts.count])
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(Color("NotchStatus/Error"))
                    .transition(.opacity)
            }

            // Sprite lines
            ForEach(Array(renderedLines.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(buddy.rarity.color)
            }

            // Name below the sprite
            Text(buddy.name)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(buddy.rarity.color)
                .padding(.top, 2)
        }
        .onReceive(timer) { _ in
            tick += 1
            if isPetting {
                petTick += 1
            }
        }
    }

    // MARK: - Rendering

    /// The fully rendered sprite lines for the current animation tick.
    private var renderedLines: [String] {
        let species = buddy.species
        guard species != .unknown,
              let frames = spriteBodies[species] else {
            // Fallback for unknown species
            return ["  ???  ", " (?.?) ", "  ???  "]
        }

        let frameCount = frames.count

        // Determine frame index and blink state from idle sequence
        let step = idleSequence[tick % idleSequence.count]
        let blink: Bool
        let frameIndex: Int

        if isPetting {
            // Excited: cycle all fidget frames fast
            frameIndex = tick % frameCount
            blink = false
        } else if step == -1 {
            frameIndex = 0
            blink = true
        } else {
            frameIndex = step % frameCount
            blink = false
        }

        let frame = frames[frameIndex]
        let eyeChar = blink ? "-" : buddy.eye

        // Replace {E} placeholders with the eye character
        var lines = frame.map { line in
            line.replacingOccurrences(of: "{E}", with: eyeChar)
        }

        // Apply hat if buddy has one and line 0 is blank
        let hat = buddy.hat
        if hat != "none",
           let hatLine = hatLines[hat],
           !lines.isEmpty,
           lines[0].trimmingCharacters(in: .whitespaces).isEmpty {
            lines[0] = hatLine
        }

        // Drop blank hat slot if ALL frames have blank line 0 and no hat
        // (avoids wasting a row when there's no hat and no frame uses line 0)
        if !lines.isEmpty,
           lines[0].trimmingCharacters(in: .whitespaces).isEmpty,
           frames.allSatisfy({ $0[0].trimmingCharacters(in: .whitespaces).isEmpty }) {
            lines.removeFirst()
        }

        return lines
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        BuddyASCIIView(
            buddy: BuddyInfo(
                name: "Bloop",
                personality: "A cheerful blob",
                species: .blob,
                rarity: .rare,
                stats: BuddyStats(debugging: 5, patience: 3, chaos: 7, wisdom: 4, snark: 6),
                eye: "\u{00B7}",
                hat: "crown",
                isShiny: false,
                hatchedAt: nil
            )
        )
        .frame(width: 120, height: 80)

        BuddyASCIIView(
            buddy: BuddyInfo(
                name: "Quackers",
                personality: "A mischievous duck",
                species: .duck,
                rarity: .legendary,
                stats: BuddyStats(debugging: 8, patience: 2, chaos: 9, wisdom: 3, snark: 7),
                eye: "\u{2726}",
                hat: "tophat",
                isShiny: true,
                hatchedAt: nil
            ),
            isPetting: true
        )
        .frame(width: 120, height: 100)
    }
    .padding()
    .background(Color.black)
}
