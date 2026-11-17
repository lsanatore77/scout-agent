# How Lou Logs In (dev org cqse-golden--dev)

No passwords or secrets in this file.

## Users
- **lou@golden-dev.com** (Lou Admin, System Administrator): everyday user.
- **lou@cqplay.golden.dev** (Lou Sanatore, System Administrator): spare way in. Set up Salesforce Authenticator on it too, so it can fix the main user if that one gets stuck.

## Sign-in method
- **Admins must use a passkey.** Salesforce now requires phishing-resistant MFA (a passkey) for users with admin-level rights. It reached sandboxes in June 2026 and production in July 2026. That is why the passkey options are greyed out and why login shows "Your account requires a passkey" if none is registered. Do not delete the passkey.
- **Desktop:** password, then the passkey saved on **this Windows PC (Windows Hello)**. Expect to enter the Windows PIN twice; that is normal for this org. Authenticator is not used on the desktop. When creating it, choose this Windows device, not a phone or security key, so Windows can always find it.
- **Salesforce mobile app:** password, then approve in **Salesforce Authenticator**. Salesforce says the mobile app login does not change with the passkey rule.
- **CLI:** `sf org open -o <alias>` uses the saved session.
- Backup (optional): One-Time Password Authenticator, a 6-digit code in the Authenticator app.

## If a login gets stuck on "Choose a passkey"
1. Get in another way: `sf org open -o <alias>`, or log in as the spare user.
2. Setup > Users > the stuck user > Passkeys list: delete the passkey that cannot be found, then log in again and create a new one on this Windows device.
3. Last resort: another admin clicks Generate next to Temporary Verification Code on the stuck user.

## History
- 16 Nov 2026: Built-In Authenticator #1 passkey appeared on lou@golden-dev.com at 5:58 pm CT (not added on purpose). Login on the computer and the phone app stalled on the passkey. Got in via CLI and deleted the passkey; Salesforce then required a new one ("Your account requires a passkey"), because admin users must have one. Lesson: keep one passkey, saved on this Windows device.
