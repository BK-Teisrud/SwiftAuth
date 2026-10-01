import Foundation

/// Session coordinator. Interactive login is explicit; API credentials never open a browser.
public actor AuthClient {
  private let configuration: AuthConfiguration
  private let service: any AuthOIDCAdapter
  private let storage: any SessionStorage
  private let now: @Sendable () -> Date
  private var session = SessionContext()
  private var issuedTokens: Set<String> = []
  private var generation: UInt64 = 0
  private var loginID: UUID?
  private var refreshTask: (id: UUID, task: Task<AuthTokenResponse, Error>)?
  private var refreshMayHaveSent = false
  private var browserStopsInFlight = 0
  private var browserStopping: Bool { browserStopsInFlight > 0 }
  private var lease: SessionLease?
  private var deletionPending = false
  private var observers: [UUID: AsyncStream<AuthState>.Continuation] = [:]
  /// Latest token-free session state. Read with `await` outside the actor or subscribe with ``states()``.
  public private(set) var state: AuthState = .restoring

  /// Creates the standard client with ``NativeOIDCAdapter`` and an exclusive lock for the storage identity.
  ///
  /// Construction does not read Keychain; call ``restoreSession()`` explicitly.
  /// - Throws: Configuration, storage, or `sessionAlreadyInUse` errors.
  public init(configuration: AuthConfiguration, browser: any AuthBrowserSession) async throws {
    self.configuration = configuration
    self.service = await NativeOIDCAdapter(configuration: configuration, browser: browser)
    self.lease = try SessionLease.acquire(configuration.storageService)
    self.storage = KeychainSessionStorage(service: configuration.storageService)
    self.now = { Date() }
  }

  /// Creates a client with a trusted adapter and an exclusive storage lock based on the adapter's immutable configuration.
  ///
  /// The adapter must return verified OIDC output or trusted backend-issued application sessions. See <doc:ProvidersAndExtensions>.
  /// - Throws: Storage errors or `AuthError.sessionAlreadyInUse`.
  public init(adapter: any AuthOIDCAdapter) async throws {
    let configuration = await adapter.configuration
    self.configuration = configuration
    self.service = adapter
    self.lease = try SessionLease.acquire(configuration.storageService)
    self.storage = KeychainSessionStorage(service: configuration.storageService)
    self.now = { Date() }
  }

  init(
    configuration: AuthConfiguration, service: any AuthOIDCAdapter, storage: any SessionStorage,
    now: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.configuration = configuration
    self.service = service
    self.storage = storage
    self.now = now
  }

  /// Subscribes to state changes and immediately emits the current state.
  ///
  /// Only the latest value is buffered for slow consumers. Cancel the subscription task when observation is no longer needed.
  /// - Returns: A stream containing no tokens or network operations.
  public func states() -> AsyncStream<AuthState> {
    let id = UUID()
    let (stream, continuation) = AsyncStream<AuthState>.makeStream(
      bufferingPolicy: .bufferingNewest(1))
    observers[id] = continuation
    continuation.yield(state)
    continuation.onTermination = { [weak self] _ in Task { await self?.removeObserver(id) } }
    return stream
  }
  private func removeObserver(_ id: UUID) { observers[id] = nil }
  private func publish(_ value: AuthState) {
    state = value
    for continuation in observers.values { continuation.yield(value) }
  }

  /// Restores identity, refresh token, and quarantine state from local storage without network access.
  ///
  /// Completes any previous logout marker before reading. Restore creates a new session identity; create a new API client.
  /// - Throws: Storage failure, a conflicting operation, or incomplete earlier logout. See <doc:SessionLifecycle>.
  public func restoreSession() throws {
    guard loginID == nil, !browserStopping, refreshTask == nil else {
      throw AuthError.operationInvalidated
    }
    guard !deletionPending else { throw AuthError.storage }
    generation &+= 1
    session = SessionContext()
    issuedTokens.removeAll()
    publish(.restoring)
    do {
      if try storage.hasPendingLogout() {
        try storage.remove()
        try storage.clearPendingLogout()
        deletionPending = false
      }
      let loaded = try storage.load()
      guard loaded == nil || loaded?.version == 1,
        loaded == nil || loaded?.identity.issuer == configuration.issuer.absoluteString,
        loaded == nil || loaded?.identity.subject.isEmpty == false,
        loaded == nil || loaded?.refreshToken.isEmpty == false
      else { throw AuthError.storage }
      session.stored = loaded
      session.refreshBlocked =
        loaded?.refreshRejected == true
        ? .refreshRejected : loaded?.refreshInFlight == true ? .refreshOutcomeUnknown : nil
      publish(session.state())
    } catch {
      let safe = error as? AuthError ?? .storage
      publish(.restoring)
      throw safe
    }
  }

  /// Starts explicit login with a configured choice; defaults to `.serviceSelection`.
  ///
  /// Persists the refresh token before publication. Success creates a new session identity; failure and cancellation preserve the correct prior state.
  /// - Throws: Adapter, storage, or `loginAlreadyInProgress` errors. Create a new credential provider and HTTPClient after success.
  public func login(choice: AuthLoginChoice = .serviceSelection) async throws {
    guard loginID == nil, !browserStopping else { throw AuthError.loginAlreadyInProgress }
    guard configuration.loginChoices.contains(choice) else {
      throw AuthError.unsupportedProviderFeature
    }
    guard !deletionPending, try !storage.hasPendingLogout() else { throw AuthError.storage }
    generation &+= 1
    let epoch = generation
    let id = UUID()
    loginID = id
    if refreshTask != nil && refreshMayHaveSent && session.refreshBlocked == nil {
      session.refreshBlocked = .refreshOutcomeUnknown
    }
    refreshTask?.task.cancel()
    refreshTask = nil
    publish(.signingIn)
    defer { if loginID == id { loginID = nil } }
    do {
      let tokens = try await withTaskCancellationHandler {
        try await service.login(choice: choice)
      } onCancel: {
        Task { await self.cancelLogin(operation: id) }
      }
      try Task.checkCancellation()
      guard generation == epoch, loginID == id else { throw AuthError.operationInvalidated }
      guard tokens.identity.issuer == configuration.issuer.absoluteString,
        !tokens.identity.subject.isEmpty,
        !tokens.accessToken.isEmpty, tokens.expiresAt > now()
      else { throw AuthError.tokenExchange }
      if let token = tokens.refreshToken, !token.isEmpty {
        let record = StoredSession(
          identity: tokens.identity, refreshToken: token, loginNonce: tokens.loginNonce,
          idTokenBinding: tokens.idTokenBinding)
        try storage.save(record)
        session.stored = record
      } else {
        try storage.remove()
        session.stored = nil
      }
      session.id = UUID()
      issuedTokens.removeAll()
      session.install(tokens, now: now())
      session.refreshBlocked = nil
      publish(.signedIn(tokens.identity))
    } catch {
      guard generation == epoch, loginID == id else { throw AuthError.operationInvalidated }
      let safe =
        error is CancellationError ? AuthError.cancelled : error as? AuthError ?? .tokenExchange
      publish(session.state(problem: safe))
      throw safe
    }
  }

  /// Cancels active interactive login and waits for adapter cancellation. Does nothing without an active login.
  ///
  /// State returns to the previous identity and any existing refresh quarantine.
  public func cancelLogin() async { if let id = loginID { await cancelLogin(operation: id) } }
  private func cancelLogin(operation: UUID) async {
    guard loginID == operation else { return }
    generation &+= 1
    loginID = nil
    publish(session.state())
    browserStopsInFlight += 1
    await service.cancelLogin()
    browserStopsInFlight -= 1
  }

  /// Returns a valid access token from memory or one shared refresh operation.
  ///
  /// Never opens the browser. Early refresh margin is at most 60 seconds and ten percent of token lifetime.
  /// Cancellation stops only this waiting consumer. Never log the return value.
  /// - Returns: A sensitive bearer token.
  /// - Throws: Session, refresh, storage, or cancellation errors; see <doc:SessionLifecycle>.
  public func validAccessToken() async throws -> String {
    try Task.checkCancellation()
    guard loginID == nil, !browserStopping else { throw AuthError.loginAlreadyInProgress }
    if let access = session.access, access.expiresAt > now(),
      now() < session.refreshAfter || session.stored == nil
    {
      return remember(access.accessToken)
    }
    if let blocked = session.refreshBlocked { throw blocked }
    guard let stored = session.stored else {
      session.refreshBlocked = .reauthenticationRequired
      publish(
        .reauthenticationRequired(session.access?.identity, reason: .reauthenticationRequired))
      throw AuthError.reauthenticationRequired
    }
    let current: (id: UUID, task: Task<AuthTokenResponse, Error>)
    if let existing = refreshTask {
      current = existing
    } else {
      let id = UUID()
      let epoch = generation
      refreshMayHaveSent = false
      let task = Task { try await self.refreshWithDeadline(stored, epoch: epoch, id: id) }
      current = (id, task)
      refreshTask = current
    }
    let epoch = generation
    let tokens = try await awaitShared(current.task)
    try Task.checkCancellation()
    guard generation == epoch, session.access?.identity == tokens.identity,
      session.access?.accessToken == tokens.accessToken, tokens.expiresAt > now(), loginID == nil
    else {
      throw AuthError.operationInvalidated
    }
    return remember(tokens.accessToken)
  }

  private func tokenFingerprint(_ token: String) -> String {
    OIDCEncoding.base64(OIDCEncoding.sha256(Data(token.utf8)))
  }
  private func remember(_ token: String) -> String {
    // Bound memory; very old delayed rejections fail closed instead of causing a refresh.
    if issuedTokens.count >= 256 { issuedTokens.removeAll() }
    issuedTokens.insert(tokenFingerprint(token))
    return token
  }

  /// A provider is bound to the first successful credential acquisition, never another login session.
  func credential(expectedSession: UUID?) async throws -> (UUID, String) {
    let id = session.id
    guard expectedSession == nil || expectedSession == id else {
      throw AuthError.operationInvalidated
    }
    let token = try await validAccessToken()
    guard session.id == id else { throw AuthError.operationInvalidated }
    return (id, token)
  }
  func recover(rejectedToken: String, expectedSession: UUID) async throws -> String {
    guard session.id == expectedSession else { throw AuthError.operationInvalidated }
    let token = try await recover(rejectedToken: rejectedToken)
    guard session.id == expectedSession else { throw AuthError.operationInvalidated }
    return token
  }

  private func refreshWithDeadline(_ record: StoredSession, epoch: UInt64, id: UUID) async throws
    -> AuthTokenResponse
  {
    let gate = AsyncResultGate<AuthTokenResponse>()
    let worker = Task {
      try await self.performRefresh(record, epoch: epoch, id: id, completion: gate)
    }
    let timer = Task {
      do { try await Task.sleep(for: .seconds(configuration.refreshTimeout)) } catch { return }
      worker.cancel()
      gate.finish(.failure(AuthError.networkUnavailable))
    }
    defer {
      timer.cancel()
      if refreshTask?.id == id { refreshTask = nil }
    }
    do {
      return try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { continuation in
          gate.install(continuation)
          Task { gate.finish(await worker.result) }
        }
      } onCancel: {
        worker.cancel()
        gate.finish(.failure(AuthError.operationInvalidated))
      }
    } catch {
      guard generation == epoch else { throw AuthError.operationInvalidated }
      if refreshMayHaveSent {
        session.access = nil
        session.refreshBlocked =
          error as? AuthError == .networkUnavailable
          ? .refreshOutcomeUnknown : error as? AuthError ?? .refreshOutcomeUnknown
        publish(session.state())
        throw session.refreshBlocked!
      }
      publish(session.state(problem: error as? AuthError ?? .networkUnavailable))
      throw error
    }
  }

  private func performRefresh(
    _ record: StoredSession, epoch: UInt64, id: UUID, completion: AsyncResultGate<AuthTokenResponse>
  ) async throws
    -> AuthTokenResponse
  {
    var mayHaveSent = false
    do {
      guard generation == epoch, refreshTask?.id == id else { throw AuthError.operationInvalidated }
      try await service.prepareRefresh()
      guard generation == epoch, refreshTask?.id == id else { throw AuthError.operationInvalidated }
      try Task.checkCancellation()
      // Durable quarantine BEFORE network send also covers app termination with an unknown rotating-token outcome.
      try storage.save(
        StoredSession(
          identity: record.identity, refreshToken: record.refreshToken, refreshInFlight: true,
          loginNonce: record.loginNonce, idTokenBinding: record.idTokenBinding))
      mayHaveSent = true
      refreshMayHaveSent = true
      let result = try await service.refresh(
        token: record.refreshToken, identity: record.identity, nonce: record.loginNonce,
        binding: record.idTokenBinding)
      try Task.checkCancellation()
      guard generation == epoch, refreshTask?.id == id else { throw AuthError.operationInvalidated }
      guard result.identity == record.identity, !result.accessToken.isEmpty,
        result.expiresAt > now()
      else {
        throw AuthError.idTokenValidation
      }
      let replacement = StoredSession(
        identity: record.identity, refreshToken: result.refreshToken ?? record.refreshToken,
        loginNonce: record.loginNonce, idTokenBinding: record.idTokenBinding)
      guard !replacement.refreshToken.isEmpty else { throw AuthError.refreshRejected }
      do { try storage.save(replacement) } catch {
        // Never reuse the old persisted rotating credential after a successful response whose commit failed.
        session.stored = replacement
        session.access = nil
        session.refreshBlocked = error as? AuthError ?? .storage
        publish(.reauthenticationRequired(record.identity, reason: session.refreshBlocked!))
        throw session.refreshBlocked!
      }
      session.stored = replacement
      session.install(result, now: now())
      refreshMayHaveSent = false
      // Commit and publish the terminal result in the same actor turn as persistence.
      completion.finish(.success(result))
      publish(session.state())
      return result
    } catch {
      guard generation == epoch, refreshTask?.id == id else { throw AuthError.operationInvalidated }
      let safe = error as? AuthError ?? (mayHaveSent ? .refreshOutcomeUnknown : .networkUnavailable)
      if !mayHaveSent {
        publish(session.state(problem: safe))
        throw safe
      }
      if safe == .refreshRejected {
        try? storage.save(
          StoredSession(
            identity: record.identity, refreshToken: record.refreshToken, refreshInFlight: true,
            refreshRejected: true, loginNonce: record.loginNonce,
            idTokenBinding: record.idTokenBinding))
      }
      session.refreshBlocked = safe
      session.access = nil
      publish(session.state())
      throw safe
    }
  }

  /// Handles rejection of a token previously issued by this session.
  ///
  /// An already replaced token reuses the current token without another rotation. Unknown token fingerprints are rejected.
  /// Use ``AuthCredentialProvider`` to bind attempts to the same session across account changes.
  /// - Returns: The current or refreshed sensitive access token.
  /// - Throws: `operationInvalidated` or a token-acquisition error.
  public func recover(rejectedToken: String) async throws -> String {
    guard issuedTokens.contains(tokenFingerprint(rejectedToken)) else {
      throw AuthError.operationInvalidated
    }
    if let access = session.access, access.accessToken != rejectedToken {
      return try await validAccessToken()
    }
    session.access = nil
    return try await validAccessToken()
  }

  /// Clears memory, invalidates operations, and deletes the local session using a durable logout marker.
  ///
  /// Performs no network logout. Memory remains cleared after deletion failure; retry local logout before restore.
  /// - Throws: Keychain or storage errors, or `logoutPersistenceUnavailable` when both marker persistence and deletion fail.
  public func logout() async throws {
    generation &+= 1
    loginID = nil
    refreshTask?.task.cancel()
    refreshTask = nil
    session = SessionContext()
    issuedTokens.removeAll()
    let failure: AuthError?
    // Attempt credential deletion even if marker storage is unavailable.
    var markerFailed = false
    do { try storage.markLogoutPending() } catch { markerFailed = true }
    do {
      try storage.remove()
      try storage.clearPendingLogout()
      deletionPending = false
      failure = nil
    } catch {
      deletionPending = true
      failure = markerFailed ? .logoutPersistenceUnavailable : error as? AuthError ?? .storage
    }
    browserStopsInFlight += 1
    publish(.signedOut(problem: failure))
    await service.cancelLogin()
    browserStopsInFlight -= 1
    if let failure { throw failure }
  }

  /// Opens separate provider logout in the system browser without deleting the local session.
  ///
  /// Call ``logout()`` afterward even if provider logout fails. An ID-token hint exists only in adapter memory.
  /// - Throws: Adapter errors, `loginAlreadyInProgress`, or `unsupportedProviderFeature`.
  public func logoutAtProvider() async throws {
    guard loginID == nil, !browserStopping else { throw AuthError.loginAlreadyInProgress }
    do { try await service.logoutAtProvider() } catch {
      throw error as? AuthError ?? .providerRejected
    }
  }
}
