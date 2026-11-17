# How Lou Logs In (dev org cqse-golden--dev)

No passwords or secrets in this file.

## Users
- **lou@golden-dev.com** (Lou Admin, System Administrator): everyday user.
- **lou@cqplay.golden.dev** (Lou Sanatore, System Administrator): spare way in. Set up Salesforce Authenticator on it too, so it can fix the main user if that one gets stuck.

## Sign-in method
- Password, then approve on **Salesforce Authenticator** (phone). Same for the computer, the Salesforce mobile app and the CLI.
- Backup (optional): One-Time Password Authenticator, a 6-digit code in the same app.
- Geolocation auto-approve is on in the org, so logins from a trusted place may approve themselves.

## Passkeys: say no
- The org has passkey options locked on (built-in authenticator and security key are greyed out in Session Settings, because MFA is required for all logins).
- After a login, Salesforce, Windows Hello or the browser may offer to create a passkey. Click Not Now, Skip or Cancel.
- Why: the Salesforce mobile app cannot use passkeys, and a passkey saved on one device makes the login stall on another. Once a passkey exists, Salesforce asks for it first.
- Do not turn on "Allow passwordless login with passkeys".

## If a login gets stuck on "Choose a passkey"
1. Get in another way: `sf org open -o <alias>` (uses the CLI's saved session), or log in as the spare user.
2. Setup > Users > the stuck user > Passkeys related list > Del every entry.
3. Check App Registration: Salesforce Authenticator says [Disconnect] (connected).
4. Last resort: another admin clicks Generate next to Temporary Verification Code on the stuck user.

## History
- 16 Nov 2026: Built-In Authenticator #1 passkey appeared on lou@golden-dev.com at 5:58 pm CT (not added on purpose). Login on the computer and the phone app stalled on the passkey. Got in via CLI, deleted the passkey; Salesforce Authenticator confirmed connected.
