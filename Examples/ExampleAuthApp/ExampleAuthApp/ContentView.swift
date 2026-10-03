import Auth
import SwiftUI

private enum Studio {
  static let background = Color(red: 0.045, green: 0.055, blue: 0.055)
  static let surface = Color(red: 0.095, green: 0.11, blue: 0.105)
  static let ink = Color(red: 0.94, green: 0.95, blue: 0.89)
  static let muted = Color(red: 0.60, green: 0.65, blue: 0.61)
  static let lime = Color(red: 0.78, green: 0.96, blue: 0.37)
  static let lavender = Color(red: 0.70, green: 0.65, blue: 0.94)
}

struct ContentView: View {
  @Environment(AuthAppModel.self) private var model
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var showsSettings = false

  var body: some View {
    @Bindable var model = model
    ScrollView {
      VStack(alignment: .leading, spacing: 28) {
        masthead
        if model.configuration == nil {
          VStack(alignment: .leading, spacing: 12) {
            eyebrow("FØR VI BEGYNNER")
            Text("En god start.").font(.system(size: 42, weight: .semibold, design: .rounded))
            Text("Koble til testmiljøet ditt, så er du klar.")
              .foregroundStyle(Studio.muted)
          }
          ConfigurationCard(draft: $model.draft) {
            Task { await model.saveConfigurationAndRestore() }
          }
          .disabled(model.isBusy)
        } else if model.isSignedIn {
          profile
        } else {
          welcome
        }
        if let message = model.message, model.messageIsError {
          Label(message, systemImage: "exclamationmark.circle")
            .font(.subheadline).foregroundStyle(Studio.ink)
            .padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.red.opacity(0.3)))
            .textSelection(.enabled)
        }
        footer
      }
      .padding(.horizontal, 26).padding(.top, 18).padding(.bottom, 24)
      .frame(maxWidth: 560).frame(maxWidth: .infinity)
    }
    .background {
      ZStack(alignment: .topTrailing) {
        Studio.background
        Circle().fill(Studio.lime.opacity(0.07)).frame(width: 340, height: 340)
          .blur(radius: 90).offset(x: 170, y: -160)
      }
      .ignoresSafeArea()
    }
    .foregroundStyle(Studio.ink)
    .preferredColorScheme(.dark)
    .tint(Studio.lime)
    .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: model.isSignedIn)
    .sheet(isPresented: $showsSettings) { settings }
    .task { await model.start() }
  }

  private var masthead: some View {
    HStack {
      HStack(spacing: 10) {
        Image(systemName: "asterisk").font(.system(size: 25, weight: .black))
          .foregroundStyle(Studio.lime)
        Text("auth.").font(.system(size: 28, weight: .bold, design: .rounded))
      }
      .accessibilityElement(children: .combine).accessibilityLabel("Auth")
      Spacer()
      Button {
        showsSettings = true
      } label: {
        Image(systemName: "slider.horizontal.3").font(.system(size: 17, weight: .medium))
          .frame(width: 46, height: 46)
          .background(Studio.surface, in: Circle())
          .overlay(Circle().stroke(Studio.ink.opacity(0.10)))
      }
      .buttonStyle(.plain).accessibilityLabel("Innstillinger")
    }
  }

  private var welcome: some View {
    VStack(alignment: .leading, spacing: 24) {
      HStack {
        eyebrow("DIN IDENTITET. DITT ROM.")
        Spacer()
        Text("01 / ACCESS").font(.system(size: 10, weight: .medium, design: .monospaced))
          .foregroundStyle(Studio.muted).accessibilityHidden(true)
      }
      IdentityArtwork()
        .frame(height: 220)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 12) {
        Text("Du er nøkkelen.")
          .font(.system(size: 44, weight: .semibold, design: .rounded))
          .tracking(-1.8).fixedSize(horizontal: false, vertical: true)
        Text("Ett øyeblikk unna. Logg inn med kontoen du allerede bruker, og gjør deg hjemme.")
          .font(.system(size: 16)).foregroundStyle(Studio.muted)
          .lineSpacing(4).fixedSize(horizontal: false, vertical: true)
      }
      VStack(spacing: 12) {
        Button {
          Task { await model.signIn(provider: .apple) }
        } label: {
          Label("Fortsett med Apple", systemImage: "apple.logo")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(StudioButtonStyle(prominent: true))
        Button {
          Task { await model.signIn(provider: .github) }
        } label: {
          HStack(spacing: 12) {
            GitHubMark().fill(Studio.ink).frame(width: 21, height: 21)
            Text("Fortsett med GitHub")
          }.frame(maxWidth: .infinity)
        }
        .buttonStyle(StudioButtonStyle(prominent: false))
      }
      .disabled(model.isBusy)
      if model.isBusy {
        HStack(spacing: 10) {
          ProgressView().tint(Studio.lime)
          Text(model.statusTitle).font(.footnote).foregroundStyle(Studio.muted)
        }.frame(maxWidth: .infinity).accessibilityElement(children: .combine)
      } else {
        Label("Din konto. Trygt på din enhet.", systemImage: "lock.shield")
          .font(.system(size: 12)).foregroundStyle(Studio.muted)
          .frame(maxWidth: .infinity)
      }
    }
  }

  private var profile: some View {
    VStack(alignment: .leading, spacing: 24) {
      HStack {
        eyebrow("DITT PERSONLIGE ROM")
        Spacer()
        HStack(spacing: 6) {
          Circle().fill(Studio.lime).frame(width: 6, height: 6)
          Text("PÅLOGGET").font(.system(size: 10, weight: .semibold, design: .monospaced))
        }.foregroundStyle(Studio.lime)
      }
      Text("Godt å se deg.")
        .font(.system(size: 42, weight: .semibold, design: .rounded)).tracking(-1.5)
        .fixedSize(horizontal: false, vertical: true)
      if let user = model.user {
        VStack(alignment: .leading, spacing: 26) {
          HStack(alignment: .top) {
            AsyncImage(url: user.picture) { image in
              image.resizable().scaledToFill()
            } placeholder: {
              ZStack {
                Studio.lavender.opacity(0.2)
                Text(String(user.displayName.prefix(1)).uppercased())
                  .font(.system(size: 38, weight: .medium, design: .rounded))
              }
            }
            .frame(width: 90, height: 90).clipShape(RoundedRectangle(cornerRadius: 28))
            .overlay(RoundedRectangle(cornerRadius: 28).stroke(Studio.ink.opacity(0.15)))
            .accessibilityHidden(true)
            Spacer()
            Image(systemName: "arrow.up.right").font(.system(size: 24, weight: .light))
              .foregroundStyle(Studio.lime).accessibilityHidden(true)
          }
          VStack(alignment: .leading, spacing: 7) {
            Text(user.displayName).font(.system(size: 30, weight: .semibold, design: .rounded))
            if let login = user.githubLogin {
              Text("@\(login)").font(.system(size: 15, design: .monospaced))
                .foregroundStyle(Studio.muted)
            }
            if let email = user.email { Text(email).font(.footnote).foregroundStyle(Studio.muted) }
          }.textSelection(.enabled)
          Rectangle().fill(Studio.ink.opacity(0.10)).frame(height: 1)
          Label(model.verification.title, systemImage: model.verification.symbol)
            .font(.system(size: 13, weight: .medium)).foregroundStyle(model.verification.color)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(26).frame(maxWidth: .infinity, alignment: .leading)
        .background {
          RoundedRectangle(cornerRadius: 32)
            .fill(
              LinearGradient(
                colors: [Studio.surface, Studio.lime.opacity(0.07)],
                startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        .overlay(RoundedRectangle(cornerRadius: 32).stroke(Studio.ink.opacity(0.10)))
      } else {
        VStack(alignment: .leading, spacing: 10) {
          Label("Du er logget inn", systemImage: "checkmark.seal")
            .font(.title3.weight(.semibold))
          Text("Hent profilen din for å fylle ut ditt personlige rom.")
            .foregroundStyle(Studio.muted).font(.subheadline)
        }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
          .background(Studio.surface, in: RoundedRectangle(cornerRadius: 28))
      }
      HStack(alignment: .top, spacing: 16) {
        Image(systemName: "lock.shield").font(.system(size: 24, weight: .light))
          .foregroundStyle(Studio.lime).frame(width: 44, height: 44)
          .background(Studio.lime.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
        VStack(alignment: .leading, spacing: 5) {
          Text("Bare ditt.").font(.headline)
          Text("Sesjonen din lagres sikkert på enheten. Du bestemmer når du vil logge ut.")
            .font(.subheadline).foregroundStyle(Studio.muted).lineSpacing(3)
        }
      }
      Button {
        Task { await model.refreshUser() }
      } label: {
        HStack {
          Text(model.isBusy ? "Oppdaterer …" : "Oppdater profil")
          Spacer()
          if model.isBusy {
            ProgressView().tint(Studio.background)
          } else {
            Image(systemName: "arrow.clockwise")
          }
        }
      }.buttonStyle(StudioButtonStyle(prominent: true)).disabled(model.isBusy)
      Button {
        Task { await model.signOut() }
      } label: {
        Label("Logg ut", systemImage: "rectangle.portrait.and.arrow.right")
          .font(.subheadline.weight(.medium)).foregroundStyle(Studio.muted)
          .frame(maxWidth: .infinity, minHeight: 44)
      }.buttonStyle(.plain).disabled(model.isBusy)
    }
  }

  private var footer: some View {
    HStack {
      Text("SWIFTAUTH").font(.system(size: 10, weight: .medium, design: .monospaced)).tracking(2)
      Spacer()
      Text("En enklere vei inn.").font(.system(size: 11))
    }
    .foregroundStyle(Studio.muted.opacity(0.75))
    .padding(.top, 12)
    .overlay(alignment: .top) { Rectangle().fill(Studio.ink.opacity(0.08)).frame(height: 1) }
  }

  private var settings: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 24) {
          Text("Bak kulissene.").font(.system(size: 32, weight: .semibold, design: .rounded))
          Text("Tilkobling og detaljer for testmiljøet ditt.").foregroundStyle(Studio.muted)
          VStack(alignment: .leading, spacing: 18) {
            detail("STATUS", model.statusTitle)
            detail("BACKEND", model.draft.backendURL.isEmpty ? "Ikke satt" : model.draft.backendURL)
            detail("APP-ID", model.draft.applicationID)
            detail(
              "GITHUB CLIENT ID",
              model.draft.githubClientID.isEmpty ? "Ikke satt" : model.draft.githubClientID)
            if !model.draft.expectedLogin.isEmpty {
              detail("FORVENTET BRUKER", model.draft.expectedLogin)
            }
            if let user = model.user {
              detail("BRUKER-ID", user.subject)
              if let id = user.githubID { detail("GITHUB-ID", id) }
            }
          }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
            .background(Studio.surface, in: RoundedRectangle(cornerRadius: 24))
          if model.configuration != nil {
            Button {
              model.editConfiguration()
              showsSettings = false
            } label: {
              Label("Endre tilkobling", systemImage: "slider.horizontal.3").frame(
                maxWidth: .infinity)
            }.buttonStyle(StudioButtonStyle(prominent: true)).disabled(model.isBusy)
          }
        }.padding(26)
      }
      .background(Studio.background).foregroundStyle(Studio.ink)
      .navigationTitle("Innstillinger").navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Ferdig") { showsSettings = false }.tint(Studio.lime)
        }
      }
    }.preferredColorScheme(.dark)
  }

  private func detail(_ title: String, _ value: String) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      eyebrow(title)
      Text(value).font(.system(size: 13, design: .monospaced)).textSelection(.enabled)
    }
  }

  private func eyebrow(_ text: String) -> some View {
    Text(text).font(.system(size: 10, weight: .semibold, design: .monospaced))
      .tracking(1.5).foregroundStyle(Studio.muted)
  }
}

