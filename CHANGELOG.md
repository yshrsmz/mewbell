# Changelog

## [0.7.0](https://github.com/yshrsmz/mewbell/compare/v0.6.0...v0.7.0) (2026-10-19)


### Features

* add the app icon ([#80](https://github.com/yshrsmz/mewbell/issues/80)) ([9effbd7](https://github.com/yshrsmz/mewbell/commit/9effbd73e6113d3f599569cdcaab9de59484e683))

## [0.6.0](https://github.com/yshrsmz/mewbell/compare/v0.5.0...v0.6.0) (2026-10-17)


### Features

* add the menu bar icon context menu ([#70](https://github.com/yshrsmz/mewbell/issues/70)) ([134aea6](https://github.com/yshrsmz/mewbell/commit/134aea6238ab17c0ddf0f70eafc89811108de3f5))
* align the account heading actions with the repository heading and add mark all as done ([#66](https://github.com/yshrsmz/mewbell/issues/66)) ([ffaca97](https://github.com/yshrsmz/mewbell/commit/ffaca97cff070dd6a9fd941540111a40f13600ea))
* mark the app name and version of debug builds ([#71](https://github.com/yshrsmz/mewbell/issues/71)) ([26f25ad](https://github.com/yshrsmz/mewbell/commit/26f25ad12c5fc646230eae5dfffb86db8d656af5))
* space out batched thread actions by one second ([#69](https://github.com/yshrsmz/mewbell/issues/69)) ([8c339fe](https://github.com/yshrsmz/mewbell/commit/8c339fe0cef76ed92d7e046125c8e99c6fb40f33))
* use GitHub's state colors for thread icons ([#61](https://github.com/yshrsmz/mewbell/issues/61)) ([0e222c5](https://github.com/yshrsmz/mewbell/commit/0e222c52f1df65b1ee58f8f64cc6ab570c8d6643))


### Bug Fixes

* align the account heading text on one baseline ([#68](https://github.com/yshrsmz/mewbell/issues/68)) ([e2bf9a7](https://github.com/yshrsmz/mewbell/commit/e2bf9a721fc17131059b4a95882624709d1d7b40))
* keep the list width when the scroll bar appears ([#62](https://github.com/yshrsmz/mewbell/issues/62)) ([2d64cb0](https://github.com/yshrsmz/mewbell/commit/2d64cb03928348e81ee98d1138bb9a02a733c6d8))
* match the later-waiting run scenario to the approval run search ([#65](https://github.com/yshrsmz/mewbell/issues/65)) ([67423d8](https://github.com/yshrsmz/mewbell/commit/67423d8de83f4db7de39ec27b0fbc191be9c91dd))
* withdraw the notifications of threads removed together in one call ([#67](https://github.com/yshrsmz/mewbell/issues/67)) ([1177a22](https://github.com/yshrsmz/mewbell/commit/1177a22665d89446c5b2d53426170be92315e2be))

## [0.5.0](https://github.com/yshrsmz/mewbell/compare/v0.4.0...v0.5.0) (2026-10-15)


### Features

* mark a repository group as read or done ([#59](https://github.com/yshrsmz/mewbell/issues/59)) ([22d7cdf](https://github.com/yshrsmz/mewbell/commit/22d7cdfecc91784ae5af3b31e55bca6749de115b))


### Bug Fixes

* open the run of an already approved deployment request ([#53](https://github.com/yshrsmz/mewbell/issues/53)) ([93674aa](https://github.com/yshrsmz/mewbell/commit/93674aaf081841901cbc728203e83c8690363790))

## [0.4.0](https://github.com/yshrsmz/mewbell/compare/v0.3.0...v0.4.0) (2026-10-15)


### Features

* open individual Discussion and Release pages (update-thread-open-url) ([#47](https://github.com/yshrsmz/mewbell/issues/47)) ([35709a3](https://github.com/yshrsmz/mewbell/commit/35709a31bd98af5d53bd08e213e398a2ebb4575c))
* open the workflow run of Actions notifications (update-actions-open-url) ([#50](https://github.com/yshrsmz/mewbell/issues/50)) ([e065780](https://github.com/yshrsmz/mewbell/commit/e065780645b03071b091905b147a1b538fd4b2b4))


### Bug Fixes

* merge a conditional 200 into the notification list (fix-conditional-fetch-partial-list) ([#49](https://github.com/yshrsmz/mewbell/issues/49)) ([6dd714d](https://github.com/yshrsmz/mewbell/commit/6dd714da90c16dd7f7820c177a331521285680c8))
* treat secondary rate limit 403 as a rate limit for the list and actions (fix-secondary-rate-limit-403) ([#45](https://github.com/yshrsmz/mewbell/issues/45)) ([e3b5d7f](https://github.com/yshrsmz/mewbell/commit/e3b5d7fa00071abe63c7b7b63514eb2a0c3ab72a))

## [0.3.0](https://github.com/yshrsmz/mewbell/compare/v0.2.0...v0.3.0) (2026-10-14)


### Features

* add hover feedback to popover controls (update-popover-hover-feedback) ([#42](https://github.com/yshrsmz/mewbell/issues/42)) ([a0ff2f2](https://github.com/yshrsmz/mewbell/commit/a0ff2f264bb49399aad63779e81ea169d2bd9011))
* raise the popover heading hit target to 24pt (update-heading-hit-target) ([#43](https://github.com/yshrsmz/mewbell/issues/43)) ([1bda279](https://github.com/yshrsmz/mewbell/commit/1bda279197ba0333f59775cf9b03618778dfa471))


### Bug Fixes

* clear the A10 and A11 known deviations (fix-minor-principle-deviations) ([#40](https://github.com/yshrsmz/mewbell/issues/40)) ([6863b1d](https://github.com/yshrsmz/mewbell/commit/6863b1d4a25ba5aae9d30154e27fb54927ef1da7))
* keep tests from timing out on a slow release runner (fix-slow-runner-test-waits) ([#34](https://github.com/yshrsmz/mewbell/issues/34)) ([e7f1d7d](https://github.com/yshrsmz/mewbell/commit/e7f1d7da08592fc6fd84a436d2e76bde120a853e))
* make GitHubAPIClient.send private again (fix-api-client-send-privacy) ([#32](https://github.com/yshrsmz/mewbell/issues/32)) ([bb01e2c](https://github.com/yshrsmz/mewbell/commit/bb01e2cd7e3508aaee3d096b2a755f19bb67d7d4))
* name the token state icon for VoiceOver (fix-account-token-status-labels) ([#35](https://github.com/yshrsmz/mewbell/issues/35)) ([597a3f1](https://github.com/yshrsmz/mewbell/commit/597a3f1c907f6198ad9d793d9853b6293ba4ee6e))

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
