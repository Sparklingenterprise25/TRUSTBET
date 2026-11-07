# TRUSTBET admin JavaScript boundary map

Branch: `security/admin-ui-isolation`

This file began as a source-inspection checkpoint. The extraction is now staged on the working branch; static validation and a Vercel preview build passed. Full runtime regression remains outstanding.

## Admin-exclusive function clusters

The current `index.html` module contains these identifiable administrator clusters:

| Cluster | Functions | Extraction note |
|---|---|---|
| Odds editor | `renderAdminOddsEditor`, `saveAdminGameOdds` | Keep `loadGameOdds` shared: it also supplies public game odds. Move only the editor and administrator save path. |
| Request review | `adminProfileNames`, `adminProfilePhones`, `adminRequestDate`, `adminRequestNameEditor`, `showAdminReceipt`, `confirmAdminDecision`, `adminSelfExclusion`, `adminDeposits`, `adminWithdrawals` | Receipt rendering and decision confirmation are admin-only; wallet refresh and shared request data must be checked before moving callers. |
| User administration | `adminUserAction`, `renderWelcomeNameManager`, `openWelcomeNameEditor`, `renderAdminUsers`, `adminUsers` | Keep customer-facing identity/profile rendering separate. The generic `welcomeName` helper is not classified as admin-only without checking every caller. |
| Recovery and phone approvals | `backfillRecoveryCodes`, `formatAdminConfirmationInput`, `recoveryAdminAction`, `showRecoveryCodes`, `phoneAdminAction`, `adminPhoneApprovals` | These operations must not be exposed in the public customer bundle. |
| Registration controls | `readActiveRegistrationRule`, `paintRegistrationRuleStatus`, `refreshRegistrationRuleControls`, `selectRegistrationRule`, `openRegistrationRulesReadOnly` | Admin controls and previews are separate from customer registration submission and validation. |
| Support inbox | `adminInbox` | Move inbox listing/search/pagination and its admin-only subscription; retain the shared customer chat panel, message renderer, and sender. |

## Shared boundaries that must stay shared or be split first

- `isAdmin` is a role predicate used across mixed code. Its existence in the public bundle is not itself an authorization boundary.
- `profileLoad` initializes the customer session and also starts admin workflows. Split its admin startup branch rather than moving the whole initializer.
- `loadGameOdds` loads public odds and updates the admin editor. Remove only the editor refresh side effect from the public module after the protected portal has its own refresh path.
- `loadBankDetails` supports the public deposit page. Keep customer-visible verified bank details; move the `#adminBankEditor` controls and save handlers.
- `#chatPanel` and its shared message/realtime code serve both customer and administrator conversations. Do not move or remove the shared panel.
- Customer account deletion and self-exclusion submission are not the same as the admin review queues. Preserve the customer request forms and their submission handlers.
- Customer wallet/deposit/withdrawal request creation must remain distinct from administrator review and approval functions.

## Public-document removal checklist

Before removing anything from `index.html`, verify each item against its full set of call sites:

1. Admin dashboard wrapper `#adminArea` and its dashboard-only descendants.
2. Admin-only bank editor `#adminBankEditor`, without removing the public deposit details or request form.
3. Admin receipt overlay `#adminReceiptOverlay` and its receipt-only styles.
4. Admin-exclusive event bindings, startup calls, inbox subscriptions, and helper functions.
5. Admin-only CSS, while retaining styles used by customer pages or shared chat.
6. Admin-only data reads and mutation calls, ensuring the public bundle does not contain administrator workflows.

## Safe next implementation boundary

The first code extraction should establish a protected portal response and asset-loading contract, then move one self-contained cluster at a time. The existing Edge Function currently returns only an authorization JSON response; it does not yet serve portal HTML or JavaScript. It must not be treated as a completed protected portal.

No production deployment, database modification, role/permission change, or change to the 12 protected SECURITY DEFINER warnings is part of this checkpoint.


## Additional call-site findings from the next pass

A second reference scan found several important cross-cluster dependencies that must be handled explicitly:

