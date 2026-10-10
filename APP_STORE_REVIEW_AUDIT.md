# Nestic App Store review audit

Reviewed October 5, 2026. This is a source/configuration audit and local verification, not a guarantee of App Review approval. Changes are local; no production deployment or App Store Connect submission was performed.

## Findings corrected

| Area | Review risk and correction |
| --- | --- |
| Privacy/support links | The live `/privacy` and `/support` routes returned the SPA instead of the legal pages. The website image now includes the real pages and nginx serves them explicitly. Deploy the updated website before submission. |
| Readable legal pages and signup agreement | Extensionless legal routes explicitly return HTML with inline disposition. Added a service-terms page and legal index, separate from Apple's app license. New email/Apple accounts require agreement on both clients; the server stores version `2026-10-05` and its own acceptance timestamp. Existing logins are unchanged, and historical consent is not fabricated. Deploy the website, migrate the server with `AddTermsAcceptance`, and release the updated iOS client together. |
| Privacy manifests | Added required-reason UserDefaults declarations for the iPhone app, watch app and widget, including the shared App Group reason where used. Verified all three manifests in the archive. These do not replace App Store Connect privacy labels. |
| Subscription disclosures | Added Terms, Privacy and subscription-management links; show StoreKit’s localized price and billing period; removed unconditional Family Sharing claims and clearly distinguish free tracker logging from Pro routines. Added unavailable-product retry, pending-purchase messaging and restore feedback. Verified transaction updates are finished. |
| Account deletion | Deletion now removes the user's authored entries and health updates even in surviving shared nests. Associated photos are recorded in a durable deletion queue, retried after storage failures. Remaining members' records survive and ownership transfers. Local health-photo caches and account prediction/quiet-hour/reminder preferences are cleared. |
| Sign in with Apple deletion | Added reauthentication and server-side Apple authorization revocation using a fresh authorization code. A deletion is still fulfilled if revocation cannot complete, with instructions to manually disconnect Apple access. Production Apple credentials still need configuration and a real-account test. |
| Subscription cancellation | Account deletion explains that Apple billing must be cancelled separately and provides the Apple subscription-management link. |
| Shared-content safety | Added a dedicated safety-report category that reaches the support/admin inbox, owner removal of other members, caregiver-link revocation when access is removed, and an immediate “Leave this nest” action for non-owners. Nestic is private and invitation-only: there is no public profile, discovery, feed, or direct-message surface. |
| Administrative identity | Admin access now requires a verified allowlisted email. Apple account creation uses the signed Apple token's email rather than trusting a client-supplied email. |
| Camera | Added permission handling, unavailable-camera feedback and a Settings route after denial. The existing system photo picker only grants access to selected photos; a full photo-library permission is not requested. |
| Health/forecasts | Added visible reminders that care forecasts are estimates, and report text is user-recorded history, not a diagnosis or treatment recommendation. |
| Archive packaging | Matched watch/phone/widget build numbers and set the widget to skip separate archive installation. Checked app/watch icon dimensions and opacity. The archive contains one main app with nested watch and widget bundles. |
| Interaction completeness | Feedback now opens in a navigation stack so users can read and reply to conversations. Quick-log menu uses native text rows instead of custom labels that were not exposed correctly by the context menu. Tracker lookup now uses the current subject pins rather than a stale passed-in value. |

## Required before submission

