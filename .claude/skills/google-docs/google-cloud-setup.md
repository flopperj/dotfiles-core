# Google Cloud Project Setup

This guide explains how to configure Google Cloud credentials for the Google Docs skill.

## Quota Project

Every request carries the quota project from your Application Default Credentials (`--set-quota-project=<your-gcp-project>` at login, or the gcloud default project). Use the Google Cloud project your org enabled the Google Docs API and Google Drive API on; the skill has no built-in default.

## Setting Up a Project

If no project has the APIs enabled yet, or you want to use a different one, follow these steps:

### Step 1: Enable Required APIs

1. Go to the [Google Cloud Console](https://console.cloud.google.com/)
2. Select your project from the project dropdown (or create a new one)
3. Navigate to **APIs & Services** → **Library**
4. Search for and enable each of these APIs:
   - **Google Docs API** - Required for creating and editing documents
   - **Google Drive API** - Required for file operations (create, read, share)

To enable an API:
- Click on the API name in the library
- Click the **Enable** button
- Wait for the API to be enabled (usually takes a few seconds)

### Step 2: Configure OAuth Consent Screen

If this is a new project, you'll need to configure the OAuth consent screen:

1. Go to **APIs & Services** → **OAuth consent screen**
2. Select **Internal** (for Workspace users) or **External** (for personal accounts)
3. Fill in the required fields:
   - App name (e.g., "Cursor Agent")
   - User support email
   - Developer contact email
4. Click **Save and Continue**
5. On the Scopes page, click **Add or Remove Scopes** and add:
   - `https://www.googleapis.com/auth/documents`
   - `https://www.googleapis.com/auth/drive`
   - `https://www.googleapis.com/auth/cloud-platform`
6. Click **Save and Continue** through the remaining steps

### Step 3: Authenticate with Your Project

Run the following command, replacing `YOUR_PROJECT_ID` with your project ID:

```bash
gcloud auth application-default login \
  --project=YOUR_PROJECT_ID \
  --scopes="https://www.googleapis.com/auth/cloud-platform,https://www.googleapis.com/auth/documents,https://www.googleapis.com/auth/drive"
```

This will:
1. Open a browser window for Google authentication
2. Ask you to authorize the requested scopes
3. Save credentials to `~/.config/gcloud/application_default_credentials.json`

### Step 4: Set Default Project (Optional)

To set the default project for all gcloud commands:

```bash
gcloud config set project YOUR_PROJECT_ID
```

### Step 5: Verify Setup

Test that authentication is working:

```bash
python3 -c "
from google.auth import default
from googleapiclient.discovery import build

creds, project = default(scopes=['https://www.googleapis.com/auth/documents'])
print(f'Authenticated with project: {project}')

docs = build('docs', 'v1', credentials=creds, cache_discovery=False)
print('Google Docs API: Connected')
"
```

## Switching Between Projects

To switch to a different project, simply re-run Step 3 with the new project ID. The credentials file will be overwritten with the new credentials.

## Troubleshooting

### "API not enabled" Error

If you see an error like `Google Docs API has not been used in project X`:
1. Go to the [API Library](https://console.cloud.google.com/apis/library)
2. Ensure you have the correct project selected
3. Search for and enable the required API

### "Access Denied" Error

If you see permission errors:
1. Verify the OAuth consent screen is configured
2. Ensure the required scopes are added to the consent screen
3. Re-run the authentication command to refresh credentials

### "Invalid Credentials" Error

If credentials are stale or invalid:
```bash
gcloud auth application-default revoke
gcloud auth application-default login \
  --scopes="https://www.googleapis.com/auth/cloud-platform,https://www.googleapis.com/auth/documents,https://www.googleapis.com/auth/drive"
```

## References

- [Google Cloud APIs Overview](https://docs.cloud.google.com/apis/docs/overview)
- [Google Docs API Documentation](https://developers.google.com/docs/api)
- [Google Drive API Documentation](https://developers.google.com/drive/api)
- [Application Default Credentials](https://cloud.google.com/docs/authentication/application-default-credentials)
