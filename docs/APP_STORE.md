# App Store publication checklist

## Before the first upload

1. **Apple Developer Program** membership, then in Certificates, Identifiers & Profiles the App ID `com.humbleplanning.app` (it cannot be changed afterwards). Set the team in the project (`DEVELOPMENT_TEAM`), signing stays automatic.
2. Create the app in **App Store Connect** with that bundle ID; primary language English (U.S.); SKU `humble-planning-ios`.
   Its Apple ID (App Information) gives the App Store page: set `AppInfo.storeURL` (`Packages/HumbleCore/Sources/HumbleCore/Support/AppInfo.swift`) to `https://apps.apple.com/app/id<Apple ID>`, the page an outdated app opens when the server has none.
3. Host `docs/PRIVACY.md` at a public address (privacy policy URL); support URL: the repository's issues or the website.
4. **Servers:** the app needs a server in 1.2.3 or later (it identifies itself with `X-App-Platform: ios`). The public demo used for the review must run it too.
5. The distribution through the App Store is allowed by the additional permission of `LICENSE-EXCEPTION.md`; keep that file next to `LICENSE`.

## Build and upload

Raise `MARKETING_VERSION` (and always `CURRENT_PROJECT_VERSION`) in the project, see `RELEASING.md`, then in Xcode: Product > Archive, Distribute App > App Store Connect. Test the build with TestFlight before submitting it.

Once the app is published, set its App Store page in each server, *Settings > General > Mobile app > iOS app download page*, and in the server code as the default (`MOBILE_IOS_STORE_URL`), so that an outdated app opens it.

## App Review information

| Field | Answer |
|---|---|
| Sign-in required | Yes. Server `https://demo.humbleplanning.app`, account `humbledemo` / `humblepass` (the public demo of the README: second factor off, data reset every night) |
| Notes | "Humble Planning is a self-hosted team planning server; this app connects to the server of the user's organisation. Use the public demo server above: enter its address on the first screen, then the account." |
| Contact | The maintainer's name, e-mail and phone |

## App Privacy

