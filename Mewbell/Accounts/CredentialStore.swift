/// アカウントのトークンをメモリにだけ持つ。トークンを保持するのはこの actor だけにする。
actor CredentialStore {
    private var tokens: [AccountID: AccessToken] = [:]
    /// `close()` の後は、トークンを受け取らない（終了処理中に走っていた取得が書き戻さないように）
    private var isClosed = false

    func token(for id: AccountID) -> AccessToken? {
        tokens[id]
    }

    func set(_ token: AccessToken, for id: AccountID) {
        guard !isClosed else { return }
        tokens[id] = token
    }

    /// `ids` に含まれないアカウントのトークンを捨て、トークンが残っているアカウントを返す。
    @discardableResult
    func retainOnly(_ ids: Set<AccountID>) -> Set<AccountID> {
        tokens = tokens.filter { ids.contains($0.key) }
        return Set(tokens.keys)
    }

    func remove(_ id: AccountID) {
        tokens[id] = nil
    }

    func removeAll() {
        tokens.removeAll()
    }

    /// トークンをすべて捨て、以後は受け取らない（アプリの終了時）。
    func close() {
        isClosed = true
        tokens.removeAll()
    }
}
