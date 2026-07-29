# Read meetings from macOS Calendar via EventKit

Meetings live in an Outlook (Microsoft 365) work calendar, but registering an app with the IT tenant is not possible, which rules out the Microsoft Graph API. Outlook ICS publish links lag 15–60 minutes, which is fatal for minute-accurate alerts. We therefore read events locally via EventKit and require, as a setup step, that the user adds their Outlook account to the built-in macOS Calendar app (Exchange account sync). This also transparently covers any other calendars (iCloud, Google) the user has synced.
