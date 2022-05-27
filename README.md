This is a PowerShell script that can be used as manual auth and cleanup hook,
and executes the necessary [dnscmd](https://docs.microsoft.com/en-us/windows-server/administration/windows-commands/dnscmd)
commands on a Windows DNS server to enable dns-01 authentication.

# Prerequisites

- Custom root CA (e.g. [step-ca](https://smallstep.com/docs/step-ca))
- Windows server acting as DNS
- Active PowerShell Remoting over SSH
  - OpenSSH server
  - [SSH key for an administrator login](https://docs.microsoft.com/de-de/windows-server/administration/openssh/openssh_keymanagement#administrative-user)

# certbot auth hook

Save `certbot-dns-windows.ps1` to `/etc/letsencrypt` and change the following variables:

- `$zone`: The name of the forward lookup zone
- `$dnsServerHostName`: The fully qualified Windows DNS server we're logging in to
- `$userName`: The name of the administrator user used for a login

Important: Make the `certbot-dns-windows.ps1` script executable with: `chmod 755 /etc/letsencrypt/certbot-dns-windows.ps1`.

# certbot command

The `REQUESTS_CA_BUNDLE` is required for a successful TLS connection to your
custom ACME CA server.

You should change the following values:

- `REQUESTS_CA_BUNDLE`: Path to the root CA file to be able to connect to your custom ACME CA server
- `--email`: The ACME CA account
- `--installer`: To be changed when you don't use NGINX
- `-d`: The domain to get the certificate for
- `--cert-name`: The (internal) name of the certificate to be issued
- `--server`: The URL to your custom ACME CA server (e.g. [step-ca](https://smallstep.com/docs/step-ca))

```bash
#!/bin/bash

sudo \
  REQUESTS_CA_BUNDLE=/usr/local/share/ca-certificates/your-custom-root-ca.crt \
  certbot --agree-tos --email "your-account@email.com" \
    run \
      --installer nginx                  \
      --authenticator manual             \
      --manual-auth-hook "/etc/letsencrypt/certbot-dns-windows.ps1" \
      --manual-cleanup-hook "/etc/letsencrypt/certbot-dns-windows.ps1 --remove" \
      -d \*.your.intern.domain.com       \
      --cert-name wildcard-cert-name     \
      --preferred-challenges dns         \
      --server https://your-internal-acme-ca-like-step-ca/acme/acme/directory \
      --force-renewal
```

# Troubleshooting

## Challenge fails

Symptom: The challenge simply doesn't work and you see lots of messages in the step-ca log like `There was a problem with a DNS query during identifier validation`

Explanation: The DNS record lookup uses systemd-resolved which caches DNS requests. Thus, the ACME CA (like step-ca) never sees the newly created TXT records.

Solution: Ensure that the ACME CA queries the Windows DNS server directly.

In case you use step-ca, just add the `--resolver 127.0.0.53:53` argument when starting the `step-ca` server. Don't forget to replace `127.0.0.53` with the correct IP of your DNS server!

The `CMD` of the `smallstep/step-ca` docker image can be overriden, with - for example - the following values:

```yaml
version: "3.8"
services:
  step-ca:
    image: smallstep/step-ca:latest
    restart: always
    command: ["/usr/local/bin/step-ca", "--resolver", "127.0.0.53:53", "--password-file", "/home/step/secrets/password", "/home/step/config/ca.json"]
    network_mode: "host"
    volumes:
      - step:/home/step

volumes:
  step:
```
