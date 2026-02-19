{
  "BriteVerify": {
    "apiKey": "${BRITEVERIFY_API_KEY}",
    "performValidation": ${BRITEVERIFY_PERFORM_VALIDATION:-false}
  },
  "ChangeHealthcare": {
    "baseUrl": "${CHANGE_HEALTHCARE_BASE_URL}",
    "clientId": "${CHANGE_HEALTHCARE_CLIENT_ID}",
    "clientSecret": "${CHANGE_HEALTHCARE_CLIENT_SECRET}",
    "debugLogging": true
  },
  "ChangeStreams": {
    "enabled": ${MONGO_CHANGE_STREAMS:-false}
  },
  "ClientFlags": {
    "assetBaseUrl": "${CLIENT_ASSET_BASE_URL}",
    "raPhoneNumber": "${CLIENT_RA_PHONE_NUMBER}"
  },
  "Cloudwatch": {
    "enabled": true
  },
  "Environment": {
    "serverType": "${SERVER_TYPE}",
    "name": "${ENVIRONMENT_NAME}",
    "shortName": "${DEPLOY_ENV}",
    "release": "${DEPLOY_TAG}",
    "appUrl": "una://app",
    "baseUrl": "${BASE_URL}",
    "providerUrl": "${PROVIDER_URL}",
    "adminUrl": "${ADMIN_URL}",
    "appInstallUrl": "${APP_INSTALL_URL}",
    "seatUrl": "${SEAT_URL}",
    "seatSimulatorUrl": "${SEAT_SIMULATOR_URL}",
    "patientPortalUrl": "${PATIENT_PORTAL_URL}",
    "websiteUrl": "${WEBSITE_URL}",
    "extraAllowedHosts": ${EXTRA_ALLOWED_HOSTS:-[]},
    "apiProtocol": "${API_PROTOCOL}",
    "apiUrl": "${API_URL}",
    "dbUri": "${MONGO_URI}",
    "dbUsername": "${MONGO_USERNAME}",
    "dbPassword": "${MONGO_PASSWORD}",
    "dbUrl": "${MONGO_URL}",
    "dbPrefix": "${MONGO_PREFIX}",
    "readOnlyDbUri": "${MONGO_READ_ONLY_URI}",
    "readOnlyDbUsername": "${MONGO_READ_ONLY_USERNAME}",
    "readOnlyDbPassword": "${MONGO_READ_ONLY_PASSWORD}",
    "logToFileSystem": true,
    "usesHttpProxy": true,
    "sendNotifications": true,
    "directToConsumerId": "${DIRECT_TO_CONSUMER_ID}",
    "growthId": "${GROWTH_ID}",
    "defaultMessagingPersonalityId": "${DEFAULT_MESSAGING_PERSONALITY_ID}",
    "slowRequestThresholdMs": 1000,
    "getUpdatesInterval": 500,
    "passwordIterations": 600000,
    "sessionSecret": "${SESSION_SECRET}",
    "jwtSecret": "${JWT_SECRET}"
  },
  "Firebase": {
    "enabled": ${FIREBASE_ENABLED:-true},
    "serverKey": "${FIREBASE_SERVER_KEY}",
    "senderId": "${FIREBASE_SENDER_ID}"
  },
  "Github": {
    "enabled": true,
    "id": "${GITHUB_OAUTH_ID}",
    "secret": "${GITHUB_OAUTH_SECRET}"
  },
  "GoogleAnalytics": {
    "enabled": true,
    "propertyId": "${GOOGLE_ANALYTICS_PROPERTY_ID}"
  },
  "GoogleCalendar": {
    "enabled": true,
    "clientId": "${GCAL_CLIENT_ID}",
    "clientSecret": "${GCAL_CLIENT_SECRET}",
    "defaultInvitees": ${GCAL_DEFAULT_INVITEES:-[]},
    "redirectUrl": "http://localhost:5000/oauth2callback",
    "pptTxCallsCalendarId": "${GCAL_CALLS_CALENDAR_ID}",
    "refreshToken": "${GCAL_REFRESH_TOKEN}"
  },
  "Images": {
    "disableExternalServicesForTest": false,
    "enableResizing": ${IMAGES_ENABLE_RESIZING:-true},
    "maxSize": "20MB",
    "suggestedPostStar": "f497fcb8-be7b-4bc2-83a4-ace7495f2879",
    "s3Bucket": "${IMAGES_S3_BUCKET}"
  },
  "Iterable": {
    "Api-Key": "${ITERABLE_API_KEY}",
    "baseUrl": "${ITERABLE_BASE_URL}",
    "customSMSCampaignId": "${ITERABLE_CUSTOM_SMS_CAMPAIGN}",
    "CampaignIds": {
      "sms": {
        "CUSTOM_ONE_OFF_SMS__BLANK_TEMPLATE": "${CUSTOM_ONE_OFF_SMS__BLANK_TEMPLATE}",
        "PATIENT_MOBILE_LOGIN": "${PATIENT_MOBILE_LOGIN_SMS}"
      },
      "email": {
        "BRITEVERIFY_CHECK_COMPLETE": "${GENERIC_EMAIL_TEMPLATE}",
        "PRACTICE_ALERT_NOTIFICATION": "${PRACTICE_ALERT_NOTIFICATION}",
        "PATIENT_INELIGIBLE__OPTED_OUT": "${PATIENT_INELIGIBLE__OPTED_OUT}",
        "PATIENT_INELIGIBLE__ESTIMATION_OF_BENEFIT": "${PATIENT_INELIGIBLE__OPTED_OUT}",
        "PATIENT_INELIGIBLE__LEFT_PRACTICE": "${PATIENT_INELIGIBLE__LEFT_PRACTICE}",
        "PATIENT_INELIGIBLE__NO_DIAGNOSIS": "${PATIENT_INELIGIBLE__NO_DIAGNOSIS}",
        "PATIENT_INELIGIBLE__INSURANCE_CHANGE": "${PATIENT_INELIGIBLE__INSURANCE_CHANGE}",
        "NEW_ALERT": "${PRACTICE_ALERT_NOTIFICATION}",
        "NEW_ACTIVITY_IN_PROGRESS_ALERT": "${NEW_ACTIVITY_IN_PROGRESS_ALERT}",
        "NEW_ACTIVITY_OPEN_ALERT": "${NEW_ACTIVITY_OPEN_ALERT}",
        "ALERT_OVERDUE": "${ALERT_OVERDUE}",
        "NEW_ACTIVITY_OVERDUE_ALERT": "${NEW_ACTIVITY_OVERDUE_ALERT}",
        "PASSWORD_RESET": "${PASSWORD_RESET}",
        "BULK_ACTION_COMPLETED": "${BULK_ACTION_COMPLETED}",
        "CLAIM_START": "${CLAIM_START}",
        "BULK_MESSAGE_COMPLETED": "${BULK_MESSAGE_COMPLETED}",
        "BULK_ACTION_STARTED": "${BULK_ACTION_STARTED}",
        "CLAIM_STATUS_CHECK_COMPLETED": "${CLAIM_STATUS_CHECK_COMPLETED}",
        "CLAIM_STATUS_CHECK_STARTED": "${CLAIM_STATUS_CHECK_STARTED}",
        "CLAIM_COMPLETED": "${CLAIM_COMPLETED}",
        "PATIENT_MOBILE_LOGIN": "${PATIENT_MOBILE_LOGIN_EMAIL}"
      }
    },
    "OVERRIDES": { "Staging": { "easyAccess": { "info": true } } },
    "listReferences": {
      "defaultListName": "default"
    },
    "webhookUser": "${ITERABLE_WEBHOOK_USER}",
    "webhookPassword": "${ITERABLE_WEBHOOK_PASSWORD}"
  },
  "Jobs": {
    "ALARM_THRESHOLD": "${SANITY_CHECK_THRESHOLD}",
    "VALIDATOR_DOCUMENT_LIMIT": ${DOCUMENT_VALIDATION_COUNT:-100},
    "S3_BUCKET": "internal.triggrhealth.com",
    "STALE_GUIDE_OUTREACH_TIMEOUT_MINUTES": 60,
    "STALE_INTRO_OUTREACH_TIMEOUT_MINUTES": 20,
    "ORPHANED_PARTICIPANTS_HIGH_URGENCY_THRESHOLD": 20,
    "ORPHANED_PARTICIPANTS_ALERT_MINUTES": 150
  },
  "MachineLearning": {
    "enabled": false
  },
  "MLPredictionServer": {
    "baseUrl": "${ML_SERVER_URL}",
    "mode": "${ML_SERVER_PREDICTION_MODE}"
  },
  "Messages": {
    "DUPLICATE_MESSAGE_MIN_LENGTH": 20,
    "BULK_SCHEDULED_MESSAGE_WINDOW": 0,
    "WELCOME_MESSAGE_GAP_SECONDS": 4,
    "DEFAULT_RESPONSE_TIME_MINUTES": 5,
    "AUTOREPLY_ENABLED": true,
    "AUTOREPLY_MINIMUM_DAYS_SINCE": 21,
    "RESPONSE_TIME_WINDOW": 60
  },
  "MightyCall": {
    "API_KEY": "fab493b4-513b-4595-a586-7e4cd3a51a4e",
    "PhoneNumbers": {
      "+15555551234": {
        "+18444228744": {"name": "New Hope Recovery Center"},
        "+18552585678": {"name": "Triggr General"}
      }
    }
  },
  "Mixpanel": {
    "MOBILE_API_SECRET": "${MIXPANEL_MOBILE_API_SECRET}",
    "MOBILE_TOKEN": "${MIXPANEL_MOBILE_TOKEN}"
  },
  "Mongoose": {
    "autoIndex": ${MONGOOSE_AUTO_INDEX:-true}
  },
  "PagerDuty": {
    "ENG_SERVICE_KEY_LOW_URGENCY": "${PAGERDUTY_KEY_LOW_PRIORITY}",
    "ENG_SERVICE_KEY_HIGH_URGENCY": "${PAGERDUTY_KEY_HIGH_PRIORITY}"
  },
  "Reports": {
    "s3Bucket": "${REPORTS_S3_BUCKET}",
    "enabled": ${REPORTS_ENABLED:-false},
    "signedUrlExpiry": ${REPORTS_SIGNED_URL_EXPIRES:-1}
  },
  "Redis": {
    "enabled": ${REDIS_ENABLED:-false},
    "AUTH_TOKEN": "${REDIS_AUTH_TOKEN}",
    "endpoint": "${REDIS_ENDPOINT}"
  },
  "SageMaker": {
    "region": "us-east-2",
    "enrollmentEndpointName": "${SAGEMAKER_ENROLLMENT_ENDPOINT_NAME}"
  },
  "SendGrid": {
    "API_KEY": "${SENDGRID_API_KEY}",
    "useTemplateIds": true
  },
  "Sentry": {
    "enabled": true,
    "destination": "https://0097de20b5884c19af95de50e52598fb@o363493.ingest.sentry.io/4456506"
  },
  "Sftp": {
    "enabled": ${SFTP_ENABLED:-false},
    "debug": false,
    "port": 8022,
    "users": ${SFTP_USERS:-[]}
  },
  "Slack": {
    "addClinicLeadChannel": "${SLACK_ADD_CLINIC_LEAD_CHANNEL}",
    "botToken": "${SLACK_BOT_TOKEN}",
    "claimsWebhook": "${SLACK_CLAIMS_WEBHOOK}",
    "feedContentChannel": "${SLACK_FEED_CONTENT_CHANNEL}",
    "growthAlertChannel": "${SLACK_GROWTH_ALERT_CHANNEL}",
    "growthCallRemindersChannel": "${SLACK_GROWTH_CALL_REMINDERS_CHANNEL}",
    "introAlertChannel": "${SLACK_INTRO_ALERT_CHANNEL}",
    "invalidPhoneNumberChannel": "${SLACK_INVALID_PHONE_NUMBER_CHANNEL}",
    "locationAlertsChannel": "${SLACK_LOCATION_ALERTS_CHANNEL}",
    "newLeadAlertChannel": "${SLACK_NEW_LEAD_ALERT_CHANNEL}",
    "orphanedPatientAlertChannel": "${SLACK_ORPHANED_PPT_ALERT_CHANNEL}",
    "peerConversationsChannel": "${SLACK_PEER_CONVERSATIONS_CHANNEL}",
    "raAlertChannel": "${SLACK_RA_ALERT_CHANNEL}",
    "seatSimulatorResultsChannel": "${SLACK_SEAT_SIMULATOR_RESULTS_CHANNEL}",
    "responseTimeAlertChannel": "${SLACK_RESPONSE_TIME_ALERT_CHANNEL}",
    "supportSquadAlertChannel": "${SLACK_SUPPORT_SQUAD_ALERT_CHANNEL}",
    "supporterAlertChannel": "${SLACK_SUPPORTER_ALERT_CHANNEL}",
    "undeliverableEmailAlertsWebhook": "${SLACK_UNDELIVERABLE_EMAIL_ALERTS_WEBHOOK}",
    "undeliverableMessageAlertsWebhookUrl": "${SLACK_UNDELIVERABLE_MESSAGE_ALERTS_WEBHOOK}",
    "verificationToken": "${SLACK_VERIFICATION_TOKEN}"
  },
  "Twilio": {
    "ACCOUNT_SID": "AC97afd88131d8a292302748dacc66de38",
    "AUTH_TOKEN": "${TWILIO_AUTH_TOKEN}",
    "API_KEY": "${TWILIO_API_KEY}",
    "API_SECRET": "${TWILIO_API_SECRET}",
    "alertSid": "${TWILIO_ALERT_SID}",
    "patientConversationSid": "${TWILIO_PATIENT_CONVO_SID}",
    "batphoneNumber": "+13129149336",
    "defaultOutboundPhoneNumber": "${TWILIO_OUTGOING_PHONE_NUMBER}",
    "defaultSmsPhoneNumber": "${TWILIO_DEFAULT_SMS_PHONE_NUMBER}",
    "outboundPhoneNumbers": ${TWILIO_OUTBOUND_PHONE_NUMBERS:-[]},
    "pointOfCaptureMap": {
      "+13122486015": "Facebook Page",
      "+13122487079": "Brochure Dec2016",
      "+13122783468": "20161222 FB iOS_AN",
      "+13122783621": "20161222 FB PromotionAd",
      "+13123132864": "Inbound TX Lead",
      "+13123132881": "20161219 CTA Bus Family",
      "+13123132958": "20161219 CTA Rail Anxious",
      "+13123132986": "20161219 CTA Rail Family",
      "+13122486218": "20170104 TriggrHealth.com"
    },
    "validateRequests": true,
    "IVR_FLOW_SID": "${TWILIO_IVR_FLOW_SID}",
    "VOICE_APP_SID": "${TWILIO_VOICE_APP_SID}"
  },
  "Upload": {
    "maxSize": 5000000
  }
}
