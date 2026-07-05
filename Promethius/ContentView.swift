//
//  ContentView.swift
//  Promethius
//
//  Created by Isidoro Flores on 7/3/26.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationSplitView {
            
            Text("Agents / models  active agents view live here")
            
        }
        detail : {
            Text("Agent Dashboard")
            DashboardView()
        }
    }
}

#Preview {
    ContentView()
}
