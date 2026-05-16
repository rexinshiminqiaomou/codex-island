import SwiftUI
import AppKit

/// One-click share artifact for the Cost screen. It turns the existing local
/// cost snapshot into a 16:9 image built around CodexIsland's notch shape.
struct ShareReceiptButton: View {
    @ObservedObject private var costStore = CostStore.shared
    @ObservedObject private var usageStore = UsageStore.shared
    @ObservedObject private var visibility = ProviderVisibilityStore.shared
    @ObservedObject private var tokenMode = TokenCountModeStore.shared
    @State private var hovered = false
    @State private var copied = false

    private var canShare: Bool {
        visibility.claudeVisible || visibility.codexVisible
    }

    var body: some View {
        Button(action: copyReceipt) {
            Image(systemName: copied ? "checkmark" : "square.and.arrow.up")
                .font(Typography.button)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white.opacity(hovered || copied ? 0.78 : 0.42))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
                .background {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(.white.opacity(hovered || copied ? 0.08 : 0))
                }
        }
        .buttonStyle(.plain)
        .disabled(!canShare)
        .opacity(canShare ? 1 : 0.35)
        .onHover { hovered = $0 }
        .help(canShare ? "Copy receipt card" : "Show a provider to copy receipt card")
        .animation(.strongEaseOut, value: hovered)
        .animation(.strongEaseOut, value: copied)
        .accessibilityLabel(copied ? "Receipt card copied" : "Copy receipt card")
        .accessibilityHint("Copies a shareable CodexIsland receipt image")
    }

    @MainActor
    private func copyReceipt() {
        guard canShare else { return }
        let snapshot = NotchReceiptSnapshot(
            cost: costStore,
            usage: usageStore,
            visibility: visibility,
            tokenMode: tokenMode.mode
        )
        guard NotchReceiptRenderer.copyToPasteboard(snapshot) else { return }
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            copied = false
        }
    }
}

@MainActor
private enum NotchReceiptRenderer {
    static func copyToPasteboard(_ snapshot: NotchReceiptSnapshot) -> Bool {
        let card = NotchReceiptCard(snapshot: snapshot)
            .frame(width: 1200, height: 675)

        let renderer = ImageRenderer(content: card)
        renderer.scale = 1
        guard let image = renderer.nsImage else { return false }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        if let png = image.pngData {
            item.setData(png, forType: .png)
        }
        if let tiff = image.tiffRepresentation {
            item.setData(tiff, forType: .tiff)
        }
        return pasteboard.writeObjects([item])
    }
}

private struct NotchReceiptCard: View {
    let snapshot: NotchReceiptSnapshot

    var body: some View {
        ZStack {
            ReceiptCanvasBackground()

            VStack(spacing: 20) {
                MacNotchHeader(snapshot: snapshot)
                ReceiptCommandPanel(snapshot: snapshot)
                ReceiptCardFooter()
            }
            .frame(width: 1040)
        }
        .frame(width: 1200, height: 675)
        .clipped()
    }
}

private struct MacNotchHeader: View {
    let snapshot: NotchReceiptSnapshot

    var body: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(red: 0.038, green: 0.041, blue: 0.049))
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(.white.opacity(0.08))
                        .frame(height: 1)
                }
                .frame(width: 1040, height: 76)

            HStack {
                Text("CodexIsland")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.88))

                Spacer()

                Text("local-only usage receipt")
                    .font(Typography.label)
                    .foregroundStyle(.white.opacity(0.48))
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)

            IslandShape()
                .fill(.black)
                .frame(width: 344, height: 68)
                .overlay(alignment: .bottom) {
                    NotchStatusStrip(providers: snapshot.providers)
                        .padding(.horizontal, 22)
                        .padding(.bottom, 13)
                }
                .shadow(color: .black.opacity(0.56), radius: 22, y: 11)
                .shadow(color: IslandColor.cobalt.opacity(0.20), radius: 18)
        }
        .frame(width: 1040, height: 86)
    }
}

private struct NotchStatusStrip: View {
    let providers: [ReceiptProviderSlice]

    var body: some View {
        HStack(spacing: 14) {
            ForEach(providers) { provider in
                HStack(spacing: 7) {
                    Circle()
                        .fill(provider.color)
                        .frame(width: 7, height: 7)
                        .shadow(color: provider.color.opacity(0.55), radius: 5)
                    Text(provider.name)
                        .font(Typography.micro)
                        .foregroundStyle(.white.opacity(0.58))
                    Text(provider.usagePercent)
                        .font(Typography.caption)
                        .foregroundStyle(.white.opacity(0.82))
                        .monospacedDigit()
                }
                .lineLimit(1)
            }
        }
    }
}

