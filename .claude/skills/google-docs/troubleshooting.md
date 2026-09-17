# Troubleshooting

## "Could not automatically determine credentials"

Run ADC login:
```bash
gcloud auth application-default login \
  --scopes="https://www.googleapis.com/auth/cloud-platform,https://www.googleapis.com/auth/documents,https://www.googleapis.com/auth/drive"
```

## "Request had insufficient authentication scopes"

Re-authenticate with all required scopes (cloud-platform, documents, drive).

## "invalid_grant" or "Token has been revoked"

```bash
gcloud auth application-default revoke
gcloud auth application-default login --scopes="..."
```

## "The caller does not have permission"

- Verify Google account has access to the document
- Shared documents require edit permissions

## "No module named 'google'"

```bash
pip3 install google-auth google-api-python-client
```

## Credential Location

ADC credentials: `~/.config/gcloud/application_default_credentials.json`
