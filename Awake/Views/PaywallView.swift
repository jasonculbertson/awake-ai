import SwiftUI
import StoreKit

struct PaywallView: View {
    @EnvironmentObject var viewModel: MenuBarViewModel
    @State private var selectedPlan: PlanOption = .yearly
    @State private var showAPIKeySetup = false

    enum PlanOption { case monthly, yearly, pro }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 6) {
                Image(systemName: "wand.and.stars")
                    .font(.title2)
                    .foregroundStyle(.orange)

                Text("Unlock AI Commands")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text("Tell Awake what to do in plain English")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 16)
            .padding(.horizontal, 12)

            // Feature list
            VStack(alignment: .leading, spacing: 6) {
                featureRow("Stay awake for 2 hours")
                featureRow("Keep awake when Xcode is open")
                featureRow("Turn on at 3am for 30 minutes")
                featureRow("Pause for 10 minutes")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            // Plan picker
            VStack(spacing: 8) {
                if let yearly = viewModel.storeKit.yearlyProduct {
                    planButton(
                        plan: .yearly,
                        title: "Annual",
                        price: yearly.displayPrice + "/year",
                        badge: "Best Value",
                        product: yearly
                    )
                }

                if let monthly = viewModel.storeKit.monthlyProduct {
                    planButton(
                        plan: .monthly,
                        title: "Monthly",
                        price: monthly.displayPrice + "/month",
                        badge: nil,
                        product: monthly
                    )
                }

                if let pro = viewModel.storeKit.proProduct {
                    planButton(
                        plan: .pro,
                        title: "Lifetime",
                        price: pro.displayPrice + " once",
                        badge: nil,
                        product: pro
                    )
                }

                // Fallback if products haven't loaded yet
                if viewModel.storeKit.yearlyProduct == nil &&
                   viewModel.storeKit.monthlyProduct == nil &&
                   viewModel.storeKit.proProduct == nil {
                    loadingPlaceholders
                }
            }
            .padding(.horizontal, 12)

            if let error = viewModel.storeKit.purchaseError {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 12)
                    .padding(.top, 4)
            }

            // BYOK option
            VStack(spacing: 4) {
                Divider().padding(.horizontal, 12)

                Button(action: {
                    showAPIKeySetup = true
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "key")
                            .font(.caption2)
                        Text("Use your own API key instead")
                            .font(.caption2)
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Button(action: {
                    Task { await viewModel.storeKit.restorePurchases() }
                }) {
                    Text("Restore purchases")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 8)
        }
        .onChange(of: showAPIKeySetup) {
            if showAPIKeySetup {
                showAPIKeySetup = false
                openAPIKeyWindow(keychainService: viewModel.keychainService) {
                    viewModel.refreshAIStatus()
                }
            }
        }
    }

    // MARK: - Subviews

    private func featureRow(_ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark")
                .font(.caption2.bold())
                .foregroundStyle(.orange)
                .frame(width: 12)
            Text(text)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func planButton(plan: PlanOption, title: String, price: String, badge: String?, product: Product) -> some View {
        let isSelected = selectedPlan == plan
        return Button(action: { selectedPlan = plan }) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.caption.bold())
                        if let badge = badge {
                            Text(badge)
                                .font(.caption2.bold())
                                .foregroundStyle(.black)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.orange)
                                .clipShape(Capsule())
                        }
                    }
                    Text(price)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if viewModel.storeKit.isPurchasing && isSelected {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Button("Subscribe") {
                        Task { await viewModel.storeKit.purchase(product) }
                    }
                    .font(.caption.bold())
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .controlSize(.small)
                    .disabled(viewModel.storeKit.isPurchasing)
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected
                        ? Color.orange.opacity(0.08)
                        : Color(nsColor: .controlBackgroundColor).opacity(0.5))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        isSelected ? Color.orange.opacity(0.4) : Color(nsColor: .separatorColor).opacity(0.3),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private var loadingPlaceholders: some View {
        VStack(spacing: 8) {
            ForEach(0..<2, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                    .frame(height: 52)
                    .overlay(
                        ProgressView()
                            .controlSize(.small)
                    )
            }
        }
    }
}