private struct ConfigurationCard: View {
  @Binding var draft: AuthSettings
  let save: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      field(
        "BACKEND-URL", placeholder: "https://api.example.com", value: $draft.backendURL, isURL: true
      )
      field("APP-ID", placeholder: "Appens identifikator", value: $draft.applicationID)
      field("GITHUB CLIENT ID", placeholder: "Offentlig client ID", value: $draft.githubClientID)
      field(
        "FORVENTET BRUKER · VALGFRITT", placeholder: "GitHub-brukernavn",
        value: $draft.expectedLogin)
      Text(
        "Offentlige innstillinger lagres på denne enheten. Leverandørhemmeligheter hører hjemme på serveren."
      )
      .font(.footnote).foregroundStyle(Studio.muted).lineSpacing(3)
      Button(action: save) {
        HStack {
          Text("Koble til")
          Spacer()
          Image(systemName: "arrow.right")
        }
      }.buttonStyle(StudioButtonStyle(prominent: true)).disabled(!draft.isComplete)
    }
    .padding(22).background(Studio.surface, in: RoundedRectangle(cornerRadius: 28))
    .overlay(RoundedRectangle(cornerRadius: 28).stroke(Studio.ink.opacity(0.10)))
  }

  private func field(
    _ title: String, placeholder: String, value: Binding<String>, isURL: Bool = false
  ) -> some View {
    VStack(alignment: .leading, spacing: 9) {
      Text(title).font(.system(size: 10, weight: .medium, design: .monospaced))
        .tracking(1).foregroundStyle(Studio.muted)
      TextField(placeholder, text: value)
        .font(.system(size: 15)).textInputAutocapitalization(.never).autocorrectionDisabled()
        .keyboardType(isURL ? .URL : .default).padding(14)
        .background(Studio.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Studio.ink.opacity(0.12)))
    }
  }
}

