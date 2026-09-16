//
//  HoldSwitchView.swift
//  Lyre
//
//  Created by Daniel Buzlea on 5/14/26.
//

import SwiftUI

struct HoldSwitchView: View {
    @Binding var isEnabled: Bool
    
    var body: some View {
        VStack(spacing: 2) {
            RoundedRectangle(cornerRadius: 4)
                .fill(
                    LinearGradient(
                        colors: [Color(white: 0.6), Color(white: 0.4)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 50, height: 20)
                .overlay {
                    HStack(spacing: 4) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(isEnabled ? .orange : .white.opacity(0.4))
                        
                        Rectangle()
                            .fill(isEnabled ? Color.orange : Color.white.opacity(0.6))
                            .frame(width: 20, height: 12)
                            .cornerRadius(2)
                            .overlay {
                                RoundedRectangle(cornerRadius: 2)
                                    .stroke(Color.black.opacity(0.3), lineWidth: 1)
                            }
                            .offset(x: isEnabled ? 0 : -8)
                            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isEnabled)
                    }
                }
                .onLongPressGesture(minimumDuration: 0.6) {
                    let generator = UIImpactFeedbackGenerator(style: .medium)
                    generator.prepare()
                    generator.impactOccurred()
                    isEnabled.toggle()
                }
                .accessibilityLabel(isEnabled ? "Hold switch, enabled" : "Hold switch, disabled")
                .accessibilityHint("Long press to toggle hold")
                .accessibilityAddTraits(.isButton)
            
            Text("HOLD")
                .font(.system(size: 6, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
        }
    }
}
