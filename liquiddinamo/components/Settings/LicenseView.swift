//
//  LicenseView.swift
//  LiquidDynamo
//
//  Created for LiquidDynamo
//  Copyright © 2026 Agrigence. All rights reserved.
//

import SwiftUI

struct LicenseView: View {
    @State private var selectedLicenseTab: LicenseCategory = .restricted

    enum LicenseCategory: String, CaseIterable, Identifiable {
        case restricted = "LiquidDynamo License"
        case thirdParty = "Third-Party Notices"

        var id: String { rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("License & Acknowledgements")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                Picker("License", selection: $selectedLicenseTab) {
                    ForEach(LicenseCategory.allCases) { category in
                        Text(category.rawValue).tag(category)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 320)
            }
            .padding(.horizontal)
            .padding(.top, 16)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if selectedLicenseTab == .restricted {
                        Text("LIQUIDDYNAMO SOFTWARE LICENSE AGREEMENT")
                            .font(.headline)
                        Text("Restricted-Use Proprietary License")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("Copyright © 2026 Agrigence. All rights reserved.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Divider()

                        Text(restrictedLicenseText)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    } else {
                        Text("Third-Party Software Acknowledgements")
                            .font(.headline)
                        Text("LiquidDynamo makes use of the following open-source libraries and components:")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Divider()

                        Text(thirdPartyLicenseText)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
                .padding()
            }
            .background(Color(NSColor.textBackgroundColor).opacity(0.5))
            .cornerRadius(8)
            .padding(.horizontal)
            .padding(.bottom, 16)
        }
        .navigationTitle("License")
        .frame(minWidth: 500, minHeight: 400)
    }

    private var restrictedLicenseText: String {
        """
        LIQUIDDYNAMO SOFTWARE LICENSE AGREEMENT
        RESTRICTED-USE PROPRIETARY LICENSE

        Copyright (c) 2026 Agrigence. All rights reserved.

        IMPORTANT — PLEASE READ CAREFULLY BEFORE USING THIS SOFTWARE:

        This Software License Agreement ("Agreement") is a legal agreement between you (an individual or a single entity, referred to as "User" or "You") and Agrigence ("Rights Holder"), governing your access to and use of the LiquidDynamo application, accompanying software binaries, source code, visual assets, documentation, and interface components (collectively, the "Software").

        1. OWNERSHIP
        The Software, including its source code, architecture, compiled binaries, user interface designs, liquid glass shaders, 3D assets, icons, documentation, and product names, is the exclusive proprietary property of Agrigence.

        2. PERMITTED USE
        Subject to the terms and restrictions of this Agreement, Agrigence hereby grants you a limited, personal, non-exclusive, non-transferable, revocable license to:
        (a) Download, install, and execute the Software on macOS devices that you own or control; and
        (b) Use the Software solely for its documented, intended functionality as a personal macOS utility.

        3. PROHIBITED ACTIONS
        Unless explicitly authorized in advance and in writing by an authorized representative of Agrigence, you shall not, directly or indirectly:
        (a) Modify, adapt, translate, alter, or create derivative works of the Software or any portion thereof;
        (b) Distribute, share, publish, lease, rent, loan, sublicense, sell, resell, or otherwise convey modified copies or derivative versions of the Software;
        (c) Repackage, rebrand, or distribute the Software or its components under any other product name or publisher identity;
        (d) Remove, alter, obscure, or delete any copyright, trademark, or proprietary attribution notices;
        (e) Claim ownership, authorship, or exclusive rights in or to the Software.

        4. THIRD-PARTY COMPONENTS AND PREVIOUS RELEASES
        (a) Third-party open-source components remain governed by their respective licenses as detailed in NOTICE.md.
        (b) Rights exercised under previous open-source releases of this project are not retroactively eliminated.

        5. STATUTORY RIGHTS
        Applicable mandatory consumer and legal rights guaranteed by law remain unaffected.

        6. DISCLAIMER & LIMITATION OF LIABILITY
        THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND. IN NO EVENT SHALL AGRIGENCE BE LIABLE FOR ANY DAMAGES ARISING FROM THE USE OR INABILITY TO USE THE SOFTWARE.

        Contact: https://www.agrigence.in/
        """
    }

    private var thirdPartyLicenseText: String {
        """
        LiquidDynamo incorporates or interfaces with the following open-source projects:

        - Boring Notch (GPL-3.0) - Copyright (c) TheBoredTeam
        - Purge (MIT License) - Copyright (c) 2026 Jithin Sabu
        - Plexo (MIT License) - Copyright (c) 2026 Anmol Kapil
        - Net-Merge (MIT License) - Copyright (c) Rohit
        - Defaults (MIT License) - Copyright (c) Sindre Sorhus
        - KeyboardShortcuts (MIT License) - Copyright (c) Sindre Sorhus
        - LaunchAtLogin-Modern (MIT License) - Copyright (c) Sindre Sorhus
        - Lottie (Apache 2.0 License) - Copyright (c) Airbnb, Inc.
        - Sparkle (MIT License) - Copyright (c) Andy Matuschak, Kornel Lesiński
        - SkyLightWindow (MIT License) - Copyright (c) Lakr Aream
        - AsyncXPCConnection (MIT License) - Copyright (c) ChimeHQ
        - Swift Collections (Apache 2.0 with Runtime Exception) - Copyright (c) Apple Inc.
        - OpenMTP (MIT / LGPL-2.1) - Copyright (c) Ganesh Rathinavel
        """
    }
}
