/// ポーラーがアカウントのトークンを受け取る口。トークンを持つのは `CredentialStore` だけで、ポーラーは取得の間だけ使う。
protocol TokenProviding: Sendable {
    /// メモリに持っているトークン。
    func currentToken(for id: AccountID) async -> AccessToken?
    /// トークンを捨てて gh から取り直す。取れなければ nil。
    func refreshToken(for id: AccountID) async -> AccessToken?
    /// トークンを捨てる（取り直しても 401 だったとき）。
    func discardToken(for id: AccountID) async
}

struct LiveTokenProvider: TokenProviding {
    let credentials: CredentialStore
    let discovery: any AccountDiscovering

    func currentToken(for id: AccountID) async -> AccessToken? {
        await credentials.token(for: id)
    }

    func refreshToken(for id: AccountID) async -> AccessToken? {
        await discovery.refreshToken(for: id)
    }

    func discardToken(for id: AccountID) async {
        await credentials.remove(id)
    }
}
