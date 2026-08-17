import SwiftUI

/// The app shell: the navigation stack, the home screen inside it, and first run.
///
/// This is the only place in the app that owns an `AppCoordinator` or a `NavigationStack`. Features
/// push routes; they never construct navigation, which is what keeps "where can the user go from
/// here" answerable by reading one file.
struct RootView: View {

    @Environment(\.accessibleAnimation) private var accessibleAnimation

    @State private var coordinator = AppCoordinator()
    @State private var onboarding = OnboardingState.shared
    @State private var appEnvironment = AppEnvironment()

    /// Non-nil while the sample document is being rendered, so the button can show progress instead
    /// of appearing to do nothing for the ~100ms of render plus OCR startup.
    @State private var isPreparingSample = false
    @State private var showingAbout = false
    @State private var showingOnboarding = !OnboardingState.shared.hasCompleted
    #if DEBUG
    @State private var showingTokenGallery = false
    #endif

    var body: some View {
        NavigationStack(path: $coordinator.path) {
            home
                .navigationDestination(for: AppRoute.self) { route in
                    RouteDestination(route: route)
                }
        }
        .tint(Token.Accent.violetLight)
        .environment(coordinator)
        .environment(appEnvironment)
        .modelContainer(appEnvironment.container)
        .fullScreenCover(isPresented: $showingOnboarding) {
            OnboardingView(
                onTrySample: {
                    finishOnboarding()
                    startSample()
                },
                onSkip: finishOnboarding
            )
        }
        .sheet(isPresented: $showingAbout) {
            NavigationStack { AboutView(onboarding: onboarding) }
                .preferredColorScheme(.dark)
        }
        // The coordinator's paywall seam. `presentPaywall()` is the only thing that sets
        // `presentedSheet`, so this is the single place the subscription screen appears — Phase 3
        // changes what is inside it and nothing else moves.
        .sheet(
            isPresented: Binding(
                get: { coordinator.presentedSheet != nil },
                set: { if !$0 { coordinator.presentedSheet = nil } }
            )
        ) {
            if let sheet = coordinator.presentedSheet {
                NavigationStack { RouteDestination(route: sheet) }
                    .preferredColorScheme(.dark)
            }
        }
        // Onboarding can be re-armed from About, which resets the persisted flag.
        .onChange(of: onboarding.hasCompleted) { _, completed in
            showingOnboarding = !completed
        }
        .task {
            appEnvironment.prepareStorage()
        }
    }

    // MARK: - Home

    private var home: some View {
        ScrollView {
            VStack(spacing: Token.Space.lg) {
                Spacer(minLength: Token.Space.xl)

                mark
                headline

                if appEnvironment.storageIsTemporary {
                    storageWarning
                }

                actions

                privacyNote

                Spacer(minLength: Token.Space.lg)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Token.Space.lg)
            .padding(.bottom, Token.Space.xl)
        }
        .scrollBounceBehavior(.basedOnSize)
        .ambientBackground()
        .navigationTitle("Redact")
        .toolbar(.hidden, for: .navigationBar)
        .overlay(alignment: .topTrailing) { topBar }
    }

    private var topBar: some View {
        HStack(spacing: Token.Space.xs) {
            #if DEBUG
            // Debug-only entry to the token gallery so the simulator run in verify.sh can reach it.
            // Compiled out of Release, so it adds no user-visible surface (CLAUDE.md rule 10).
            Button {
                showingTokenGallery = true
            } label: {
                Image(systemName: "paintpalette.fill")
                    .typeStyle(Typography.caption)
                    .foregroundStyle(Token.Text.faint)
                    .frame(width: Token.Size.minimumHitTarget, height: Token.Size.minimumHitTarget)
            }
            .accessibilityLabel("Open design token gallery")
            .sheet(isPresented: $showingTokenGallery) { TokenGallery() }
            #endif

            Button {
                showingAbout = true
            } label: {
                Image(systemName: "info.circle")
                    .typeStyle(Typography.body)
                    .foregroundStyle(Token.Text.muted)
                    .frame(width: Token.Size.minimumHitTarget, height: Token.Size.minimumHitTarget)
            }
            .accessibilityLabel("About Redact")
            .accessibilityHint("Privacy policy, terms of use, and how Redact protects you")
        }
        .padding(.trailing, Token.Space.sm)
        .padding(.top, Token.Space.xs)
    }

