//
//  AddAgentButton.swift
//  AgentHubMac
//
//  Created by Isidoro Flores on 7/8/26.
//

import SwiftUI

struct AddAgentButton<Destination: View>: View {
    /// Called after the sheet closes, whether or not anything was created.
    var onDismiss: () -> Void = {}
    /// The screen to present when the button is tapped.
    @ViewBuilder var destination: () -> Destination

    @State private var isHovering = false
    @State private var isPresented = false
    @State private var isRotating = false
    var body : some View {
        Button {
            isPresented = true
        } label : {
            HStack (spacing: 4){
                Text("Add Agent")
                Image(systemName: "plus")
                    // Driven by the sheet, so the plus unwinds on dismiss.
                    .rotationEffect(.degrees(isRotating ? 90 : 0))
                    .animation(.spring(response: 0.2, dampingFraction: 0.8), value: isPresented)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .scaleEffect(isHovering ? 1.05 : 1)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)){
                isHovering = hovering
                isRotating.toggle()
            }
        }
        .sheet(isPresented: $isPresented, onDismiss: onDismiss) {
            destination()
        }
    }
}

#Preview {
    AddAgentButton {
        Text("Preview destination")
    }
    .padding()
}