private struct ReceiptCommandPanel: View {
    let snapshot: NotchReceiptSnapshot

    var body: some View {
        VStack(spacing: 0) {
            panelHeader
            ReceiptHairline()

            HStack(spacing: 0) {
                hero
                    .frame(width: 552, alignment: .leading)

                ReceiptVerticalHairline()
                    .padding(.vertical, 22)

                ProviderSplitList(providers: snapshot.providers)
            }
            .frame(height: 298)

            ReceiptHairline()
            metricsBar
        }
        .frame(width: 1040, height: 462)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(red: 0.055, green: 0.058, blue: 0.067))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(.white.opacity(0.095), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.48), radius: 34, y: 20)
        }
    }

    private var panelHeader: some View {
        HStack(spacing: 12) {
            Text("AI Usage Receipt")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))

            Text(snapshot.monthLabel)
                .font(Typography.chip)
                .tracking(0.8)
                .foregroundStyle(.white.opacity(0.68))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(.white.opacity(0.075))
                        .overlay {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .strokeBorder(.white.opacity(0.09), lineWidth: 0.5)
                        }
                }

            Spacer()

            HStack(spacing: 7) {
                Circle()
                    .fill(IslandColor.liveTeal)
                    .frame(width: 7, height: 7)
                    .shadow(color: IslandColor.liveTeal.opacity(0.55), radius: 5)
                Text("local estimate")
                    .font(Typography.label)
                    .foregroundStyle(.white.opacity(0.54))
            }
        }
        .frame(height: 64)
        .padding(.horizontal, 24)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("API-equivalent usage")
                .font(Typography.sectionLabel)
                .tracking(0.8)
                .foregroundStyle(.white.opacity(0.46))

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("$")
                    .font(.system(size: 50, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.86))
                Text(snapshot.dollarAmountText)
                    .font(.system(size: 104, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.70)
            }
            .padding(.top, 14)

            Text("from Claude Code + Codex logs on this Mac")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white.opacity(0.58))
                .padding(.top, 4)

            HStack(spacing: 10) {
                ReceiptValuePill(value: snapshot.tokensText, label: snapshot.tokensLabel)
                ReceiptValuePill(value: snapshot.valueText, label: snapshot.valueLabel)
            }
            .padding(.top, 28)
        }
        .padding(.leading, 34)
        .padding(.trailing, 28)
    }

    private var metricsBar: some View {
        HStack(spacing: 0) {
            ReceiptMetricColumn(title: "today", value: snapshot.todayDollarsText, muted: "API-equivalent")
            ReceiptVerticalHairline()
                .padding(.vertical, 16)
            ReceiptMetricColumn(title: "tokens", value: snapshot.tokensText, muted: snapshot.tokensLabel)
            ReceiptVerticalHairline()
                .padding(.vertical, 16)
            ReceiptMetricColumn(title: "split", value: snapshot.providerText, muted: "monthly share")
        }
        .frame(height: 98)
    }
}

private struct ProviderSplitList: View {
    let providers: [ReceiptProviderSlice]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Provider split")
                    .font(Typography.sectionLabel)
                    .tracking(0.8)
                    .foregroundStyle(.white.opacity(0.46))
                Spacer()
                Text("today / month")
                    .font(Typography.label)
                    .foregroundStyle(.white.opacity(0.38))
            }
            .padding(.bottom, 14)

            VStack(spacing: 8) {
                ForEach(providers) { provider in
                    ProviderSplitRow(provider: provider)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ProviderSplitRow: View {
    let provider: ReceiptProviderSlice

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(provider.color.opacity(0.13))
                    Circle()
                        .fill(provider.color)
                        .frame(width: 8, height: 8)
                }
                .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 7) {
                        Text(provider.name)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.88))
                        if let plan = provider.planLabel {
                            Text(plan)
                                .font(Typography.chip)
                                .tracking(0.8)
                                .foregroundStyle(.white.opacity(0.55))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background {
                                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                                        .fill(.white.opacity(0.07))
                                }
                        }
                    }

                    Text(provider.usagePercent)
                        .font(Typography.caption)
                        .foregroundStyle(.white.opacity(0.42))
                        .monospacedDigit()
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(provider.todayDollarsText)
                        .font(Typography.caption)
                        .foregroundStyle(.white.opacity(0.48))
                    Text(provider.dollarsText)
                        .font(.system(size: 18, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.90))
                        .monospacedDigit()
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(.white.opacity(0.055))
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(provider.color)
                        .frame(width: max(6, geo.size.width * CGFloat(provider.dollarShare)))
                }
            }
            .frame(height: 6)
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.white.opacity(0.034))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(.white.opacity(0.065), lineWidth: 0.5)
                }
        }
    }
}