- `adminAccountDeletionRequests` is an administrator review workflow, but its code is interleaved with the shared customer account-deletion flow. Keep `deletionAction` as a shared service because it submits customer requests as well as administrator list/review actions. Move only the administrator queue renderer, approval/rejection UI, and admin-only confirmation helper.
- `confirmDeletionTwoWay` is an admin-only confirmation UI. `formatAdminConfirmationInput` is also used by phone-approval confirmation, so it belongs with the shared protected admin confirmation utilities—not in the customer bundle.
- `adminProfilePhones` is called by the self-exclusion, deposit, withdrawal, and account-deletion review queues. It can move with the admin review utilities, provided all those queues move together or the helper is exported to the portal's admin service module.
- `adminProfileNames` is called by self-exclusion, deposit, and withdrawal review queues. Treat it the same way as `adminProfilePhones`.
- `adminUsers` has callers from user actions, recovery-code workflows, and phone-approval workflows. Those clusters are not independently movable until their refresh/update calls are redirected to a shared admin user-service interface.
- `adminPhoneApprovals` refreshes `adminUsers` after an approval; `adminUsers` in turn refreshes recovery-code-related data. Preserve this refresh chain when extracting the user, recovery-code, and phone-approval cluster.
- `confirmAdminDecision` is used by self-exclusion, deposit, and withdrawal review. Move it with those review queues, not with the separate account-deletion confirmation flow.
- `readActiveRegistrationRule` is called by both the admin controls and customer registration validation. Keep the read/validation path available to customer registration; move only the admin controls and their presentation/update actions. The portal can call a protected admin-specific wrapper if it needs a separate refresh.
- `loadGameOdds` must continue to work when the admin portal is not open. The public function should not assume the admin editor DOM exists.

### Extraction order implied by these dependencies

1. Establish the protected document transport and customer-side portal entry point without changing any customer flow.
2. Extract the admin review queues as one unit, including account-deletion review, admin-only confirmation UIs, and the shared admin profile lookup helpers.
3. Extract the admin user/recovery/phone-approval cluster as one unit because its workflows refresh one another.
4. Extract the registration-rule controls while leaving customer registration's rule-read/validation path intact.
5. Extract the odds editor and its save/refresh path while retaining public odds loading.
6. Extract the admin inbox after its dependency on the shared chat panel and realtime subscription has been isolated.

Do not treat this ordering as permission to delete code by name alone. Re-check every call site after each move and compare the customer-facing behavior before and after.


## Additional administrator-only workflows found in the role-branch scan

The full `isAdmin()` call-site scan identified two more extraction areas and several shared role-aware branches:

- **Administrator wallet-credit console:** the bulk wallet-credit workflow (registered-user search, multi-select state, batch fingerprint/ID, confirmation, and `admin_issue_bulk_wallet_credit` RPC call) is admin-only and belongs in the protected portal. It also calls `confirmAdminDecision`, so that confirmation utility must remain available to both request-review and wallet-credit workflows inside the portal.
- **Bank-detail editor:** the save handler is guarded by `isAdmin()`, but `loadBankDetails` is shared and must remain in the customer site. Move only editor controls and the admin save handler; do not remove the public bank-details display or customer deposit flow.
- **Customer account-deletion restriction:** customer deletion submission explicitly refuses administrator accounts. Preserve this business rule in the customer flow, while moving only the admin request-review queue and its decision UI.
- **Shared support chat:** administrator-specific message length, idle timeout, retention period, sender interpretation, and inbox behavior are interwoven with customer chat. The shared chat panel and common message transport must stay available; isolate the role-dependent settings behind a portal-provided configuration rather than stripping every `isAdmin()` branch from the public module.
- **Profile initialization:** `profileLoad` currently reveals the dashboard, toggles the bank editor, starts multiple admin queues, and calls `adminInbox` even for non-admin users (the inbox function itself checks the role). The future public initializer should only initialize customer state and show the admin entry control when the existing role is admin. Portal startup should happen only after an explicit admin action.
- **Deposit page navigation:** `go('deposit')` currently checks the admin role to reveal the bank editor. Keep the public bank-detail loading behavior but remove the editor toggle from the customer page after the editor has moved into the portal.

### Revised protected workflow grouping

The protected portal extraction now has these clusters:

1. Request review: self-exclusion, deposit, withdrawal, and account-deletion queues; admin profile lookups; receipt/decision UI.
2. User administration: user search/actions, welcome-name manager, recovery-code administration, and phone-registration approvals.
3. Wallet credits: single/bulk admin credit controls and their state, confirmation, and RPC calls.
4. Registration rules: admin control panel only; retain shared customer rule-read/validation.
5. Odds administration: editor/save controls only; retain public odds reads.
6. Support inbox: inbox search/pagination/selection; retain shared chat renderer and transport.
7. Bank editor: bank-details editing only; retain public bank-details display and customer deposit submission.

The shared support chat's role-specific settings need a dedicated boundary in the design; simply moving the inbox function is not sufficient to complete admin-code isolation.


## CSS boundary scan

The stylesheet contains several clearly portal-specific groups:

- Receipt overlay and receipt card/print rules (`#adminReceiptOverlay`, `.admin-receipt*`).
- Bank editor (`.admin-bank-editor`).
- Dashboard section and odds editor (`.admin-section`, `.odds-admin-*`, `#adminGameOddsStatus`).
- Admin request queue rows (`.admin-request`).
- Admin inbox toolbar, viewport, cards, and pagination (`.admin-inbox-*`, `#adminInbox`).

Do not remove every selector containing the word "admin". These selectors are shared with customer-facing behavior and must remain or be recreated in the right shared stylesheet:

