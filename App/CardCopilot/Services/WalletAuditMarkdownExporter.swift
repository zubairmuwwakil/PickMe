import Foundation
import CardCopilotEngine
import CardCopilotStore

/// Generates formatted Markdown (.md) audit reports summarizing wallet performance,
/// keep/cancel decisions, and acquisition opportunities for export to Notes, Files, or sharing.
public struct WalletAuditMarkdownExporter {
    public init() {}

    public static func generateReport(
        portfolioAnalysis: PortfolioAnalysis?,
        acquisitionAnalysis: AcquisitionAnalysis?,
        catalogue: Catalogue,
        distributionName: String = "Standard ($40k Household)",
        metrics: ExperimentMetrics? = nil
    ) -> String {
        var md = ""

        // Header
        md += "# PickMe Wallet & Rewards Audit Report\n\n"
        let dateStr = Date().formatted(date: .long, time: .shortened)
        md += "> Generated on \(dateStr) by **PickMe (Canadian Card Copilot)**  \n"
        md += "> *100% On-Device · Privacy by Construction · Deterministic Semantics*\n\n"
        md += "---\n\n"

        // Spend Assumption
        md += "## 1. Spend Profile Assumption\n\n"
        md += "- **Active Profile:** \(distributionName)\n"
        if let analysis = portfolioAnalysis {
            let totalSpend = analysis.totalAnnualSpendCad
            let netPortfolioValue = analysis.portfolioValueCad - analysis.totalAnnualFeesCad
            md += String(format: "- **Projected Annual Spend:** C$%.2f\n", totalSpend)
            md += String(format: "- **Total Annual Rewards Earned:** C$%.2f\n", analysis.portfolioValueCad)
            md += String(format: "- **Total Recurring Annual Fees:** C$%.2f\n", analysis.totalAnnualFeesCad)
            md += String(format: "- **Net Portfolio Return:** C$%.2f (%.2f%% return on spend)\n\n",
                         netPortfolioValue,
                         totalSpend > 0 ? (netPortfolioValue / totalSpend * 100.0) : 0.0)
        }

        // Keep or Cancel Verdicts
        md += "## 2. Keep vs. Cancel Card Verdicts\n\n"
        if let analysis = portfolioAnalysis, !analysis.contributions.isEmpty {
            md += "| Card | Annual Fee | Gross Value | Marginal Lift | Verdict |\n"
            md += "| :--- | :--- | :--- | :--- | :--- |\n"

            for contribution in analysis.contributions {
                let card = catalogue.cards.first(where: { $0.cardId == contribution.cardId })
                let name = card?.officialName ?? contribution.cardId

                let verdictStr: String
                switch contribution.verdict {
                case .freeToKeep:
                    verdictStr = "✅ **FREE TO KEEP**"
                case .keep:
                    verdictStr = "✅ **KEEP**"
                case .cancel:
                    verdictStr = "❌ **CANCEL**"
                case .downgrade:
                    verdictStr = "⚠️ **DOWNGRADE**"
                }

                md += String(format: "| %-30@ | C$%6.2f | C$%7.2f | %+8.2f CAD | %-14@ |\n",
                             name, contribution.annualFeeCad, contribution.grossRewardValueCad,
                             contribution.marginalValueCad, verdictStr)
            }
            md += "\n"

            md += "### Verdict Details & Rationale\n\n"
            for contribution in analysis.contributions {
                let card = catalogue.cards.first(where: { $0.cardId == contribution.cardId })
                let name = card?.officialName ?? contribution.cardId

                md += "#### \(name)\n"
                md += "- **Recommendation:** \(portfolioVerdictLabel(contribution.verdict))\n"
                md += String(format: "- **Marginal Value vs Next Best Card:** C$%.2f / year\n",
                             contribution.marginalValueCad)
                if contribution.realizedCreditValueCad > 0.01 {
                    md += String(format: "- **Confirmed Credits Recovered:** C$%.2f / year (counted)\n",
                                 contribution.realizedCreditValueCad)
                }
                if contribution.unspentCreditPotentialCad > 0.01 {
                    md += String(format: "- **Unused Credit Potential:** C$%.2f (not counted until posted)\n",
                                 contribution.unspentCreditPotentialCad)
                }
                if contribution.requiredBenefitValueCad > 0 {
                    md += String(format: "- **Unpriced Benefits Needed to Break Even:** C$%.2f / year\n",
                                 contribution.requiredBenefitValueCad)
                }
                if !contribution.winningBuckets.isEmpty {
                    md += "- **Winning Spend Buckets:** \(contribution.winningBuckets.joined(separator: ", "))\n"
                }
                md += "\n"
            }
        } else {
            md += "*No card verdicts available. Add cards to your PickMe wallet to generate audits.*\n\n"
        }

        // Acquisition Analysis
        md += "## 3. Top Acquisition Opportunities\n\n"
        if let acq = acquisitionAnalysis, !acq.candidates.isEmpty {
            md += "| Rank | Card | Annual Fee | Net Incremental Upside |\n"
            md += "| :--- | :--- | :--- | :--- |\n"

            for (idx, candidate) in acq.candidates.prefix(5).enumerated() {
                let card = catalogue.cards.first(where: { $0.cardId == candidate.cardId })
                let name = card?.officialName ?? candidate.cardId

                md += String(format: "| #%d | %-32@ | C$%6.2f | %+8.2f CAD / yr |\n",
                             idx + 1, name, candidate.annualFeeCad, candidate.netAnnualValueCad)
            }
            md += "\n"
        } else {
            md += "*All catalogue cards already evaluated or owned.*\n\n"
        }

        // Experiment Scoreboard (if available)
        if let metrics, metrics.confirmedCount > 0 {
            md += "## 4. Checkout Experiment Scoreboard\n\n"
            md += String(format: "- **Progress:** %d of %d confirmed checkouts\n", metrics.confirmedCount, metrics.targetCheckouts)
            if let categoryAccuracy = metrics.categoryAccuracy {
                md += String(format: "- **Category Accuracy:** %.1f%% (%@)\n", categoryAccuracy * 100.0,
                             metrics.meetsCategoryBar == true ? "✅ Meets 85% bar" : "⚠️ Below 85% target")
            }
            if let arithmeticCorrectRate = metrics.arithmeticCorrectRate {
                md += String(format: "- **Arithmetic Correctness:** %.1f%% (%@)\n\n", arithmeticCorrectRate * 100.0,
                             metrics.meetsArithmeticBar == true ? "✅ Meets 100% bar" : "⚠️ Discrepancy detected")
            } else {
                md += "- **Arithmetic Correctness:** Not enough eligible checkouts yet\n\n"
            }
        }

        md += "---\n"
        md += "*Exported by PickMe · Canadian Card Copilot*\n"

        return md
    }

    private static func portfolioVerdictLabel(_ verdict: PortfolioVerdict) -> String {
        switch verdict {
        case .freeToKeep: "Free to keep"
        case .keep: "Keep"
        case .downgrade: "Downgrade"
        case .cancel: "Cancel"
        }
    }

    /// Saves the markdown report to a temporary file URL suitable for UIActivityViewController / ShareLink.
    public static func createTemporaryReportFile(
        portfolioAnalysis: PortfolioAnalysis?,
        acquisitionAnalysis: AcquisitionAnalysis?,
        catalogue: Catalogue,
        distributionName: String = "Standard ($40k Household)"
    ) -> URL? {
        let content = generateReport(
            portfolioAnalysis: portfolioAnalysis,
            acquisitionAnalysis: acquisitionAnalysis,
            catalogue: catalogue,
            distributionName: distributionName
        )
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "PickMe_Wallet_Audit_\(Date().formatted(.iso8601.year().month().day())).md"
        let fileURL = tempDir.appendingPathComponent(fileName)

        do {
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            return fileURL
        } catch {
            return nil
        }
    }
}
