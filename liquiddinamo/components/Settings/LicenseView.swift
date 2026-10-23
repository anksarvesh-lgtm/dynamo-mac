//
//  LicenseView.swift
//  LiquidDynamo
//
//  Created for LiquidDynamo
//

import SwiftUI

struct LicenseView: View {
    @State private var selectedLicenseTab: LicenseCategory = .gpl

    enum LicenseCategory: String, CaseIterable, Identifiable {
        case gpl = "LiquidDynamo (GPL-3.0)"
        case thirdParty = "Third-Party Notices"

        var id: String { rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Open Source Licenses")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                Picker("License", selection: $selectedLicenseTab) {
                    ForEach(LicenseCategory.allCases) { category in
                        Text(category.rawValue).tag(category)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 280)
            }
            .padding(.horizontal)
            .padding(.top, 16)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if selectedLicenseTab == .gpl {
                        Text("GNU GENERAL PUBLIC LICENSE")
                            .font(.headline)
                        Text("Version 3, 29 June 2007")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("Copyright © 2026 Agrigence. Portions Copyright © TheBoredTeam.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Divider()

                        Text(gplLicenseText)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    } else {
                        Text("Third-Party Software Acknowledgements")
                            .font(.headline)
                        Text("LiquidDynamo makes use of the following open-source libraries:")
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

    private var gplLicenseText: String {
        """
        GNU GENERAL PUBLIC LICENSE
        Version 3, 29 June 2007

        Copyright (C) 2007 Free Software Foundation, Inc. <https://fsf.org/>
        Everyone is permitted to copy and distribute verbatim copies
        of this license document, but changing it is not allowed.

        Preamble

        The GNU General Public License is a free, copyleft license for software and other kinds of works.

        The licenses for most software and other practical works are designed to take away your freedom to share and change the works. By contrast, the GNU General Public License is intended to guarantee your freedom to share and change all versions of a program--to make sure it remains free software for all its users. We, the Free Software Foundation, use the GNU General Public License for most of our software; it applies also to any other work released this way by its authors. You can apply it to your programs, too.

        When we speak of free software, we are referring to freedom, not price. Our General Public Licenses are designed to make sure that you have the freedom to distribute copies of free software (and charge for them if you wish), that you receive source code or can get it if you want it, that you can change the software or use pieces of it in new free programs, and that you know you can do these things.

        To protect your rights, we need to prevent others from denying you these rights or asking you to surrender the rights. Therefore, you have certain responsibilities if you distribute copies of the software, or if you modify it: responsibilities to respect the freedom of others.

        For the complete terms and conditions, visit:
        https://www.gnu.org/licenses/gpl-3.0.html
        """
    }

    private var thirdPartyLicenseText: String {
        """
        LiquidDynamo relies on open-source packages:

        - Defaults (MIT License) - Copyright (c) Sindre Sorhus
        - KeyboardShortcuts (MIT License) - Copyright (c) Sindre Sorhus
        - LaunchAtLogin-Modern (MIT License) - Copyright (c) Sindre Sorhus
        - Lottie (Apache 2.0 License) - Copyright Airbnb, Inc.
        - SkyLightWindow (MIT License) - Copyright (c) Lakr Aream
        - AsyncXPCConnection (MIT License) - Copyright (c) ChimeHQ
        - Swift Collections (Apache 2.0 with Runtime Exception) - Copyright (c) Apple Inc.
        """
    }
}
