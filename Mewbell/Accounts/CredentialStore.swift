/// アカウントのトークンをメモリにだけ持つ。トークンを保持するのはこの actor だけにする。
actor CredentialStore {
    private var tokens: [AccountID: AccessToken] = [:]

    func token(for id: AccountID) -> AccessToken? {
        tokens[id]
    }

    func contains(_ id: AccountID) -> Bool {
        tokens[id] != nil
    }

    func set(_ token: AccessToken, for id: AccountID) {
        tokens[id] = token
    }

    /// `ids` に含まれないアカウントのトークンを捨てる。
    func retainOnly(_ ids: Set<AccountID>) {
        tokens = tokens.filter { ids.contains($0.key) }
    }

    func removeAll() {
        tokens.removeAll()
    }
}