    /// Closes first run and remembers it. Split out because two buttons end onboarding and both
    /// must persist the flag — a "Skip" that does not persist shows the explainer again next launch.
    private func finishOnboarding() {
        onboarding.complete()
        showingOnboarding = false
    }

    private var mark: some View {
        RoundedRectangle(cornerRadius: Token.Radius.control, style: .continuous)
            .fill(Token.gradient)
            .frame(width: markSize, height: markSize)
            .overlay(
                Image(systemName: "eye.slash.fill")
                    .typeStyle(Typography.markGlyph)
                    .foregroundStyle(.white)
            )
            .shadow(Token.Shadow.mark)
            .accessibilityHidden(true)
    }

    /// The mark grows with the user's text size so it stays in proportion to the wordmark beneath it
    /// at Larger Accessibility Sizes (CLAUDE.md rule 4).
    @ScaledMetric(relativeTo: .largeTitle) private var markSize = Token.Size.mark

    private var headline: some View {
        VStack(spacing: Token.Space.sm) {
            Text("Redact")
                .typeStyle(Typography.displayXL)
                .foregroundStyle(Token.Text.primary)

            Text("Find personal information in any document and remove it permanently.")
                .typeStyle(Typography.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(Token.Text.muted)
                .frame(maxWidth: Token.Layout.proseWidth)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Redact. Find personal information in any document and remove it permanently.")
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Actions

    private var actions: some View {
        VStack(spacing: Token.Space.sm) {
            PrimaryButton("Scan a document", systemImage: "doc.viewfinder") {
                coordinator.push(.scan)
            }

            SecondaryButton(
                isPreparingSample ? "Preparing the sample…" : "Try a sample document",
                systemImage: "wand.and.sparkles"
            ) {
                startSample()
            }
            .disabled(isPreparingSample)
            .accessibilityHint(SampleDocument.subtitle)

            SecondaryButton("Your documents", systemImage: "square.stack.3d.up.fill", prominence: .plain) {
                coordinator.push(.library)
            }
            .accessibilityHint("Documents you have already redacted")
        }
        .frame(maxWidth: Token.Layout.proseWidth)
        .accessibleAnimation(Motion.snappy, value: isPreparingSample)
    }

    /// Renders the built-in payslip, runs the real pipeline on it, then opens the editor.
    ///
    /// Render → detect → navigate as **one** task, matching `ScanView`. Pushing first and letting
    /// the editor's own `.task` start the pipeline would work, but only by luck: the editor only
    /// self-starts while `processing` is still `.idle`, so a push followed by a separate `Task`
    /// races to see which sets the state first, and losing the race runs OCR twice.
    ///
    /// The whole thing is well under a second for one page, which is why the editor is shown
    /// already populated rather than filling in under the user.
    private func startSample() {
        guard !isPreparingSample else { return }
        isPreparingSample = true

        Task { @MainActor in
            let session = await SampleDocument.makeSession()
            await DocumentPipeline.run(on: session)
            isPreparingSample = false
            // Pushed even when the run failed: the editor renders the failure with a retry, which
            // is a recovery path. Staying here with a silently reset button is a dead end.
            coordinator.push(.editor(session))
        }
    }

    // MARK: - Status

    private var storageWarning: some View {
        HStack(alignment: .top, spacing: Token.Space.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .typeStyle(Typography.body)
                .foregroundStyle(Token.Accent.amberLight)
                .accessibilityHidden(true)

            Text("Saved documents can't be stored on this device right now, so anything you redact will be lost when you close Redact. Redacting and sharing still work.")
                .typeStyle(Typography.callout)
                .foregroundStyle(Token.Text.muted)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: Token.Layout.proseWidth)
        .glassCard()
        .accessibilityElement(children: .combine)
    }

    private var privacyNote: some View {
        HStack(spacing: Token.Space.xs) {
            Image(systemName: "lock.fill")
                .typeStyle(Typography.caption)
            Text("Everything happens on this device")
                .typeStyle(Typography.caption)
        }
        .foregroundStyle(Token.Text.faint)
        .padding(.horizontal, Token.Space.md)
        .padding(.vertical, Token.Space.sm)
        .background(Capsule().fill(.ultraThinMaterial))
        .overlay(Capsule().strokeBorder(Token.Line.hairline, lineWidth: Token.Size.hairlineWidth))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Everything happens on this device. Nothing is uploaded.")
    }
}

#Preview {
    RootView()
        .preferredColorScheme(.dark)
}
