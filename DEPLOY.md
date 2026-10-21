# Deploying MoonCycle

Every push to `main` on GitHub runs `.github/workflows/deploy.yml`:

1. Checks the code: `flutter analyze` and the unit tests, plus a syntax
   check of the API.
2. Builds the website (`flutter build web --release`).
3. Copies `server/server.js`, `tip-writer.js` and `tips-seed.json` to
   `/opt/mooncycle-api/` and restarts the API.
4. Copies the website to `/var/www/mooncycle/`.

If any step fails, nothing after it runs and the live site stays as it was.
To redeploy without a new commit: Actions tab, "Check and deploy", "Run
workflow".

GitHub logs in as a `deploy` user that can only write the website and the API
files and restart the API. It is not root. Its private key exists only in
GitHub's secrets and in `C:\src\mooncycle_deploy` on the PC.

**Not deployed automatically:** the nginx and systemd files in `server/`, and
npm packages on the server. Those change rarely and are installed by hand.

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

### D. On GitHub: add the secrets

1. Check the fingerprint matches B10:
   ```
   ssh-keyscan -t ed25519 178.105.213.196 | ssh-keygen -lf -
   ```
2. In the `mooncycle` repository: Settings, Secrets and variables, Actions,
   New repository secret. Add three:
   - `DEPLOY_HOST`: `178.105.213.196`
   - `DEPLOY_KNOWN_HOSTS`: run `ssh-keyscan -t ed25519 178.105.213.196` and
     copy the one line that starts with `178.105.213.196 ssh-ed25519 AAAA`
     (not a line starting with `#`, and not the `SHA256:` fingerprint from
     step 1), then paste it. It is public, so it is safe to show.
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
and the API as before), then update `DEPLOY_HOST` and `DEPLOY_KNOWN_HOSTS`
(section D).

## If a run fails

Open the failed run on the Actions tab and the step marked red.

- **Analyse or Unit tests:** a code problem; nothing was deployed.
- **Prepare SSH or Deploy:** check the three secrets, and that section C
  still prints `active`.