1. **Deploy server and website changes.** Run the server migrations, including `CreatePhotoDeletionJobs`. Confirm the new account-deletion response and photo cleanup worker are live. Confirm production `/privacy` and `/support` display their actual documents, not merely HTTP 200. The local website image serves both correctly.
2. **Configure Apple authorization revocation.** Set `APPLE_TEAM_ID`, `APPLE_KEY_ID` and `APPLE_PRIVATE_KEY` on the server, using the appropriate Sign in with Apple `.p8` key. Keep secrets out of source control. Confirm `APPLE_CLIENT_IDS` matches the app's identity configuration. Exercise deletion with a disposable real Apple-linked account, including cancellation and service failure. Source-level compilation is not a live Apple test.
3. **Finish the subscription in App Store Connect.** Product ID: `com.nestic.predictions.monthly`. Configure the subscription group, duration, price, localization, review screenshot, agreements/tax/banking and submission attachment. Enable Family Sharing only if intended. Test purchase, restore, pending approval, renewal, expiration and revocation using sandbox/TestFlight. Keep the product available to review; a disabled purchase button with an unavailable-product error is not a completed paid flow.
4. **Complete App Privacy disclosures.** Based on current server data, review name, email, user ID, photos/video, other user content, customer support and optional health information. These are linked to the account and used for app functionality. Human health data and pet-care content may need different category treatment. Entitlement checks alone do not mean payment-card data is collected; confirm whether any purchase history is transmitted or retained. There is no advertising/tracking SDK identified in this source audit. Verify declarations against actual server/provider logging and any future SDKs.
5. **Give reviewers reliable access.** Confirm the previously requested `test@test.com` account can sign in against production, without email verification or inaccessible MFA blocking review, and has representative subjects, trackers, routines, an open health event, photos and history. Enter its password securely in App Store Connect, not this file. Explain paid features and the gated administrative dashboard in review notes; do not disclose a personal admin credential. Keep the backend running during review.
6. **Check support operations.** Confirm the admin feedback inbox is monitored and support requests and in-app safety reports receive timely responses. A report button alone is not moderation. Ensure provider/backups retention statements and administrator access in the published privacy policy match operational practice.
7. **Physical-device acceptance pass.** Use the signed Release/TestFlight build on iPhone, iPad and the supported physical watch. Check first launch, Apple/email authentication, offline recovery, Watch installation/sync/routines, camera denial, photo upload/progress notes, export/share-sheet anchoring on iPad, caregiver expiry/revocation, account deletion and sandbox IAP. Local tests cannot validate these hardware or external-service paths completely.
8. **Finish listing metadata.** Use accurate iPhone/iPad screenshots and feature descriptions, an appropriate age rating, real support/privacy URLs, Terms link in metadata and subscription disclosures. Nestic is not currently designed as a Kids Category product or a clinical/diagnostic service. Do not make medical reliability claims or describe forecast confidence as a clinically validated probability.

## Remaining policy judgment / risk

- **User-generated content, guideline 1.2:** Nestic is private, invitation-only collaboration, not a public social feed. It has a safety-report path, an administrator response workflow, owner removal, caregiver-link revocation, and an immediate escape route for a non-owner. Review should be told this private model explicitly. There is deliberately no public-community discovery or automated moderation feed; support operations must still respond promptly to safety reports.
- **Credential logging:** WebSocket query-token fallback and caregiver bearer links can put credentials in request URLs and diagnostics. Restrict/redact production logs and prefer header authentication for native sockets. Never send token-bearing diagnostic URLs to review/support. No production log configuration was changed in this audit.
- **External features:** Production R2 object deletion, real Apple revocation, StoreKit payments, monitored support and reviewer credentials have not been exercised live in this audit. Do not submit assuming successful local compilation verifies them.

## Verification

- Release iOS distribution archive builds without signing and has the expected main/watch/widget structure. This does not verify provisioning, distribution signing or App Store server validation.
- All 12 server tests pass against an isolated PostgreSQL instance, including signup terms enforcement/persistence, verified-admin identity, deletion of authored shared events/progress photos and ownership transfer. Photo deletion is queued in tests because live R2 is deliberately not configured.
- All 28 existing iOS unit/UI regression tests pass on the iPhone simulator. The additional dedicated signup agreement UI test also passes, verifying the agreement starts unchecked and enables/disables account creation without submitting a production account.
- The local nginx deployment image returns the actual privacy and support documents; production remains unchanged.

## Review-note starting point

Nestic is a private, invitation-only care journal. The review account contains sample care history. Open Home and select a subject to switch between Record and Insights, record a tracker, update an open health event, and view/share its report. Activity shows shared history. Your nest contains members, preferences, feedback, subscription controls and account deletion. Nestic Pro is an auto-renewable in-app subscription for forecasts, additional nests and temporary caregiver access. The watch companion requires the iPhone app/account configuration and supports quick records and routines. Restricted administration is available only to authorized support staff and is not an ordinary consumer feature. Forecasts and reports are organizational aids, not medical diagnoses.

Adjust these notes to reflect the final tested build and actual subscription configuration.

## Apple references

- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/): 1.2, 2.1, 3.1.1, 3.1.2 and 5.1.1.
- [Auto-renewable subscriptions](https://developer.apple.com/app-store/subscriptions/): pricing, duration and legal disclosures.
- [Account deletion guidance](https://developer.apple.com/help/app-review/guideline-reference/5-1-1-account-deletion): deletion of shared user-generated content and Apple authorization.
- [TN3194: account deletion and Apple token revocation](https://developer.apple.com/documentation/technotes/tn3194-handling-account-deletions-and-revoking-tokens-for-sign-in-with-apple).
- [Required-reason API declarations](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api).
