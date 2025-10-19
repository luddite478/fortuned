# Anonymous Authentication and Device-Based Identity

This document outlines the authentication-less approach implemented in the application, which provides a seamless first-launch experience for users without requiring a traditional login or registration.

## High-Level Goal

The primary goal is to remove user friction by eliminating the need for an email/password signup. The app instantly creates a unique identity for the user on their device, which is then used to silently create an account on the backend. This allows all user data (threads, playlists, etc.) to be associated with this identity and synchronized with the server.

## Client-Side Implementation (`app/`)

The core of the client-side implementation is the `UserState` class (`lib/state/user_state.dart`).

### Key Responsibilities:
1.  **Identity Management**: On first launch, `UserState` generates a unique, 24-character hexadecimal ID. This ID is then persisted locally on the device using the `shared_preferences` package. On subsequent launches, this saved ID is loaded, ensuring the user maintains the same identity.

2.  **Backend Synchronization**: After loading or creating a user ID, `UserState` calls the `UsersService.getOrCreateUser` method. It sends the entire local user profile to the `POST /api/v1/users/session` endpoint on the server, which handles the "get-or-create" logic.

### Development and Testing Features

To facilitate testing and development across multiple devices (e.g., a simulator and a physical phone), a developer-specific workflow has been implemented.

**1. Shared Developer User:**

You can force the app to use a fixed, hardcoded user ID by passing a `--dart-define` flag when running the app. This is configured in the `run-ios.sh` script.

-   **Command:**
    ```bash
    # The 4th argument is the developer user ID
    ./run-ios.sh <env> <device> <model> YOUR_USER_ID_HERE
    ```
-   **Mechanism:** If the `DEV_USER_ID` variable is present, `UserState` bypasses the local storage check and a random ID generation, and instead uses the provided ID.

**2. Clearing Storage:**

To test the "first-launch" experience reliably, a `clear` flag can be passed to the run script.

-   **Command:**
    ```bash
    # The last argument is 'clear'
    ./run-ios.sh <env> <device> <model> <user_id or ""> clear
    ```
-   **Mechanism:** The script passes a `CLEAR_STORAGE=true` flag to the app. `UserState` detects this flag on startup and deletes the saved user profile from `shared_preferences` *before* any other logic runs, ensuring a completely fresh start.

## Server-Side Implementation (`server/`)

The backend was modified to support this new authentication flow.

### Key Changes:

**1. New Endpoint: `POST /api/v1/users/session`**

-   This endpoint was added to `server/app/http_api/users.py` and registered in `server/app/http_api/router.py`.
-   It accepts a user profile in the request body.
-   **Logic**:
    -   It first searches the `users` collection for a document with the given `id`.
    -   If a user is found, it updates their `last_online` timestamp and returns the existing user document.
    -   If no user is found, it creates a new user document using the data provided by the client and returns it with a `201` status code.

**2. Schema and Data Changes:**

-   **User Schema**: The `password_hash` and `salt` fields were removed from the `required` array in `schemas/0.0.1/user/user.json` to allow for password-less users.
-   **Sample Data**: The sample data in `server/app/db/init_collections.py` was updated to include an example of an anonymous user without password information.
-   **Serialization Fix**: A fix was implemented in the `session_handler` to correctly serialize MongoDB's `ObjectId` type to a string before sending it in a JSON response, resolving a `500` error.
