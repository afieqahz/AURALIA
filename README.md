# AURALIA

AURALIA is a Flutter-based mood-aware music application designed for mental wellness support. The app lets users record their current mood, generates Spotify-based playlists using a rule-based Iso-Principle approach, tracks mood patterns over time, and supports post-listening reflection.

The project was built as a Final Year Project and focuses on combining mood input, music sequencing, Spotify playback, and simple behavioral analytics in one mobile experience.

## Key Features

- Email-based sign up, login, logout, forgot password, and account deletion.
- Supabase authentication and database persistence.
- Mood selection for Sad, Stressed, Neutral, Happy, and Motivated states.
- Rule-based AI playlist sequencing using the Iso-Principle.
- Spotify API integration for real track search, artwork, duration, and playback metadata.
- Spotify App Remote playback for full-song playback through Spotify.
- Playlist saving and removal from favourites.
- Mini-player and continue-listening state while music is active.
- Mood analytics with mood entries, mood baseline, mood change, helpful sessions, mood trends, insights, and mood distribution.
- Post-listening check-in to record whether the listening session helped the user.
- Wellness suggestions when repeated negative moods are detected.
- Profile management with display name, password update, Spotify connection, and account deletion.

## Tech Stack

- Flutter
- Dart
- Supabase Auth
- Supabase Database
- FastAPI
- Spotify Web API
- Spotify Android SDK / App Remote

## Project Structure

```text
auralia_app/
+-- android/                         # Android project files
+-- assets/                          # App logo and static assets
+-- backend/                         # FastAPI Spotify backend
|   +-- main.py
|   +-- requirements.txt
|   +-- .env.example
+-- lib/                             # Flutter source code
|   +-- core/                        # Models, services, config, shared app state
|   +-- features/                    # Auth, home, chat, player, analytics, profile
+-- supabase_schema.sql              # Main Supabase database schema
+-- supabase_post_listening_checkin.sql
+-- supabase_delete_account.sql
+-- pubspec.yaml
+-- README.md
```

## How AURALIA Works

1. The user logs in or creates an account.
2. The user selects a mood in the AURALIA chat screen.
3. AURALIA records the mood entry in Supabase.
4. A rule-based Iso-Principle engine chooses the playlist progression.
5. The backend requests suitable tracks from Spotify.
6. The app displays generated playlists with track titles, artists, artwork, and duration.
7. The user can save a playlist or play it through Spotify.
8. After the playlist finishes, the app asks for a post-listening check-in.
9. Mood analytics are updated based on mood entries and listening feedback.

## Rule-Based AI / Iso-Principle

AURALIA uses rule-based AI rather than a machine-learning model. The app applies predefined mood and music rules to decide how a playlist should progress.

For low moods such as Sad or Stressed, the playlist should begin by validating the user's current emotional state, then slowly transition toward more balanced or uplifting songs.

Example:

```text
Sad mood
-> Validation tracks
-> Transition tracks
-> Elevation tracks
```

For positive moods such as Happy or Motivated, the playlist can start with higher-energy songs and maintain or guide that energy depending on the user's state.

This makes the app explainable during evaluation because the recommendation logic is based on clear mood-to-music rules.

## Supabase Setup

1. Create a Supabase project.
2. Open the SQL Editor.
3. Run `supabase_schema.sql`.
4. Run the additional SQL files if the features are not already included:

```text
supabase_post_listening_checkin.sql
supabase_delete_account.sql
```

5. Enable email/password authentication in Supabase Authentication settings.
6. Copy your Supabase Project URL and anon key.

Do not commit your real Supabase keys inside source code. Pass them using `--dart-define`.

## Spotify Setup

Create an app in the Spotify Developer Dashboard.

Required settings:

- Add Android package name.
- Add Android SHA1 fingerprint.
- Add redirect URI:

```text
auralia://callback
```

The Flutter app uses the Spotify Client ID. The Spotify Client Secret must stay in the backend only.

## Backend Setup

The backend is required for Spotify Web API search because the Spotify Client Secret must not be stored inside the Flutter mobile app.

Create `backend/.env` from `backend/.env.example`:

