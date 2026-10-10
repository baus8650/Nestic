# Build 12 submission audit — October 9, 2026

## Outcome

App Store Connect now has version 1.0 (12) in the existing review draft, alongside the Nestic subscription and its subscription group. All three items show ready for review, and the draft offers Submit for Review without missing-field errors. The submission has **not** been sent to Apple.

There is one confirmed production configuration concern to resolve before submitting: Apple authorization revocation during account deletion is not configured. A successful App Store Connect completeness check does not verify this behavior or guarantee approval.

## Corrections made

- Replaced the draft's previous build 9 with build 12, preserving both subscription items.
- Expanded Pro subscription availability from 44 countries/regions to all 175, matching the user's worldwide launch instruction. Existing localized pricing was preserved.

## Verified in App Store Connect

- TestFlight identifies version 1.0 (12) as Validated, with non-exempt encryption set to No. It includes iPhone, iPad, and Apple Watch support.
- Subtitle: Keep track of your nest. Promotional text and description use that slogan and describe routines, habits, and everyday updates.
- Lifestyle category; age-rating questionnaire completed (13+ in most regions, with regional variations). Standard Apple license agreement selected; content rights answer present.
- App is free, with 175 available countries/regions. Pro is an optional monthly subscription, product ID `com.nestic.predictions.monthly`.
- Subscription and group both Ready for Review; English localization and subscription review screenshot present. Family Sharing is enabled. Subscription display name is Nestic Pro — Family.
- Review sign-in and contact fields filled. Notes accurately describe the free review account, sample nest, Pro subscription, Watch setup, private sharing, feedback, and account deletion.
- Four medium iPhone screenshots, four large iPhone screenshots, four iPad screenshots, and one Watch screenshot present. Phone and iPad home images show the slogan, Our Little Nest, Parker, and Penny. Watch image shows Parker and Penny. Header and search result creatives each present and use the slogan.
- Published privacy policy URL is correct. Published disclosures include linked Name, Email Address, User ID, Health, Photos or Videos, Other User Content, and Customer Support, for app functionality. No tracking disclosure shown.
- Free and Paid Apps Agreements active. Bank account and W-9 active. Digital Services Act compliance record active. Developer currently identifies as a non-trader for the app; this classification should reflect the developer's actual circumstances.
- Automatic release after approval remains selected.

## Live checks

- Review account successfully authenticated against the production service; email verified, manual Pro disabled, and Our Little Nest available. No account data was deleted or modified during this check.
- Public website, privacy, terms, and support URLs all returned HTTPS 200. The legal and support routes returned their actual documents rather than the app shell.
- StoreKit purchases are handled on device in current source; the server does not collect purchase history through a transaction endpoint. Current source includes purchase verification, restore, pending-purchase feedback, and entitlement updates. This is a source inspection, not a live purchase test.
- Current iPhone, Widget, and Watch source each include a privacy manifest and required UserDefaults reasons. Local archives found on this machine report build 3 in archive metadata, so they cannot establish the exact contents of uploaded build 12. Apple’s build 12 validation was inspected directly in TestFlight.

## Resolve before submission

The production server's variable inventory lacks `APPLE_TEAM_ID`, `APPLE_KEY_ID`, and `APPLE_PRIVATE_KEY`. `revokeAppleAuthorization` requires all three. Account deletion still removes the Nestic account and returns a manual-disconnection warning when revocation fails, but the normal automatic Apple revocation path cannot succeed with these settings absent.

Configure the correct Sign in with Apple key on the server, confirm the client ID configuration, and test deletion with a disposable Apple-linked account. Do not delete the App Review account. Keep the private key out of source control and audit output.

Apple's guidance: https://developer.apple.com/support/offering-account-deletion-in-your-app/

## Remaining verification limits

This audit did not perform an actual build 12 TestFlight subscription purchase/restore or a physical paired Watch recording/sync test. Those release checks should pass before submission, especially given the earlier Watch sync issue. App Store Connect metadata readiness does not establish their runtime behavior.

The review account remains on the free plan as requested. Reviewers can test Pro through Apple's sandbox purchase flow; confirm that the product loads and unlocks features in TestFlight.
