# Changelog

## [0.2.0](https://github.com/yshrsmz/mewbell/compare/v0.1.0...v0.2.0) (2026-10-13)


### Features

* collapse accounts and repositories in the list and show issue numbers (update-notification-list) ([#20](https://github.com/yshrsmz/mewbell/issues/20)) ([72b6813](https://github.com/yshrsmz/mewbell/commit/72b68130eafb489b9ebe2f52a6a86d80c9fdaba1))
* make the popover text larger and easier to read (update-list-readability) ([#23](https://github.com/yshrsmz/mewbell/issues/23)) ([a2955b2](https://github.com/yshrsmz/mewbell/commit/a2955b24920fc469d144b0c4469b75a882e734d3))
* open the web notifications page from the account header (add-web-notifications-link) ([#22](https://github.com/yshrsmz/mewbell/issues/22)) ([0d07b56](https://github.com/yshrsmz/mewbell/commit/0d07b56ca758e598315a109e049262292e125106))
* show what happened on each thread and its state (add-thread-latest-event) ([#24](https://github.com/yshrsmz/mewbell/issues/24)) ([232e7ed](https://github.com/yshrsmz/mewbell/commit/232e7ed0542b1b03cb571a37b1451fe53c9708dd))


### Bug Fixes

* drop the stale pnpm self-record from pnpm-lock.yaml ([#29](https://github.com/yshrsmz/mewbell/issues/29)) ([9f15cb7](https://github.com/yshrsmz/mewbell/commit/9f15cb7d57b77fe0148b9a3fa9c462e20b808eab))
* fade the row title under the hover buttons ([#21](https://github.com/yshrsmz/mewbell/issues/21)) ([4c30efa](https://github.com/yshrsmz/mewbell/commit/4c30efa0854db07a20a590b6475ace1748ac3729))
* keep the row's hover buttons at the first title line ([#15](https://github.com/yshrsmz/mewbell/issues/15)) ([84079e8](https://github.com/yshrsmz/mewbell/commit/84079e88c8d36dcd3e3065720c8a72653aeaf9b1))
* widen the icon column to 24pt so thread icons are not clipped (fix-thread-icon-column) ([#26](https://github.com/yshrsmz/mewbell/issues/26)) ([8f1a1e9](https://github.com/yshrsmz/mewbell/commit/8f1a1e9305db64a777b3ebc6e39ed28913f37c9d))

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