```text
SPOTIFY_CLIENT_ID=your_spotify_client_id
SPOTIFY_CLIENT_SECRET=your_spotify_client_secret
```

Run the backend locally:

```powershell
python -m pip install -r requirements.txt
.\.venv\Scripts\python.exe -m uvicorn main:app --reload --host 0.0.0.0 --port 8000
```

Test in browser:

```text
http://127.0.0.1:8000/spotify/search?q=happy
```

When testing on a physical phone, use your laptop IP instead of `localhost`.

Example:

```text
http://192.168.0.182:8000
```

## Run The Flutter App

Install dependencies:

```powershell
flutter pub get
```

Check connected devices:

```powershell
flutter devices
```

Run on Android phone:

```powershell
flutter run -d YOUR_DEVICE_ID `
  --dart-define=SUPABASE_URL=https://your-project-ref.supabase.co `
  --dart-define=SUPABASE_ANON_KEY=your_supabase_anon_key `
  --dart-define=SPOTIFY_BACKEND_URL=http://YOUR_LAPTOP_IP:8000 `
  --dart-define=SPOTIFY_CLIENT_ID=your_spotify_client_id `
  --dart-define=SPOTIFY_REDIRECT_URL=auralia://callback `
  --dart-define=PASSWORD_RESET_REDIRECT_URL=auralia://callback
```

## Build Release APK

Use your deployed backend URL for a real APK. Do not use a laptop IP for production.

```powershell
flutter clean
flutter pub get
flutter build apk --release `
  --dart-define=SUPABASE_URL=https://your-project-ref.supabase.co `
  --dart-define=SUPABASE_ANON_KEY=your_supabase_anon_key `
  --dart-define=SPOTIFY_BACKEND_URL=https://your-backend-url.onrender.com `
  --dart-define=SPOTIFY_CLIENT_ID=your_spotify_client_id `
  --dart-define=SPOTIFY_REDIRECT_URL=auralia://callback `
  --dart-define=PASSWORD_RESET_REDIRECT_URL=auralia://callback
```

The APK will be generated at:

```text
build/app/outputs/flutter-apk/app-release.apk
```

## Deployment Notes

Recommended deployment setup:

```text
Flutter APK
-> Supabase for auth and database
-> FastAPI backend hosted on Render or Railway
-> Spotify Web API
```

Supabase is used for user data and analytics. The FastAPI backend is used for Spotify API calls because it protects the Spotify Client Secret.

## Environment Variables

Flutter app values:

```text
SUPABASE_URL
SUPABASE_ANON_KEY
SPOTIFY_BACKEND_URL
SPOTIFY_CLIENT_ID
SPOTIFY_REDIRECT_URL
PASSWORD_RESET_REDIRECT_URL
```

Backend values:

```text
SPOTIFY_CLIENT_ID
SPOTIFY_CLIENT_SECRET
```

## Important Security Notes

Do not commit:

- `backend/.env`
- real Spotify Client Secret
- private API keys
- generated build files
- local virtual environment folders

Safe to commit:

- `.env.example`
- SQL schema files
- Flutter source code
- backend source code

## Testing Checklist

Before demo or deployment, test:

- New user sign up.
- Existing user login.
- Persistent login after closing and reopening the app.
- Logout and login with another account.
- Mood selection creates a new mood entry.
- Playlist generation returns Spotify tracks when the API is available.
- Track artwork and duration display correctly.
- Save and remove favourite playlist.
- Play, pause, next, and previous controls.
- Mini-player only appears when a track is active.
- Post-listening check-in updates analytics.
- Analytics cards, trends, insights, and distribution update correctly.
- Profile update, change password, and delete account.
- Forgot password opens the reset password flow.

## Limitations

- Full-song playback depends on Spotify support and the Spotify app on the user's device.
- Spotify rate limits can temporarily reduce API availability.
- Free backend hosting may sleep, causing the first request to load slowly.
- APK files only work on Android devices. iPhone requires an iOS build through Apple tools.

## Project Status

AURALIA is a functional Final Year Project prototype with real authentication, database persistence, Spotify-based track generation, music playback flow, and mood analytics. Further improvements can include production hosting, stronger recommendation filtering, app store release preparation, and larger-scale user testing.
