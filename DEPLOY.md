# Deploying MoonCycle

Every push to `main` on GitHub runs `.github/workflows/deploy.yml`:

1. Checks the code: `flutter analyze` and the unit tests, plus a syntax
   check of the API.
2. Builds the website (`flutter build web --release`).
3. Copies `server/server.js`, `server/her-notes.js` and the reviewed card
   texts (`content/her-insights-en-GB-combined.json`, as `her-cards.json`)
   to `/opt/mooncycle-api/` and restarts the API.
4. Copies the website to `/var/www/mooncycle/`.

If any step fails, nothing after it runs and the live site stays as it was.
To redeploy without a new commit: Actions tab, "Check and deploy", "Run
workflow".

GitHub logs in as a `deploy` user that can only write the website and the API
files and restart the API. It is not root. Its private key exists only in
GitHub's secrets and in `C:\src\mooncycle_deploy` on the PC.

**Not deployed automatically:** the nginx and systemd files in `server/`, and
npm packages on the server. Those change rarely and are installed by hand.

### AI-written notes on the server (once)

As root on the server:

1. The Anthropic SDK, beside `pg`:
   ```
   cd /opt/mooncycle-api && npm install @anthropic-ai/sdk@1.0.0
   ```
   Pinned: on 23 October 2026 npm listed 1.2.0 but its download returned
   404. 1.0.0 is the version the agent prototype was tested with.
2. The API key, from the Anthropic account in the company's name. Type it on
   the server only, never in chat or the repository:
   ```
   nano /etc/mooncycle-api.env
   ```
   Add the line `ANTHROPIC_API_KEY=...`, save, then
   `systemctl restart mooncycle-api`.

Optional lines in the same file: `AI_NOTES_REVIEW=off` turns off the second
reading of each note (half the cost, less checking); `AI_NOTES_EFFORT=low`.
Without the key, notes simply never arrive and everyone sees the cards.

### Sign in with Apple on the server (once, before the App Store)

Sign in with Apple works without this, but Apple requires that deleting an
account also cancels Apple's link, and that needs the "Sign in with Apple" key
(.p8) from the Apple Developer portal. As root on the server:

1. Copy the key from the PC (in PowerShell, on the PC):
   ```
   scp -i C:\src\RSA_hetzner C:\src\AuthKey_XXXXXXXXXX.p8 root@178.105.213.196:/etc/mooncycle-apple-key.p8
   ```
2. Let only the API read it (find the service's user with
   `systemctl show -p User mooncycle-api`):
   ```
   chown root:<that user> /etc/mooncycle-apple-key.p8 && chmod 640 /etc/mooncycle-apple-key.p8
   ```
3. Add to `/etc/mooncycle-api.env` (the IDs are not secret):
   ```
   APPLE_TEAM_ID=<Team ID>
   APPLE_KEY_ID=<Key ID of that key>
   APPLE_KEY_FILE=/etc/mooncycle-apple-key.p8
   ```
   then `systemctl restart mooncycle-api`.

## One-time setup

### A. On the PC: create the deploy key

1. Create the key. When it asks for a passphrase, press Enter twice (GitHub
   cannot type one):
   ```
   ssh-keygen -t ed25519 -C "mooncycle-deploy" -f C:\src\mooncycle_deploy
   ```
2. Show the public half (safe to show):
   ```
   Get-Content C:\src\mooncycle_deploy.pub
   ```

### B. On the server, as root

1. `ssh -i C:\src\RSA_hetzner root@178.105.213.196`
2. `apt-get update && apt-get install -y rsync`
3. `useradd --create-home --shell /bin/bash deploy && usermod -p '*' deploy`
4. `install -d -m 700 -o deploy -g deploy /home/deploy/.ssh`
5. Paste the public key from A2 after `restrict `:
   ```
   echo 'restrict ssh-ed25519 AAAA...your key... mooncycle-deploy' > /home/deploy/.ssh/authorized_keys
   ```
6. `chown deploy:deploy /home/deploy/.ssh/authorized_keys && chmod 600 /home/deploy/.ssh/authorized_keys`
7. `chown -R deploy:deploy /var/www/mooncycle`
8. `chown deploy:deploy /opt/mooncycle-api /opt/mooncycle-api/*.js /opt/mooncycle-api/*.json`
9. Allow it to restart the API, and nothing else:
   ```
   echo 'deploy ALL=(root) NOPASSWD: /usr/bin/systemctl restart mooncycle-api' > /etc/sudoers.d/mooncycle-deploy && chmod 440 /etc/sudoers.d/mooncycle-deploy && visudo -cf /etc/sudoers.d/mooncycle-deploy
   ```
   It must say `parsed OK`.
10. Note the server's fingerprint, then `exit`:
    ```
    ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub
    ```

### C. On the PC: test the deploy login

```
ssh -i C:\src\mooncycle_deploy deploy@178.105.213.196 "sudo systemctl restart mooncycle-api && systemctl is-active mooncycle-api"
```
It must print `active`.

### D. The server's public key, and the GitHub secrets

1. The server's public key is in `.github/known_hosts`, one line:
   `178.105.213.196 ssh-ed25519 AAAA...`. It is public, so it is kept in the
   repository; GitHub refuses to deploy to a server whose key does not match.
   Its fingerprint must equal the one from B10. For this server it is
   `SHA256:1KY822mEPjebQCE7Tbk3n2nuZP9YtaN2iY4ZK5UXCMY`.
   (The PC's `ssh-keyscan` is too old for this server, so the line was taken
   from `C:\Users\<you>\.ssh\known_hosts`, saved on the first login. On the
   server, `cat /etc/ssh/ssh_host_ed25519_key.pub` shows the same key.)
2. In the `mooncycle` repository: Settings, Secrets and variables, Actions,
   New repository secret. Add two:
   - `DEPLOY_HOST`: `178.105.213.196`
   - `DEPLOY_SSH_KEY`: copy the private key as one line, which survives
     pasting exactly, then paste. Never paste this one anywhere else.
     ```
     $k = [Convert]::ToBase64String([IO.File]::ReadAllBytes('C:\src\mooncycle_deploy')); "$($k.Length) characters, starts with $($k.Substring(0,14))"
     ```
     It should say about 540 characters, starting with `LS0tLS1CRUdJTi`
     (that is only the encoded header line, not secret). Then copy it:
     ```
     $k | Set-Clipboard
     ```
     The key must have no passphrase: if section C asks for one, remove it
     with `ssh-keygen -p -f C:\src\mooncycle_deploy` (type the old one, then
     press Enter twice), and copy it again.

### E. First deploy

Push to `main`, then watch the Actions tab. Green means it is live on
mooncycle.fit.

## Moving to a new server

Repeat section B on the new server (after installing nginx, Node, PostgreSQL
and the API as before), then update the `DEPLOY_HOST` secret and the line in
`.github/known_hosts` (section D).

## If a run fails

Open the failed run on the Actions tab and the step marked red.

- **Analyse or Unit tests:** a code problem; nothing was deployed.
- **Prepare SSH or Deploy:** check the two secrets and `.github/known_hosts`,
  and that section C still prints `active`.
