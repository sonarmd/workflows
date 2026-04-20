#!/usr/bin/env node
/**
 * Generates configuration.json from environment variables.
 *
 * Replaces Ansible's configuration.j2 template rendering.
 * Run at container startup via docker-entrypoint.sh.
 *
 * Env var naming convention:
 *   - Secrets come from 1Password (via ECS task definition)
 *   - Environment config comes from ECS task definition env vars
 *   - Static values are hardcoded below (same across all environments)
 */

const fs = require('fs');
const path = require('path');

const e = process.env;

// Helper: parse JSON env var with fallback
const jsonVar = (name, fallback) => {
  try { return JSON.parse(e[name] || ''); }
  catch { return fallback; }
};

const config = {
  BriteVerify: {
    apiKey: e.BRITEVERIFY_API_KEY || '',
    performValidation: jsonVar('BRITEVERIFY_PERFORM_VALIDATION', false)
  },
  ChangeHealthcare: {
    baseUrl: e.CHANGE_HEALTHCARE_BASE_URL || '',
    clientId: e.CHANGE_HEALTHCARE_CLIENT_ID || '',
    clientSecret: e.CHANGE_HEALTHCARE_CLIENT_SECRET || '',
    debugLogging: true
  },
  ChangeStreams: {
    enabled: jsonVar('CHANGE_STREAMS_ENABLED', false)
  },
  ClientFlags: {
    assetBaseUrl: e.CLIENT_ASSET_BASE_URL || '',
    raPhoneNumber: e.CLIENT_RA_PHONE_NUMBER || ''
  },
  Cloudwatch: {
    enabled: true
  },
  Environment: {
    serverType: e.SERVER_TYPE || 'Server',
    name: e.ENVIRONMENT_NAME || '',
    shortName: e.DEPLOY_ENV || '',
    release: e.DEPLOY_TAG || '',
    appUrl: 'una://app',
    baseUrl: e.BASE_URL || '',
    providerUrl: e.PROVIDER_URL || '',
    adminUrl: e.ADMIN_URL || '',
    appInstallUrl: e.APP_INSTALL_URL || '',
    seatUrl: e.SEAT_URL || '',
    seatSimulatorUrl: e.SEAT_SIMULATOR_URL || '',
    patientPortalUrl: e.PATIENT_PORTAL_URL || '',
    websiteUrl: e.WEBSITE_URL || '',
    extraAllowedHosts: jsonVar('EXTRA_ALLOWED_HOSTS', []),
    apiProtocol: e.API_PROTOCOL || 'https',
    apiUrl: e.API_URL || '',
    dbUri: e.MONGO_URI || '',
    dbUsername: e.MONGO_USERNAME || '',
    dbPassword: e.MONGO_PASSWORD || '',
    dbUrl: e.MONGO_URL || '',
    dbPrefix: e.MONGO_PREFIX || '',
    readOnlyDbUri: e.MONGO_READ_ONLY_URI || '',
    readOnlyDbUsername: e.MONGO_READ_ONLY_USERNAME || '',
    readOnlyDbPassword: e.MONGO_READ_ONLY_PASSWORD || '',
    logToFileSystem: true,
    usesHttpProxy: true,
    sendNotifications: true,
    directToConsumerId: e.DIRECT_TO_CONSUMER_ID || '',
    growthId: e.GROWTH_ID || '',
    defaultMessagingPersonalityId: e.DEFAULT_MESSAGING_PERSONALITY_ID || '',
    slowRequestThresholdMs: 1000,
    getUpdatesInterval: 500,
    passwordIterations: 600000,
    sessionSecret: e.SESSION_SECRET || '',
    jwtSecret: e.JWT_SECRET || ''
  },
  Firebase: {
    enabled: jsonVar('FIREBASE_ENABLED', false),
    serverKey: e.FIREBASE_SERVER_KEY || '',
    senderId: e.FIREBASE_SENDER_ID || ''
  },
  Github: {
    enabled: true,
    id: e.GITHUB_OAUTH_ID || '',
    secret: e.GITHUB_OAUTH_SECRET || ''
  },
  GoogleAnalytics: {
    enabled: true,
    propertyId: e.GOOGLE_ANALYTICS_PROPERTY_ID || ''
  },
  GoogleCalendar: {
    enabled: true,
    clientId: e.GCAL_CLIENT_ID || '',
    clientSecret: e.GCAL_CLIENT_SECRET || '',
    defaultInvitees: jsonVar('GCAL_DEFAULT_INVITEES', []),
    redirectUrl: 'http://localhost:5000/oauth2callback',
    pptTxCallsCalendarId: e.GCAL_CALLS_CALENDAR_ID || '',
    refreshToken: e.GCAL_REFRESH_TOKEN || ''
  },
  Images: {
    disableExternalServicesForTest: false,
    enableResizing: jsonVar('IMAGES_ENABLE_RESIZING', false),
    maxSize: '20MB',
    suggestedPostStar: 'f497fcb8-be7b-4bc2-83a4-ace7495f2879',
    s3Bucket: e.IMAGES_S3_BUCKET || ''
  },
  Iterable: {
    'Api-Key': e.ITERABLE_API_KEY || '',
    baseUrl: e.ITERABLE_BASE_URL || '',
    customSMSCampaignId: e.ITERABLE_CUSTOM_SMS_CAMPAIGN || '',
    CampaignIds: {
      sms: {
        CUSTOM_ONE_OFF_SMS__BLANK_TEMPLATE: e.CUSTOM_ONE_OFF_SMS__BLANK_TEMPLATE || '',
        PATIENT_MOBILE_LOGIN: e.PATIENT_MOBILE_LOGIN_SMS || e.CUSTOM_ONE_OFF_SMS__BLANK_TEMPLATE || ''
      },
      email: {
        BRITEVERIFY_CHECK_COMPLETE: e.GENERIC_EMAIL_TEMPLATE || '',
        PRACTICE_ALERT_NOTIFICATION: e.PRACTICE_ALERT_NOTIFICATION || '',
        PATIENT_INELIGIBLE__OPTED_OUT: e.PATIENT_INELIGIBLE__OPTED_OUT || '',
        PATIENT_INELIGIBLE__ESTIMATION_OF_BENEFIT: e.PATIENT_INELIGIBLE__OPTED_OUT || '',
        PATIENT_INELIGIBLE__LEFT_PRACTICE: e.PATIENT_INELIGIBLE__LEFT_PRACTICE || '',
        PATIENT_INELIGIBLE__NO_DIAGNOSIS: e.PATIENT_INELIGIBLE__NO_DIAGNOSIS || '',
        PATIENT_INELIGIBLE__INSURANCE_CHANGE: e.PATIENT_INELIGIBLE__INSURANCE_CHANGE || '',
        NEW_ALERT: e.PRACTICE_ALERT_NOTIFICATION || '',
        NEW_ACTIVITY_IN_PROGRESS_ALERT: e.NEW_ACTIVITY_IN_PROGRESS_ALERT || '',
        NEW_ACTIVITY_OPEN_ALERT: e.NEW_ACTIVITY_OPEN_ALERT || '',
        ALERT_OVERDUE: e.ALERT_OVERDUE || '',
        NEW_ACTIVITY_OVERDUE_ALERT: e.NEW_ACTIVITY_OVERDUE_ALERT || '',
        PASSWORD_RESET: e.PASSWORD_RESET || '',
        BULK_ACTION_COMPLETED: e.BULK_ACTION_COMPLETED || '',
        CLAIM_START: e.CLAIM_START || '',
        BULK_MESSAGE_COMPLETED: e.BULK_MESSAGE_COMPLETED || '',
        BULK_ACTION_STARTED: e.BULK_ACTION_STARTED || '',
        CLAIM_STATUS_CHECK_COMPLETED: e.CLAIM_STATUS_CHECK_COMPLETED || '',
        CLAIM_STATUS_CHECK_STARTED: e.CLAIM_STATUS_CHECK_STARTED || '',
        CLAIM_COMPLETED: e.CLAIM_COMPLETED || '',
        PATIENT_MOBILE_LOGIN: e.PATIENT_MOBILE_LOGIN_EMAIL || ''
      }
    },
    OVERRIDES: { Staging: { easyAccess: { info: true } } },
    listReferences: {
      defaultListName: 'default'
    },
    webhookUser: e.ITERABLE_WEBHOOK_USER || '',
    webhookPassword: e.ITERABLE_WEBHOOK_PASSWORD || ''
  },
  Jobs: {
    ALARM_THRESHOLD: e.SANITY_CHECK_THRESHOLD || '100',
    VALIDATOR_DOCUMENT_LIMIT: parseInt(e.DOCUMENT_VALIDATION_COUNT || '100', 10),
    S3_BUCKET: 'internal.triggrhealth.com',
    STALE_GUIDE_OUTREACH_TIMEOUT_MINUTES: 60,
    STALE_INTRO_OUTREACH_TIMEOUT_MINUTES: 20,
    ORPHANED_PARTICIPANTS_HIGH_URGENCY_THRESHOLD: 20,
    ORPHANED_PARTICIPANTS_ALERT_MINUTES: 150
  },
  MachineLearning: {
    enabled: false
  },
  MLPredictionServer: {
    baseUrl: e.ML_SERVER_URL || '',
    mode: e.ML_SERVER_PREDICTION_MODE || 'disabled'
  },
  Messages: {
    DUPLICATE_MESSAGE_MIN_LENGTH: 20,
    BULK_SCHEDULED_MESSAGE_WINDOW: 0,
    WELCOME_MESSAGE_GAP_SECONDS: 4,
    DEFAULT_RESPONSE_TIME_MINUTES: 5,
    AUTOREPLY_ENABLED: true,
    AUTOREPLY_MINIMUM_DAYS_SINCE: 21,
    RESPONSE_TIME_WINDOW: 60
  },
  MightyCall: {
    API_KEY: 'fab493b4-513b-4595-a586-7e4cd3a51a4e',
    PhoneNumbers: {
      '+15555551234': {
        '+18444228744': { name: 'New Hope Recovery Center' },
        '+18552585678': { name: 'Triggr General' }
      }
    }
  },
  Mixpanel: {
    MOBILE_API_SECRET: e.MIXPANEL_MOBILE_API_SECRET || '',
    MOBILE_TOKEN: e.MIXPANEL_MOBILE_TOKEN || ''
  },
  Mongoose: {
    autoIndex: jsonVar('MONGOOSE_AUTO_INDEX', true)
  },
  PagerDuty: {
    ENG_SERVICE_KEY_LOW_URGENCY: e.PAGERDUTY_KEY_LOW_PRIORITY || '',
    ENG_SERVICE_KEY_HIGH_URGENCY: e.PAGERDUTY_KEY_HIGH_PRIORITY || ''
  },
  Reports: {
    s3Bucket: e.REPORTS_S3_BUCKET || '',
    enabled: jsonVar('REPORTS_ENABLED', false),
    signedUrlExpiry: parseInt(e.REPORTS_SIGNED_URL_EXPIRES || '1', 10)
  },
  Redis: {
    enabled: jsonVar('REDIS_ENABLED', false),
    AUTH_TOKEN: e.REDIS_AUTH_TOKEN || '',
    endpoint: e.REDIS_ENDPOINT || ''
  },
  SageMaker: {
    region: 'us-east-2',
    enrollmentEndpointName: e.SAGEMAKER_ENROLLMENT_ENDPOINT || ''
  },
  SendGrid: {
    API_KEY: e.SENDGRID_API_KEY || '',
    useTemplateIds: true
  },
  Sentry: {
    enabled: true,
    destination: 'https://0097de20b5884c19af95de50e52598fb@o363493.ingest.sentry.io/4456506'
  },
  Sftp: {
    enabled: jsonVar('SFTP_ENABLED', false),
    debug: false,
    port: 8022,
    users: jsonVar('SFTP_USERS', [])
  },
  Slack: {
    addClinicLeadChannel: e.SLACK_ADD_CLINIC_LEAD_CHANNEL || '',
    botToken: e.SLACK_BOT_TOKEN || '',
    claimsWebhook: e.SLACK_CLAIMS_WEBHOOK || '',
    feedContentChannel: e.SLACK_FEED_CONTENT_CHANNEL || '',
    growthAlertChannel: e.SLACK_GROWTH_ALERT_CHANNEL || '',
    growthCallRemindersChannel: e.SLACK_GROWTH_CALL_REMINDERS_CHANNEL || '',
    introAlertChannel: e.SLACK_INTRO_ALERT_CHANNEL || '',
    invalidPhoneNumberChannel: e.SLACK_INVALID_PHONE_NUMBER_CHANNEL || '',
    locationAlertsChannel: e.SLACK_LOCATION_ALERTS_CHANNEL || '',
    newLeadAlertChannel: e.SLACK_NEW_LEAD_ALERT_CHANNEL || '',
    orphanedPatientAlertChannel: e.SLACK_ORPHANED_PPT_ALERT_CHANNEL || '',
    peerConversationsChannel: e.SLACK_PEER_CONVERSATIONS_CHANNEL || '',
    raAlertChannel: e.SLACK_RA_ALERT_CHANNEL || '',
    seatSimulatorResultsChannel: e.SLACK_SEAT_SIMULATOR_RESULTS_CHANNEL || '',
    responseTimeAlertChannel: e.SLACK_RESPONSE_TIME_ALERT_CHANNEL || '',
    supportSquadAlertChannel: e.SLACK_SUPPORT_SQUAD_ALERT_CHANNEL || '',
    supporterAlertChannel: e.SLACK_SUPPORTER_ALERT_CHANNEL || '',
    undeliverableEmailAlertsWebhook: e.SLACK_UNDELIVERABLE_EMAIL_ALERTS_WEBHOOK || '',
    undeliverableMessageAlertsWebhookUrl: e.SLACK_UNDELIVERABLE_MESSAGE_ALERTS_WEBHOOK_URL || '',
    verificationToken: e.SLACK_COMMUNITY_WEBHOOK_VERIFICATION_TOKEN || ''
  },
  Twilio: {
    ACCOUNT_SID: 'AC97afd88131d8a292302748dacc66de38',
    AUTH_TOKEN: e.TWILIO_AUTH_TOKEN || '',
    API_KEY: e.TWILIO_API_KEY || '',
    API_SECRET: e.TWILIO_API_SECRET || '',
    alertSid: e.TWILIO_ALERT_SID || '',
    patientConversationSid: e.TWILIO_PATIENT_CONVO_SID || '',
    batphoneNumber: '+13129149336',
    defaultOutboundPhoneNumber: e.TWILIO_OUTGOING_PHONE_NUMBER || '',
    defaultSmsPhoneNumber: e.TWILIO_DEFAULT_SMS_PHONE_NUMBER || '',
    outboundPhoneNumbers: jsonVar('TWILIO_OUTBOUND_PHONE_NUMBERS', []),
    pointOfCaptureMap: {
      '+13122486015': 'Facebook Page',
      '+13122487079': 'Brochure Dec2016',
      '+13122783468': '20161222 FB iOS_AN',
      '+13122783621': '20161222 FB PromotionAd',
      '+13123132864': 'Inbound TX Lead',
      '+13123132881': '20161219 CTA Bus Family',
      '+13123132958': '20161219 CTA Rail Anxious',
      '+13123132986': '20161219 CTA Rail Family',
      '+13122486218': '20170104 TriggrHealth.com'
    },
    validateRequests: true,
    IVR_FLOW_SID: e.TWILIO_IVR_FLOW_SID || '',
    VOICE_APP_SID: e.TWILIO_VOICE_APP_SID || ''
  },
  Upload: {
    maxSize: 5000000
  }
};

const outputPath = e.CONFIG_OUTPUT_PATH || path.join(__dirname, 'configuration.json');
fs.writeFileSync(outputPath, JSON.stringify(config, null, 2));
console.log(`configuration.json written to ${outputPath}`);
