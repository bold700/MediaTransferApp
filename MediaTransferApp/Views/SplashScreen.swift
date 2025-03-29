import SwiftUI

struct SplashScreen: View {
    @State private var isRotating = false
    @Binding var isFinished: Bool
    
    var body: some View {
        ZStack {
            Constants.appBlue
                .ignoresSafeArea()
            
            VStack(spacing: 11) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 124, height: 124)
                    .foregroundColor(.white)
                    .rotationEffect(.degrees(isRotating ? 360 : 0))
                
                Text("Media Transfer App")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                isRotating = true
            }
            
            // After 2 seconds, transition to the main app
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                withAnimation {
                    isFinished = true
                }
            }
        }
    }
} 