private struct StudioButtonStyle: ButtonStyle {
  var prominent: Bool
  @Environment(\.isEnabled) private var isEnabled
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func makeBody(configuration: Configuration) -> some View {
    configuration.label.font(.system(size: 16, weight: .semibold))
      .foregroundStyle(prominent ? Studio.background : Studio.ink)
      .padding(.horizontal, 22).padding(.vertical, 19)
      .background(prominent ? Studio.lime : Studio.surface, in: RoundedRectangle(cornerRadius: 18))
      .overlay(
        RoundedRectangle(cornerRadius: 18).stroke(prominent ? .clear : Studio.ink.opacity(0.15))
      )
      .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.45)
      .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
      .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: configuration.isPressed)
  }
}

private struct IdentityArtwork: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var appeared = false

  var body: some View {
    GeometryReader { geometry in
      let width = min(geometry.size.width, 360)
      ZStack {
        Circle().fill(Studio.lime.opacity(0.10)).frame(width: 170, height: 170).blur(radius: 40)
        Ellipse().stroke(Studio.ink.opacity(0.12), lineWidth: 1)
          .frame(width: width, height: 150).rotationEffect(.degrees(-28))
        Ellipse().stroke(Studio.lavender.opacity(0.5), lineWidth: 1)
          .frame(width: width, height: 150).rotationEffect(.degrees(28))
        Circle().stroke(Studio.ink.opacity(0.06), lineWidth: 1).frame(width: 208, height: 208)
        RoundedRectangle(cornerRadius: 34)
          .fill(
            LinearGradient(
              colors: [Studio.lime, Color(red: 0.45, green: 0.65, blue: 0.19)],
              startPoint: .topLeading, endPoint: .bottomTrailing)
          )
          .frame(width: 124, height: 142).rotationEffect(.degrees(-12))
          .shadow(color: Studio.lime.opacity(0.14), radius: 24, x: 0, y: 12)
          .overlay {
            Image(systemName: "key.horizontal").font(.system(size: 49, weight: .light))
              .foregroundStyle(Studio.background).rotationEffect(.degrees(-42))
          }
        Circle().fill(Studio.lavender).frame(width: 12, height: 12)
          .offset(x: -width * 0.38, y: -48)
        Circle().fill(Studio.lime).frame(width: 8, height: 8)
          .offset(x: width * 0.38, y: 48)
        Text("YOU").font(.system(size: 9, weight: .medium, design: .monospaced)).tracking(2)
          .foregroundStyle(Studio.muted).offset(x: width * 0.33, y: -70)
        Image(systemName: "plus").font(.system(size: 12, weight: .ultraLight))
          .foregroundStyle(Studio.muted).offset(x: -width * 0.34, y: 70)
      }.frame(maxWidth: .infinity, maxHeight: .infinity)
        .scaleEffect(appeared || reduceMotion ? 1 : 0.9)
        .opacity(appeared || reduceMotion ? 1 : 0)
        .onAppear {
          withAnimation(reduceMotion ? nil : .spring(duration: 0.7, bounce: 0.15)) {
            appeared = true
          }
        }
    }
  }
}

