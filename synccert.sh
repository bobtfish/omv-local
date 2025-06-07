#/bin/bash
#
set -e
set -o pipefail

source /etc/default/openmediavault

DNS_NAME=$(docker run -e TS_SOCKET=/var/run/tailscale/tailscaled.sock -e TS_STATE_DIR=/var/lib/tailscale -v tailscale_run:/var/run/tailscale -v /docker/appdata/state:/var/lib/tailscale:rw -v /etc/ssl:/etc/ssl:rw tailscale/tailscale:latest tailscale status --json | jq -r .Self.DNSName | sed -e's/\.$//')

KEY_FILE="/etc/ssl/private/${DNS_NAME}.key"
CERT_FILE="/etc/ssl/certs/${DNS_NAME}.cert"
UUID_FILE="/etc/ssl/private/${DNS_NAME}.key.uuid"

docker run -e TS_SOCKET=/var/run/tailscale/tailscaled.sock -e TS_STATE_DIR=/var/lib/tailscale -v tailscale_run:/var/run/tailscale -v /docker/appdata/state:/var/lib/tailscale:rw -v /etc/ssl:/etc/ssl:rw tailscale/tailscale:latest tailscale cert --key-file $KEY_FILE --cert-file $CERT_FILE $DNS_NAME

if [[ -f $UUID_FILE ]]; then
  echo -n "Renewing $KEY_FILE in OpenMediaVault: "
    OLDCERT=$(omv-rpc -u admin CertificateMgmt get "$(echo -n '{"uuid": "'; cat < $UUID_FILE | tr -d '\n'; echo -n '"}')" | jq -r .certificate | sed 's/$/\\/g' | tr '\n' 'n' | sed -e's/\\n\\n/\\n/')
    NEWCERT=$(sed 's/$/\\/g' < $CERT_FILE | tr '\n' 'n')
    if [[ "$OLDCERT" == "$NEWCERT" ]]; then
        echo "unchanged, not changing in admin"
	exit 0
    fi
    omv-rpc -u admin CertificateMgmt set "$(echo -n '{"uuid": "'; cat < $UUID_FILE | tr -d '\n'; echo -n '", "certificate": "'; echo -n $NEWCERT ; echo -n '", "privatekey": "' ; sed 's/$/\\/g' $KEY_FILE | tr '\n' 'n'; echo -n '", "comment": "/CN='; echo -n $DNS_NAME; echo -n '/"}')" >/dev/null
  echo "Done"
else
  echo -n "Registering $KEY_FILE with OpenMediaVault: "
  omv-rpc -u admin CertificateMgmt set "$(echo -n '{"uuid": "'; echo -n $OMV_CONFIGOBJECT_NEW_UUID; echo -n '", "certificate": "'; sed 's/$/\\/g' < $CERT_FILE | tr '\n' 'n'; echo -n '", "privatekey": "' ; sed 's/$/\\/g' $KEY_FILE | tr '\n' 'n'; echo '", "comment": "/CN='; echo -n $DNS_NAME; echo -n '/"}')" | jq -r .uuid > $UUID_FILE
  echo "Done"
fi

omv-rpc -u admin WebGui setSettings "$(omv-rpc -u admin WebGui getSettings | jq -c ".sslcertificateref = \"$(cat $UUID_FILE | tr -d '\n')\"")"
omv-rpc -u admin "Config" "applyChanges" "{\"modules\": $(cat /var/lib/openmediavault/dirtymodules.json), \"force\": false}"