private struct ReceiptValuePill: View {
    let value: String
    let label: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Text(value)
                .font(Typography.bodyNumber)
                .foregroundStyle(.white.opacity(0.92))
                .monospacedDigit()
            Text(label)
                .font(Typography.label)
                .foregroundStyle(.white.opacity(0.43))
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(.white.opacity(0.052))
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(.white.opacity(0.075), lineWidth: 0.5)
                }
        }
    }
}

private struct ReceiptMetricColumn: View {
    let title: String
    let value: String
    let muted: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(Typography.sectionLabel)
                .tracking(0.8)
                .foregroundStyle(.white.opacity(0.38))
            Text(value)
                .font(.system(size: 20, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.90))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(muted)
                .font(Typography.label)
                .foregroundStyle(.white.opacity(0.38))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
    }
}

private struct ReceiptCardFooter: View {
    var body: some View {
        HStack {
            Text("Estimated locally from Claude Code + Codex logs. No telemetry. No upload.")
                .font(Typography.label)
                .foregroundStyle(.white.opacity(0.42))

            Spacer()

            Text("brew install --cask ericjypark/tap/codexisland")
                .font(Typography.caption)
                .foregroundStyle(.white.opacity(0.56))
        }
    }
}

private struct ReceiptHairline: View {
    var body: some View {
        Rectangle()
            .fill(.white.opacity(0.075))
            .frame(height: 1)
    }
}

private struct ReceiptVerticalHairline: View {
    var body: some View {
        Rectangle()
            .fill(.white.opacity(0.075))
            .frame(width: 1)
    }
}

