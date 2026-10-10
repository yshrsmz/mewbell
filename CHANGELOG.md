# Changelog

## 0.1.0 (2026-10-10)


### Features

* add menu bar app skeleton (add-project-skeleton) ([#1](https://github.com/yshrsmz/mewbell/issues/1)) ([b9b5511](https://github.com/yshrsmz/mewbell/commit/b9b55110f2dba4ade23c9d36b4de6fce5a118a40))
* add the Diagnostics tab and show failed actions and the 500-item cap (add-diagnostics) ([#11](https://github.com/yshrsmz/mewbell/issues/11)) ([8e4ba73](https://github.com/yshrsmz/mewbell/commit/8e4ba73b59df69c115897b37a62deeed9a0877e7))
* add the Settings window with per-account options and gh overrides (add-settings) ([#10](https://github.com/yshrsmz/mewbell/issues/10)) ([06e4368](https://github.com/yshrsmz/mewbell/commit/06e43688583f1bf392935ff4c0529a69bd3a3a4f))
* automate releases with release-please, attested artifacts, and a Homebrew Cask (add-distribution) ([#12](https://github.com/yshrsmz/mewbell/issues/12)) ([f449456](https://github.com/yshrsmz/mewbell/commit/f4494562ede20fbe3660140ca1bd6c07e843aed3))
* discover gh accounts and show them in the menu bar (add-gh-account-discovery) ([#2](https://github.com/yshrsmz/mewbell/issues/2)) ([0eec1f9](https://github.com/yshrsmz/mewbell/commit/0eec1f9cac00600b8e611eb13bf8846695264f23))
* fetch immediately when reload is pressed and show the progress (update-reload-fetch-now) ([#8](https://github.com/yshrsmz/mewbell/issues/8)) ([d42379f](https://github.com/yshrsmz/mewbell/commit/d42379fa057d4ad418c3326735d60f99b0b615f2))
* fetch notifications per account and list them in the popover (add-notification-fetch) ([#3](https://github.com/yshrsmz/mewbell/issues/3)) ([29ac5f9](https://github.com/yshrsmz/mewbell/commit/29ac5f9e3f31c0ee372ba5023a1cbfe1701b8e7b))
* keep the cat icon next to the unread count and tint it green (update-menu-bar-badge) ([#9](https://github.com/yshrsmz/mewbell/issues/9)) ([fbc8d3e](https://github.com/yshrsmz/mewbell/commit/fbc8d3e5fa80cbf02352b53cf5db5bf84b83803c))
* mark threads read or done and mark all as read from the list (add-thread-actions) ([#7](https://github.com/yshrsmz/mewbell/issues/7)) ([75febde](https://github.com/yshrsmz/mewbell/commit/75febded901a61f6bf7e6306a07ad35036f8aae0))
* notify new threads in macOS and mark opened threads as read (add-system-notifications) ([#5](https://github.com/yshrsmz/mewbell/issues/5)) ([702655c](https://github.com/yshrsmz/mewbell/commit/702655c6f70b825de7bd24d95b137043e1343c08))


### Bug Fixes

* refetch notifications without If-Modified-Since periodically (fix-stale-notification-list) ([#4](https://github.com/yshrsmz/mewbell/issues/4)) ([cf81731](https://github.com/yshrsmz/mewbell/commit/cf8173170e0409cbf39c3e07f235f5f90c161696))
