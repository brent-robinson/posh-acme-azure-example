#!/bin/bash

# Updates Okta with the latest certificate in key vault
#
# Requires Env Vars:
#   
#   VAULT_NAME - The name of the key vault (e.g., `hv-dev-001-kv-ops-01`)
#   CERT_NAME - The name of the certificate in key vault (e.g., `auth-homevalet-dev`)
#   OKTA_ORG_NAME - The name of the Okta org (e.g., `homevalet`)
#   OKTA_API_TOKEN - The Okta token to use for updating (see <https://developer.okta.com/docs/guides/create-an-api-token/create-the-token/>)
#   OKTA_BASE_URL - The base URL to use (e.g., `oktapreview.com`)
#   OKTA_CUSTOM_AUTH_HOSTNAME - The hostname of the custom auth (e.g., `auth.homevalet.dev`)

set -e # Exit on failure

echo showing cert details
az keyvault certificate show --vault-name $VAULT_NAME --name $CERT_NAME -o json

echo downloading certificate
az keyvault secret download --vault-name $VAULT_NAME --name $CERT_NAME --file cert.pfx -e base64

# Convert the certificate to a PFX file with a password (openssl cannot deal with PFX files that have a blank passphrase)
# This uses the java SDK `keytool` toolset to add the passphrase to it
echo adding passphrase to PFX
keytool -importkeystore -srckeystore cert.pfx -srcstoretype PKCS12 -srcstorepass '' -deststoretype PKCS12 -deststorepass asdfasdf -destkeystore cert-protected.pfx -noprompt
rm cert.pfx

echo extracting keys
openssl pkcs12 -in cert-protected.pfx -passin pass:asdfasdf -nocerts -nodes | openssl pkcs8 -nocrypt -out key.pem
KEY=$(sed -E ':a;N;$!ba;s/\r{0,1}\n/\\n/g' key.pem) # replace line breaks with \n literals
openssl pkcs12 -in cert-protected.pfx -passin pass:asdfasdf -clcerts -nokeys | openssl x509 -out cert.pem
CERT=$(sed -E ':a;N;$!ba;s/\r{0,1}\n/\\n/g' cert.pem) # replace line breaks with \n literals
openssl pkcs12 -in cert-protected.pfx -passin pass:asdfasdf -cacerts -nokeys | openssl x509 -out ca.pem
CA=$(sed -E ':a;N;$!ba;s/\r{0,1}\n/\\n/g' ca.pem) # replace line breaks with \n literals
rm cert-protected.pfx

echo searching for $OKTA_CUSTOM_AUTH_HOSTNAME
DOMAINS=$(curl -H "Accept: application/json" -H "Content-Type: application/json" -H "Authorization: SSWS $OKTA_API_TOKEN" "https://$OKTA_ORG_NAME.$OKTA_BASE_URL/api/v1/domains")
echo $DOMAINS
DOMAIN_ID=$(echo $DOMAINS | jq -r '.domains[] | select(.domain==env.OKTA_CUSTOM_AUTH_HOSTNAME).id')
if [ "$DOMAIN_ID" == "" ]; then
    echo "domain not found!"
    exit 1
fi
echo found $DOMAIN_ID

echo '{ "type": "PEM", "privateKey": "'$KEY'", "certificate": "'$CERT'", "certificateChain": "'$CA'"}' > data.json
rm ca.pem
rm cert.pem
rm key.pem

echo Publishing Cert to Okta
curl -X PUT \
-H "Accept: application/json" \
-H "Content-Type: application/json" \
-H "Authorization: SSWS $OKTA_API_TOKEN" \
--data-binary "@data.json" \
"https://$OKTA_ORG_NAME.$OKTA_BASE_URL/api/v1/domains/$DOMAIN_ID/certificate"

rm data.json
