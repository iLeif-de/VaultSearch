import SwiftUI

/// VaultSearch configuration for `AppAboutView`.
struct VaultSearchAboutView: View {
    private var configuration: AppAboutConfiguration {
        var about = AppAboutConfiguration(
            appName: "VaultSearch",
            tagline: String(localized: "Find anything in your Obsidian vault."),
            author: "Leif Jensen-Pistorius",
            copyright: "© 2026 Leif Jensen-Pistorius"
        )
        about.role = String(localized: "Design & Development")
        about.platforms = "MAC"
        about.description = String(localized: "VaultSearch indexes the Markdown notes of your Obsidian vault on your Mac and searches them as you type: by text, tag, frontmatter property or date. Your notes never leave your computer.")
        about.footer = String(localized: "Made with curiosity.")

        about.websiteURL = URL(string: "https://studio.ileif.de/projekte/vaultsearch")
        about.websiteLabel = String(localized: "Website")
        about.websitePlaceholder = String(localized: "Website coming soon")

        about.repositoryURL = URL(string: "https://github.com/iLeif-de/VaultSearch")
        about.repositoryLabel = String(localized: "Source on GitHub")

        about.licenseTitle = String(localized: "License")
        about.licenseSummary = String(localized: "VaultSearch is free software under the MIT License.")
        about.licenseResourceName = "LICENSE"
        about.licenseDisclosureTitle = String(localized: "Show Full License")
        about.licenseUnavailableText = String(localized: "The license text could not be loaded.")

        // Colors of the app icon (Design/AppIcon.svg).
        about.accentColor = Color(red: 0.23, green: 0.17, blue: 0.66)   // #3B2BA8
        about.waveColor = Color(red: 0.24, green: 0.96, blue: 0.77)     // #3CF5C4
        about.gradientStart = Color(red: 0.07, green: 0.05, blue: 0.29) // #120D4A
        about.gradientEnd = Color(red: 0.12, green: 0.09, blue: 0.44)   // #1E1670
        return about
    }

    var body: some View {
        AppAboutView(configuration: configuration)
    }
}

#Preview {
    VaultSearchAboutView()
        .frame(width: 440, height: 660)
}