private struct ReceiptCanvasBackground: View {
    var body: some View {
        ZStack {
            Color(red: 0.032, green: 0.034, blue: 0.041)
            LinearGradient(
                colors: [
                    .white.opacity(0.040),
                    .clear,
                    .black.opacity(0.22)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            ReceiptGrid()
        }
    }
}

private struct ReceiptGrid: View {
    var body: some View {
        Canvas { context, size in
            var path = Path()
            for x in stride(from: 0.0, through: size.width, by: 64.0) {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
            }
            for y in stride(from: 0.0, through: size.height, by: 64.0) {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.stroke(path, with: .color(.white.opacity(0.025)), lineWidth: 1)
        }
    }
}

private struct NotchReceiptSnapshot {
    let providers: [ReceiptProviderSlice]
    let monthLabel: String
    let totalDollars: Double
    let totalTokens: Int
    let planDollars: Double?
    let tokenMode: TokenCountMode

    @MainActor
    init(
        cost: CostStore,
        usage: UsageStore,
        visibility: ProviderVisibilityStore,
        tokenMode: TokenCountMode
    ) {
        let includeClaude = visibility.claudeVisible
        let includeCodex = visibility.codexVisible
        var slices: [ReceiptProviderSlice] = []

        if includeClaude {
            slices.append(Self.slice(
                name: "Claude",
                color: IslandColor.claude,
                today: cost.claude.today,
                month: cost.claude.month,
                usage: usage.claude,
                plan: Self.planUSD(provider: .claude, plan: usage.claude.plan),
                tokenMode: tokenMode
            ))
        }
        if includeCodex {
            slices.append(Self.slice(
                name: "Codex",
                color: IslandColor.codex,
                today: cost.codex.today,
                month: cost.codex.month,
                usage: usage.codex,
                plan: Self.planUSD(provider: .codex, plan: usage.codex.plan),
                tokenMode: tokenMode
            ))
        }

        let dollars = slices.reduce(0) { $0 + $1.dollars }
        let tokens = slices.reduce(0) { $0 + $1.tokens }
        let plan = slices.compactMap(\.planDollars).reduce(0, +)
        let normalized = slices.map { slice in
            slice.withDollarShare(dollars > 0 ? slice.dollars / dollars : 1 / Double(max(1, slices.count)))
        }

        self.providers = normalized
        self.monthLabel = normalized.first?.monthLabel ?? CostBucketing.currentMonthLabel()
        self.totalDollars = dollars
        self.totalTokens = tokens
        self.planDollars = plan > 0 ? plan : nil
        self.tokenMode = tokenMode
    }

    var dollarsText: String {
        Self.formatDollars(totalDollars)
    }

    var dollarAmountText: String {
        Self.formatWholeNumber(totalDollars)
    }

    var todayDollarsText: String {
        Self.formatDollars(providers.reduce(0) { $0 + $1.todayDollars })
    }

    var tokensText: String {
        Self.formatTokens(totalTokens)
    }

    var tokensLabel: String {
        switch tokenMode {
        case .all: return "tokens processed"
        case .billable: return "input + output tokens"
        }
    }

    var valueText: String {
        guard let planDollars, planDollars > 0 else { return "local" }
        return String(format: "%.1fx", totalDollars / planDollars)
    }

    var valueLabel: String {
        guard planDollars != nil else { return "local estimate" }
        return "plan value"
    }

    var providerText: String {
        providers.map { provider in
            "\(Int((provider.dollarShare * 100).rounded()))% \(provider.name)"
        }
        .joined(separator: " / ")
    }

    var includesClaude: Bool {
        providers.contains { $0.name == "Claude" }
    }

    var includesCodex: Bool {
        providers.contains { $0.name == "Codex" }
    }

    var breakdownTitle: String {
        guard providers.count == 1, let provider = providers.first else {
            return "Claude / Codex breakdown"
        }
        return "\(provider.name) breakdown"
    }

    private static func slice(
        name: String,
        color: Color,
        today: CostWindow,
        month: CostWindow,
        usage: AppUsage,
        plan: Double?,
        tokenMode: TokenCountMode
    ) -> ReceiptProviderSlice {
        ReceiptProviderSlice(
            name: name,
            shortName: String(name.prefix(1)),
            color: color,
            todayDollars: today.dollars,
            dollars: month.dollars,
            tokens: tokenMode == .all ? month.tokens : month.billableTokens,
            usagePercent: "\(usage.fiveHour.percentInt)% 5h",
            monthLabel: month.label,
            planLabel: usage.plan?.uppercased(),
            planDollars: plan,
            dollarShare: 0
        )
    }

    private static func planUSD(provider: TokenEvent.Provider, plan: String?) -> Double? {
        guard let plan = plan?.lowercased() else { return nil }
        switch (provider, plan) {
        case (.claude, "pro"): return 20
        case (.claude, "max"): return 200
        case (.codex, "plus"): return 20
        case (.codex, "pro"): return 200
        default: return nil
        }
    }

    private static func formatDollars(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = value < 100 ? 2 : 0
        formatter.minimumFractionDigits = value < 100 ? 2 : 0
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "$%.0f", value)
    }

    private static func formatWholeNumber(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.0f", value)
    }

    private static func formatTokens(_ count: Int) -> String {
        let value = Double(count)
        if count < 1_000 { return "\(count)" }
        if count < 1_000_000 { return String(format: "%.0fk", value / 1_000) }
        if count < 1_000_000_000 { return String(format: "%.1fM", value / 1_000_000) }
        return String(format: "%.2fB", value / 1_000_000_000)
    }
}

private struct ReceiptProviderSlice: Identifiable {
    let name: String
    let shortName: String
    let color: Color
    let todayDollars: Double
    let dollars: Double
    let tokens: Int
    let usagePercent: String
    let monthLabel: String
    let planLabel: String?
    let planDollars: Double?
    let dollarShare: Double

    var id: String { name }

    var dollarsText: String {
        NotchReceiptSnapshot.formatProviderDollars(dollars)
    }

    var todayDollarsText: String {
        NotchReceiptSnapshot.formatProviderDollars(todayDollars)
    }

    func withDollarShare(_ share: Double) -> ReceiptProviderSlice {
        ReceiptProviderSlice(
            name: name,
            shortName: shortName,
            color: color,
            todayDollars: todayDollars,
            dollars: dollars,
            tokens: tokens,
            usagePercent: usagePercent,
            monthLabel: monthLabel,
            planLabel: planLabel,
            planDollars: planDollars,
            dollarShare: share
        )
    }
}

private extension NotchReceiptSnapshot {
    static func formatProviderDollars(_ value: Double) -> String {
        if value < 100 {
            return String(format: "$%.2f", value)
        }
        return String(format: "$%.0f", value)
    }
}

private extension NSImage {
    var pngData: Data? {
        guard let tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffRepresentation) else {
            return nil
        }
        return bitmap.representation(using: .png, properties: [:])
    }
}