The publisher receives nothing: the app sends data only to the Humble Planning server chosen by the user (the user's organisation), and the assistant's messages to the AI provider configured on that server. Under Apple's definitions this is usually declared **Data Not Collected**, because no data reaches the developer or its partners. Have someone check this answer against the current questions before submitting: it engages the publisher. `HumblePlanning/Resources/PrivacyInfo.xcprivacy` declares the required-reason APIs and no tracking.

## Other answers

| Form | Answer |
|---|---|
| Category | Business (secondary: Productivity) |
| Age rating | 4+, no sensitive content |
| Encryption (export compliance) | The app only uses the encryption of the system (HTTPS, Keychain, CryptoKit for the offline copy): check the current questions; such use is usually exempt |
| Content rights | No third-party content |
| Price | Free, all territories |

## Listing

**Name:** Humble Planning

### English (U.S.)

**Subtitle** (26/30): Your team's planning, live

**Promotional text** (149/170):
See your team's planning by day, week or month, create and edit tasks, and follow every change live, from your organisation's Humble Planning server.

**Keywords** (93/100): `planning,schedule,team,tasks,calendar,workforce,dispatch,shifts,field,open source,self-hosted`

**Description:**

Humble Planning is the open-source team planning application. This app connects to your organisation's Humble Planning server.

See your planning by day, week or month, or the whole team on one grid. Filter by person, team, project or status, and watch it update as your team changes it.

Create and edit tasks with several people, half days or exact times, recurrence, places, resources and attachments: photos from your library or files.

Get alerts as soon as one of your tasks changes, set reminders before a task starts, and ask the AI assistant when your server offers it. Your own tasks stay available offline.

The app follows the permissions of your account. It needs a Humble Planning server: ask your administrator for its address, or sign in by scanning the QR code of your web profile with the camera.

Open source under the AGPL-3.0 license.

**What's new in 1.0.2:** First version of Humble Planning for iPhone and iPad.

### Français

**Subtitle** (30/30): Le planning d'équipe en direct

**Promotional text** (170/170):
Consultez le planning de votre équipe par jour, semaine ou mois, créez et modifiez des tâches, et suivez chaque changement en direct depuis votre serveur Humble Planning.

**Keywords** (88/100): `planning,équipe,tâches,calendrier,agenda,chantier,intervention,planification,open source`

**Description:**

Humble Planning est l'application open source de planning d'équipe. Cette application se connecte au serveur Humble Planning de votre organisation.

Consultez votre planning par jour, semaine ou mois, ou toute l'équipe sur une seule grille. Filtrez par personne, équipe, projet ou statut, et voyez-le se mettre à jour dès que votre équipe le modifie.

Créez et modifiez des tâches avec plusieurs personnes, des demi-journées ou des horaires précis, des récurrences, des lieux, des ressources et des pièces jointes : photos de votre photothèque ou fichiers.

Recevez une alerte dès qu'une de vos tâches change, programmez des rappels avant le début d'une tâche, et interrogez l'assistant IA quand votre serveur le propose. Vos tâches restent consultables hors connexion.

L'application respecte les droits de votre compte. Elle nécessite un serveur Humble Planning : demandez son adresse à votre administrateur, ou connectez-vous en scannant avec l'appareil photo le QR code de votre profil web.

Open source sous licence AGPL-3.0.

**What's new in 1.0.2:** Première version de Humble Planning pour iPhone et iPad.

### Español (España)

**Subtitle** (29/30): La planificación de tu equipo

**Promotional text** (166/170):
Consulta la planificación de tu equipo por día, semana o mes, crea y edita tareas y sigue cada cambio en directo desde el servidor Humble Planning de tu organización.

**Keywords** (85/100): `planificación,equipo,tareas,calendario,agenda,turnos,obra,intervención,código abierto`

**Description:**

Humble Planning es la aplicación de código abierto para planificar el trabajo de un equipo. Esta aplicación se conecta al servidor Humble Planning de tu organización.

Consulta tu planificación por día, semana o mes, o todo el equipo en una sola cuadrícula. Filtra por persona, equipo, proyecto o estado, y mira cómo se actualiza en cuanto tu equipo la cambia.

Crea y edita tareas con varias personas, medias jornadas u horas exactas, repeticiones, lugares, recursos y archivos adjuntos: fotos de tu fototeca o archivos.

Recibe una alerta en cuanto cambia una de tus tareas, programa recordatorios antes de que empiece una tarea y pregunta al asistente de IA cuando tu servidor lo ofrece. Tus tareas siguen disponibles sin conexión.

La aplicación respeta los permisos de tu cuenta. Necesita un servidor Humble Planning: pide su dirección a tu administrador, o inicia sesión escaneando con la cámara el código QR de tu perfil web.

Código abierto con licencia AGPL-3.0.

**What's new in 1.0.2:** Primera versión de Humble Planning para iPhone y iPad.

### Deutsch

**Subtitle** (21/30): Die Teamplanung, live

**Promotional text** (170/170):
Sehen Sie die Planung Ihres Teams nach Tag, Woche oder Monat, erstellen und bearbeiten Sie Aufgaben und verfolgen Sie jede Änderung live von Ihrem Humble Planning Server.

**Keywords** (86/100): `planung,team,aufgaben,kalender,einsatzplanung,dienstplan,baustelle,termine,open source`

**Description:**

Humble Planning ist die Open-Source-Anwendung für die Teamplanung. Diese App verbindet sich mit dem Humble Planning Server Ihrer Organisation.

Sehen Sie Ihre Planung nach Tag, Woche oder Monat, oder das ganze Team in einem Raster. Filtern Sie nach Person, Team, Projekt oder Status und sehen Sie, wie sie sich aktualisiert, sobald Ihr Team sie ändert.

Erstellen und bearbeiten Sie Aufgaben mit mehreren Personen, halben Tagen oder genauen Uhrzeiten, Wiederholungen, Orten, Ressourcen und Anhängen: Fotos aus Ihrer Mediathek oder Dateien.

Erhalten Sie eine Benachrichtigung, sobald sich eine Ihrer Aufgaben ändert, stellen Sie Erinnerungen vor dem Beginn einer Aufgabe ein und fragen Sie den KI-Assistenten, wenn Ihr Server ihn anbietet. Ihre eigenen Aufgaben bleiben offline verfügbar.

Die App beachtet die Berechtigungen Ihres Kontos. Sie benötigt einen Humble Planning Server: Fragen Sie Ihren Administrator nach seiner Adresse oder melden Sie sich an, indem Sie den QR-Code Ihres Webprofils mit der Kamera scannen.

Open Source unter der Lizenz AGPL-3.0.

**What's new in 1.0.2:** Erste Version von Humble Planning für iPhone und iPad.

## Screenshots

| Display | Size | Simulator |
|---|---|---|
| iPhone 6.9" | 1320 x 2868 | iPhone 18 Pro Max |
| iPad 13" | 2064 x 2752 | iPad Pro 13-inch (M5) |

Made with the fictitious company of the test server, never with real data:

```bash
HP_SERVER_SRC=../HumblePlanning HP_ANDROID_REPO=../HumblePlanning-Android tools/screenshots.sh
```

The script starts a fresh test server, fills it with `seed.mjs`, sets the status bar (9:41, full battery and signal)
and runs `AppStoreScreenshots` on both simulators. The screens, in English and French, land in
`build/ui-shots/appstore/`: the week, the team grid, a task, Upcoming, Alerts, the assistant (English only: the
scripted answer of the test server is in English) and the grid in dark mode.