private struct GitHubMark: Shape {
  func path(in rect: CGRect) -> Path {
    // GitHub's familiar silhouette, drawn locally so the sign-in button needs no network image.
    var path = Path()
    let transform = CGAffineTransform(scaleX: rect.width / 24, y: rect.height / 24)
    path.move(to: CGPoint(x: 12, y: 0))
    path.addCurve(
      to: CGPoint(x: 8.2, y: 23.4), control1: CGPoint(x: -2, y: 0),
      control2: CGPoint(x: -4, y: 19.2))
    path.addLine(to: CGPoint(x: 8.2, y: 20))
    path.addCurve(
      to: CGPoint(x: 4.3, y: 18), control1: CGPoint(x: 5, y: 21), control2: CGPoint(x: 5, y: 18))
    path.addCurve(
      to: CGPoint(x: 8.2, y: 18.5), control1: CGPoint(x: 2, y: 16), control2: CGPoint(x: 6, y: 17))
    path.addLine(to: CGPoint(x: 9, y: 16.8))
    path.addCurve(
      to: CGPoint(x: 6.5, y: 7), control1: CGPoint(x: 3, y: 16), control2: CGPoint(x: 3, y: 10))
    path.addCurve(
      to: CGPoint(x: 7, y: 3.8), control1: CGPoint(x: 6, y: 5), control2: CGPoint(x: 6.5, y: 4))
    path.addLine(to: CGPoint(x: 10, y: 5.4))
    path.addQuadCurve(to: CGPoint(x: 14, y: 5.4), control: CGPoint(x: 12, y: 4.8))
    path.addLine(to: CGPoint(x: 17, y: 3.8))
    path.addCurve(
      to: CGPoint(x: 17.5, y: 7), control1: CGPoint(x: 17.5, y: 4), control2: CGPoint(x: 18, y: 5))
    path.addCurve(
      to: CGPoint(x: 15, y: 16.8), control1: CGPoint(x: 21, y: 10), control2: CGPoint(x: 21, y: 16))
    path.addQuadCurve(to: CGPoint(x: 15.8, y: 20), control: CGPoint(x: 16, y: 18))
    path.addLine(to: CGPoint(x: 15.8, y: 23.4))
    path.addCurve(
      to: CGPoint(x: 12, y: 0), control1: CGPoint(x: 28, y: 19.2), control2: CGPoint(x: 26, y: 0))
    path.closeSubpath()
    return path.applying(transform)
  }
}

#Preview { ContentView().environment(AuthAppModel()) }
