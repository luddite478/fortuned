# S3 Storage Setup for Audio Uploads

## Overview
This application uses Digital Ocean Spaces (S3-compatible storage) for storing audio renders attached to thread messages.

## Environment Variables

Add the following variables to your server's `.env` file:

```bash
# Environment Configuration
ENV=prod  # or 'stage', 'dev' - used as prefix in S3 paths

# S3 / Digital Ocean Spaces Configuration
S3_ENDPOINT_URL=https://nyc3.digitaloceanspaces.com  # Your DO Spaces endpoint
S3_REGION=us-east-1  # or your preferred region
S3_ACCESS_KEY=your_access_key_here
S3_SECRET_KEY=your_secret_key_here
S3_BUCKET_NAME=your_bucket_name_here
```

## Digital Ocean Spaces Setup

1. Go to Digital Ocean Spaces dashboard
2. Create a new Space (if you haven't already)
3. Generate API keys:
   - Go to API → Tokens/Keys → Spaces Keys
   - Click "Generate New Key"
   - Save the Access Key and Secret Key
4. Configure your Space:
   - Set the Space to **public** or configure appropriate CORS settings
   - Note the endpoint URL (e.g., `https://nyc3.digitaloceanspaces.com`)
   - Note your bucket name

## Testing

Once configured, you can test the upload functionality:

1. Start the server: `cd server && uv run uvicorn app.main:app --reload`
2. Record audio in the sequencer
3. Press the send button
4. The audio will automatically upload to S3 and attach to the message

## File Structure

Uploaded files are organized with environment prefix:
```
{ENV}/
  └── renders/
      └── {uuid}.mp3
```

Examples:
- Production: `prod/renders/abc123-def456.mp3`
- Staging: `stage/renders/abc123-def456.mp3`
- Development: `dev/renders/abc123-def456.mp3`

This keeps different environments separate in the same S3 bucket.

## Upload Flow

1. User records audio in sequencer
2. Audio is converted to MP3 locally
3. When send button is pressed:
   - Message is sent immediately with snapshot
   - Audio upload starts in background
   - Upload progress shown in UI
   - Once complete, render is attached to message
   - UI updates to show audio attachment

## Security Notes

- Store credentials in `.env` file (never commit to git)
- Ensure `.env` is in `.gitignore`
- Use separate credentials for development and production
- Configure CORS on your Space to allow requests from your app domain

