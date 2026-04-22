import AppKit
import SwiftUI

struct IslandAboutPage: View {
    @Environment(\.openURL) private var openURL

    private let thirdPartyProjects: [IslandThirdPartyProject] = [
        IslandThirdPartyProject(
            name: "open-vibe-island",
            repositoryURL: "https://github.com/Octane0411/open-vibe-island",
            licenseName: "GPL-3.0",
            summary: "The shared notch shell language in Fantastic Island grows from this upstream interaction foundation.",
            versionText: nil,
            evidenceTitle: "Role in Fantastic Island",
            evidenceItems: [
                "Shapes the notch shell motion, sizing, and hit-testing behavior.",
                "Provides the interaction baseline that Fantastic Island extends with its own modules and settings surface.",
            ]
        ),
        IslandThirdPartyProject(
            name: "mihomo",
            repositoryURL: "https://github.com/MetaCubeX/mihomo",
            licenseName: "MIT",
            summary: "Provides the runtime core Fantastic Island can integrate with for managed Clash workflows.",
            versionText: "v1.19.23",
            evidenceTitle: "Role in Fantastic Island",
            evidenceItems: [
                "Provides the local proxy core used when managed Clash runtime assets are available.",
            ]
        ),
        IslandThirdPartyProject(
            name: "metacubexd",
            repositoryURL: "https://github.com/MetaCubeX/metacubexd",
            licenseName: "MIT",
            summary: "Provides the Clash dashboard Fantastic Island can integrate with for advanced inspection.",
            versionText: "v1.245.0",
            evidenceTitle: "Role in Fantastic Island",
            evidenceItems: [
                "Supplies the web dashboard interface used for Clash inspection and control when runtime assets are available.",
            ]
        ),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            pageHeader
            projectCard
            auditCard
            acknowledgementsCard
        }
    }

    private var pageHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("About")
                .font(.system(size: 30, weight: .bold))

            Text("Product concept, version, and acknowledgements for the work that helps shape Fantastic Island.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var projectCard: some View {
        AboutCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(displayName)
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(.white)

                        Text("A notch-first macOS utility that brings Codex, Clash, and Player into one shared island surface.")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.56))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)

                    Text(versionBadgeText)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.08), in: Capsule())
                }

                AboutInfoBlock(
                    title: "Product concept",
                    value: "Fantastic Island treats the notch as a shared command surface instead of a passive status strip. Codex lives beside Clash and Player so lightweight status, quick actions, and module switching all happen in one compact place."
                )
            }
        }
    }

    private var auditCard: some View {
        AboutCard {
            VStack(alignment: .leading, spacing: 16) {
                AboutSectionHeader(
                    title: "What This Page Covers",
                    detail: "This page highlights the outside work that materially shapes the product experience, without turning the About screen into an engineering inventory."
                )

                AboutAuditRow(
                    title: "Interaction foundation",
                    value: "open-vibe-island"
                )

                AboutAuditRow(
                    title: "Optional runtime integrations",
                    value: "mihomo, metacubexd"
                )

                AboutAuditRow(
                    title: "Product modules",
                    value: "Codex, Clash, Player"
                )

                AboutAuditRow(
                    title: "Platform base",
                    value: "SwiftUI, AppKit, Apple system frameworks"
                )
            }
        }
    }

    private var acknowledgementsCard: some View {
        AboutCard {
            VStack(alignment: .leading, spacing: 16) {
                AboutSectionHeader(
                    title: "Third-Party Acknowledgements",
                    detail: "These projects either influence the notch experience directly or provide integrations that Fantastic Island supports in source form."
                )

                ForEach(thirdPartyProjects) { project in
                    AboutProjectCard(project: project) {
                        if let url = URL(string: project.repositoryURL) {
                            openURL(url)
                        }
                    }
                }
            }
        }
    }

    private var displayName: String {
        if let displayName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String,
           !displayName.isEmpty {
            return displayName
        }

        if let bundleName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String,
           !bundleName.isEmpty {
            return bundleName
        }

        return "Fantastic Island"
    }

    private var versionBadgeText: String {
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let buildVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String

        switch (shortVersion, buildVersion) {
        case let (.some(shortVersion), .some(buildVersion)):
            return "v\(shortVersion) (\(buildVersion))"
        case let (.some(shortVersion), nil):
            return "v\(shortVersion)"
        case let (nil, .some(buildVersion)):
            return "build \(buildVersion)"
        default:
            return "local build"
        }
    }
}

private struct IslandThirdPartyProject: Identifiable {
    let name: String
    let repositoryURL: String
    let licenseName: String
    let summary: String
    let versionText: String?
    let evidenceTitle: String
    let evidenceItems: [String]

    var id: String { name }
}

private struct AboutCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            content
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        }
    }
}

private struct AboutSectionHeader: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)

            Text(detail)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct AboutAuditRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)

            Spacer(minLength: 0)

            Text(verbatim: value)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }
}

private struct AboutInfoBlock: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.42))
                .textCase(.uppercase)

            Text(verbatim: value)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.74))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct AboutProjectCard: View {
    let project: IslandThirdPartyProject
    let openRepository: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(project.name)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)

                    Text(project.summary)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.56))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                HStack(spacing: 8) {
                    if let versionText = project.versionText {
                        aboutTag(versionText)
                    }

                    aboutTag(project.licenseName)
                }
            }

            AboutInfoBlock(title: "Repository", value: project.repositoryURL)

            VStack(alignment: .leading, spacing: 8) {
                Text(project.evidenceTitle)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.42))
                    .textCase(.uppercase)

                ForEach(project.evidenceItems, id: \.self) { item in
                    Text(verbatim: item)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.74))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Button(action: openRepository) {
                Text("View Source")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.035))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        }
    }

    private func aboutTag(_ text: String) -> some View {
        Text(verbatim: text)
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundStyle(.white.opacity(0.68))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.08), in: Capsule())
    }
}
