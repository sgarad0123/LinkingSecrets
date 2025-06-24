#!/bin/bash

ORG="${org}"
PROJECT="${project}"
KEYVAULT_NAME="${keyVaultName}"
VG_NAME="${targetVariableGroupName}"
SECRETS_TO_LINK="${secretsToLink}"
AZURE_DEVOPS_PAT="${azure_devops_pat}"

API_URL="https://dev.azure.com/${ORG}/${PROJECT}/_apis/distributedtask/variablegroups?api-version=7.1-preview.2"
AUTH_HEADER="Authorization: Basic $(echo -n ":${AZURE_DEVOPS_PAT}" | base64)"

# Check if Variable Group exists
VG_EXISTS=$(curl -s -H "$AUTH_HEADER" "$API_URL" | jq -r ".value[] | select(.name==\"$VG_NAME\") | .id")

if [ -z "$VG_EXISTS" ]; then
  echo "🔧 Variable Group $VG_NAME not found. Creating..."
  cat <<EOF > create-vg-payload.json
{
  "type": "Vsts",
  "name": "$VG_NAME",
  "variableGroupProjectReferences": [
    {
      "projectReference": {
        "id": "",
        "name": "$PROJECT"
      },
      "name": "$VG_NAME"
    }
  ],
  "variables": {}
}
EOF

  VG_CREATE_RESPONSE=$(curl -s -X POST -H "$AUTH_HEADER" -H "Content-Type: application/json" --data-binary @create-vg-payload.json "$API_URL")
  VG_EXISTS=$(echo "$VG_CREATE_RESPONSE" | jq -r '.id')
  echo "✅ Created Variable Group with ID: $VG_EXISTS"
else
  echo "✅ Variable Group $VG_NAME already exists with ID: $VG_EXISTS"
fi

# Prepare link secrets payload
LINK_PAYLOAD=$(jq -n \
  --arg name "$VG_NAME" \
  --argjson secrets "$(echo ${SECRETS_TO_LINK} | jq -R 'split(",") | map({name: ., keyVault: {"name": "'"$KEYVAULT_NAME"'"}})')" \
  '{
    type: "AzureKeyVault",
    name: $name,
    variables: (reduce $secrets[] as $s ({}; .[$s.name] = { isSecret: true, value: null })),
    properties: {
      linkedSecrets: ($secrets | map(.name) | join(",")),
      keyVault: {
        name: $secrets[0].keyVault.name,
        serviceEndpointId: "'"${serviceConnectionId}"'"
      }
    }
  }')

# Update Variable Group with linked secrets
UPDATE_RESPONSE=$(curl -s -X PUT -H "$AUTH_HEADER" -H "Content-Type: application/json" --data "$LINK_PAYLOAD" "$API_URL/$VG_EXISTS?api-version=7.1-preview.2")

if echo "$UPDATE_RESPONSE" | jq -e '.id' >/dev/null; then
  echo "🔗 Secrets linked successfully to $VG_NAME"
else
  echo "❌ Failed to link secrets. Response: $UPDATE_RESPONSE"
  exit 1
fi