- `.bubble.admin-message` styles administrator messages shown in the shared support chat.
- `.admin-support-notice*` styles support notices shown in the customer experience.
- `#gameStage.admin-game-stage` and `.admin-game-stage*` are tied to the game-stage presentation, not the dashboard extraction.
- Generic layout utilities such as `.row`, `.muted`, button styles, labels, and shared responsive rules are used throughout the customer site.

Move only the confirmed portal-specific rules into the protected portal stylesheet. Compare computed layout and responsive behavior for both customer and admin screens before deleting any original declarations.


### Support-chat split: concrete functions and state

The shared support section needs a more precise split than simply moving `adminInbox`:

**Keep in the customer/shared layer**
- `conversationOpen`, the shared `chatLoad` message renderer, shared send/attachment handling, and the common realtime channel lifecycle.
- `closeSupportChat` and the common chat-panel UI behavior, adjusted so the customer app and protected portal each own their own panel instance when loaded as separate documents.
- `refreshCustomerChatNotice`, `formatSupportNoticeTime`, and the customer notice subscription.
- Shared attachment validation and signed-URL rendering.

**Move to the protected admin portal**
- `adminInbox`, its page/search/render state (`adminInboxPage`, `adminInboxSearchBound`, `adminInboxRenderToken`, `ADMIN_INBOX_PAGE_SIZE`), and inbox-specific realtime behavior.
- `loadSupportCustomerIdentity`, which fetches and displays a selected customer's account details for an administrator.
- The admin inbox conversation-selection behavior and its admin-only DOM controls.

**Split behind explicit chat configuration**
- `moveSupportChatPanel` currently moves one shared panel between the customer entry point and `adminChatPanelSlot`. A separate portal document needs its own panel placement; do not keep a cross-document DOM move.
- `resetSupportChatIdle`, message-length limits, visible-history retention (365 days for admin vs 7 days for customer), sender labeling, and read-notice behavior are role-dependent. Keep the customer values in the public customer module and define the admin values only in the protected portal.
- `chatLoad` currently contains both customer and admin sender interpretation and customer local-storage read marking. Split the role-specific presentation/side effects from the common message retrieval/rendering so the public bundle does not carry admin-only inbox behavior.

The admin inbox currently loads conversation metadata and profile details for multiple users. Keep that query and its pagination/search state out of the public bundle. Do not move the shared customer conversation renderer wholesale without preserving attachment, read-state, and realtime behavior.


## Final role-branch and event-binding pass

A final scan of every `isAdmin()` occurrence identified these specific mixed-code boundaries that must be accounted for during extraction:

- The deposit submit handler refreshes the admin deposit queue after a successful request only when the current user is an admin. The customer submit path must remain, while any portal queue refresh must be redirected to the protected portal context.
- The public deposit navigation branch calls `loadBankDetails()` for everyone but also reveals `#adminBankEditor` for admins. Keep the public bank-detail load and remove the editor reveal from the customer document after extraction.
- The bank editor save handler writes `platform_bank_details`; it is separate from the public read/copy handlers and belongs in the portal. The public `loadBankDetails()` must not depend on editor fields being present.
- The wallet-credit console is a full admin-only unit: registered-user paging/search, selected-user state, batch fingerprint/ID, confirmation, and `admin_issue_bulk_wallet_credit`. Its markup, state, and event bindings must move together.
- Registration-rule controls and previews are admin-only, but `readActiveRegistrationRule()` is also called by customer signup paths. Keep that read helper or a customer-safe equivalent in the public bundle; move the controls, status painting, selection RPC, and preview UI.
- The customer account-deletion submit handler intentionally blocks admin accounts. Preserve this check and customer request submission; only the review queue and its two-step admin confirmation move.
- The support-chat panel is currently physically moved between customer and admin dashboard slots. Separate documents must each own their own panel; do not retain a cross-document panel-move helper. Keep customer idle timeout, 1,000-character limit, seven-day history, customer read marking, and customer notice subscription in the customer app. Put the admin 5-minute timeout, 2,000-character limit, 365-day history, admin sender interpretation, inbox identity, and inbox selection behavior in the protected portal.
- The administrator inbox is invoked from `profileLoad` after customer initialization. The future public initializer must not invoke it. The admin portal should start it only after protected document initialization.
- The administrator-only registration preview handlers are attached near the end of the shared module; moving only the preview markup without these handlers would leave dead controls.

This pass is a dependency checkpoint, not a source extraction. The current public `index.html` remains unchanged.


## Extraction progress

- **Game odds administration:** the public document now retains `loadGameOdds()` for customer-facing game odds, but the admin odds editor markup, renderer, save handler, refresh handler, and the admin-only refresh side effect have been removed from `index.html`. The protected portal snapshot retains the original editor and workflow. No odds RPC, data, or database configuration was changed.
