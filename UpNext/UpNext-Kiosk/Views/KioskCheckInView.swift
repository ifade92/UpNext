//
//  KioskCheckInView.swift
//  UpNext
//
//  The customer-facing kiosk sign-in experience.
//  Three screens: Welcome → Name & Phone & Party Size → Confirmation.
//  No barber or service selection — clients sign in to the shared pool
//  and the next available barber claims them from the list.
//

import SwiftUI

struct KioskCheckInView: View {

    @StateObject var viewModel: KioskViewModel
    @FocusState  private var focusedField: Field?

    enum Field { case name, phone }

    var body: some View {
        ZStack {
            Color.brandNearBlack.ignoresSafeArea()

            switch viewModel.currentStep {
            case .welcome:      welcomeScreen
            case .namePhone:    namePhoneScreen
            case .confirmation: confirmationScreen
            }
        }
        .onAppear  { viewModel.onAppear()    }
        .onDisappear { viewModel.onDisappear() }
        .alert("Oops", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("Try Again") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    // MARK: - Welcome Screen

    private var welcomeScreen: some View {
        VStack(spacing: 0) {
            Spacer()

            // Shop branding
            VStack(spacing: 16) {
                UpNextMark(size: 52)

                Text("Welcome")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text("Walk-ins welcome.\nSign in to hold your spot.")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
            }

            Spacer()

            // Available barbers banner
            if !viewModel.availableBarbers.isEmpty {
                availableBarbersChips
                    .padding(.bottom, 32)
            } else {
                Text("Check with the front desk about current availability.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.4))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .padding(.bottom, 32)
            }

            // Check In button
            Button { viewModel.goToNext() } label: {
                Text("Check In")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .background(Color.accent, in: RoundedRectangle(cornerRadius: 18))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 32)
            .padding(.bottom, 48)
        }
    }

    private var availableBarbersChips: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                Circle().fill(Color.accent).frame(width: 8, height: 8)
                Text("Taking Walk-Ins Now")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.accent)
            }
            HStack(spacing: 10) {
                ForEach(viewModel.availableBarbers) { barber in
                    Text(barber.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Color.white.opacity(0.1), in: Capsule())
                        .overlay(Capsule().stroke(Color.accent.opacity(0.5), lineWidth: 1))
                }
            }
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Name & Phone & Party Size Screen

    private var namePhoneScreen: some View {
        VStack(spacing: 0) {

            // Back button
            HStack {
                Button {
                    focusedField = nil
                    viewModel.goBack()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                    .foregroundStyle(.white.opacity(0.6))
                    .font(.subheadline)
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(.horizontal, 32)
            .padding(.top, 24)

            Spacer()

            VStack(spacing: 32) {

                // Header
                VStack(spacing: 8) {
                    Text("Sign In")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Add your info to get on the list.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.5))
                }

                // Form fields
                VStack(spacing: 16) {

                    // Name (required)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Your Name")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white.opacity(0.6))
                        TextField("First & last name", text: $viewModel.customerName)
                            .font(.title3)
                            .textFieldStyle(.plain)
                            .padding(14)
                            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                            .foregroundStyle(.white)
                            .tint(Color.accent)
                            .focused($focusedField, equals: .name)
                            .submitLabel(.next)
                            .onSubmit { focusedField = .phone }
#if os(iOS)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                            .textContentType(.name)
#endif
                    }

                    // Phone (optional)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Phone Number (optional)")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white.opacity(0.6))
                        TextField("(555) 555-5555", text: $viewModel.customerPhone)
                            .font(.title3)
                            .textFieldStyle(.plain)
                            .padding(14)
                            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                            .foregroundStyle(.white)
                            .tint(Color.accent)
                            .focused($focusedField, equals: .phone)
                            .submitLabel(.done)
                            .onSubmit { focusedField = nil }
#if os(iOS)
                            .keyboardType(.phonePad)
                            .textContentType(.telephoneNumber)
#endif
                    }

                    // Party size
                    VStack(alignment: .leading, spacing: 6) {
                        Text("How many people need a cut?")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white.opacity(0.6))

                        HStack(spacing: 0) {
                            Button {
                                if viewModel.partySize > 1 { viewModel.partySize -= 1 }
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .font(.system(size: 32))
                                    .foregroundStyle(viewModel.partySize > 1 ? Color.accent : .white.opacity(0.2))
                            }
                            .buttonStyle(.plain)
                            .disabled(viewModel.partySize <= 1)

                            Spacer()

                            VStack(spacing: 2) {
                                Text("\(viewModel.partySize)")
                                    .font(.system(size: 52, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                                Text(viewModel.partySize == 1 ? "person" : "people")
                                    .font(.subheadline)
                                    .foregroundStyle(.white.opacity(0.5))
                            }

                            Spacer()

                            Button {
                                if viewModel.partySize < 8 { viewModel.partySize += 1 }
                            } label: {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 32))
                                    .foregroundStyle(Color.accent)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(16)
                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding(.horizontal, 32)
            }

            Spacer()

            // Submit
            Button {
                focusedField = nil
                viewModel.goToNext()
            } label: {
                Group {
                    if viewModel.isLoading {
                        ProgressView().tint(.white)
                    } else {
                        Text("Add Me to the List")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .background(
                    viewModel.isNameValid ? Color.accent : Color.white.opacity(0.15),
                    in: RoundedRectangle(cornerRadius: 18)
                )
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.isNameValid || viewModel.isLoading)
            .padding(.horizontal, 32)
            .padding(.bottom, 48)
        }
    }

    // MARK: - Confirmation Screen

    private var confirmationScreen: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 28) {

                // Big check + headline
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.accent.opacity(0.15))
                            .frame(width: 90, height: 90)
                        Image(systemName: "checkmark")
                            .font(.system(size: 40, weight: .bold))
                            .foregroundStyle(Color.accent)
                    }
                    Text("You're on the list!")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }

                // Queue number card
                if let entry = viewModel.confirmedEntry {
                    VStack(spacing: 20) {

                        // Spot number
                        HStack(spacing: 16) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Your spot")
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.5))
                                Text("#\(entry.position ?? 0)")
                                    .font(.system(size: 42, weight: .bold, design: .rounded))
                                    .foregroundStyle(Color.accent)
                            }
                            Spacer()
                            // Party size badge (only if > 1)
                            if let size = entry.partySize, size > 1 {
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("Group size")
                                        .font(.caption)
                                        .foregroundStyle(.white.opacity(0.5))
                                    Text("×\(size) people")
                                        .font(.title3.bold())
                                        .foregroundStyle(.white)
                                }
                            }
                        }

                        Divider().background(Color.white.opacity(0.1))

                        // Wait estimate
                        HStack {
                            Image(systemName: "clock")
                                .foregroundStyle(Color.accent)
                            Text("Estimated wait:")
                                .foregroundStyle(.white.opacity(0.6))
                            Spacer()
                            let wait = entry.estimatedWaitMinutes ?? 0
                            Text(wait == 0 ? "Up next!" : "~\(wait) min")
                                .font(.subheadline.bold())
                                .foregroundStyle(.white)
                        }
                        .font(.subheadline)
                    }
                    .padding(20)
                    .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 18))
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.accent.opacity(0.3), lineWidth: 1))
                    .padding(.horizontal, 32)
                }

                // Available barbers message
                if viewModel.availableBarbers.isEmpty {
                    Text("The next available barber will call your name.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.4))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                } else {
                    VStack(spacing: 8) {
                        Text("Taking walk-ins right now:")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.4))
                        HStack(spacing: 8) {
                            ForEach(viewModel.availableBarbers) { barber in
                                HStack(spacing: 5) {
                                    Circle().fill(Color.accent).frame(width: 6, height: 6)
                                    Text(barber.name)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(.white)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.white.opacity(0.07), in: Capsule())
                            }
                        }
                    }
                }

                Text("Auto-closing in a few seconds…")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.25))
            }

            Spacer()

            // Done button
            Button { viewModel.resetKiosk() } label: {
                Text("Done")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 18))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 32)
            .padding(.bottom, 48)
        }
    }
}
