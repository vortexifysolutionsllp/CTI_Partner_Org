/*
 * Lives in the PARTNER org.
 *
 * Creates one External Credential + Named Credential per subscriber org,
 * named CTI_{orgId}_{orgName} (sanitized, <= 40 chars, idempotent).
 *
 * IMPORTANT LIMITATION (by Salesforce design, not a gap in this code):
 * Neither ConnectApi.NamedCredentials nor Metadata API lets you set the
 * actual secret value of an authentication parameter (password, custom
 * header value, client secret, etc.) programmatically. This class only
 * creates the *structure*. An admin must open the resulting External
 * Credential's principal in Setup and enter the real auth value once,
 * then flip "Enabled for Callouts" on the Named Credential. See the
 * chat response for the full manual checklist.
 */
public with sharing class SubscriberCredentialProvisionerClass {

    private static final Integer MAX_DEV_NAME_LENGTH = 40;
    private static final String  PREFIX = 'CTI_';   // leading letter also satisfies the no-leading-digit rule, since org IDs start with '00D'
    private static final String  SUFFIX = '';        // no longer appended - CTI now leads instead

    // Point this at whatever the partner org actually needs to call for CTI purposes.
    // If every subscriber uses the same downstream endpoint (e.g. a shared Twilio account),
    // this can stay static. If each subscriber has its own callout target, pass it in instead.
    private static final String  DEFAULT_CALLOUT_URL = 'https://login.salesforce.com';

    private static String resolveCalloutUrl(String candidateUrl) {
        if (String.isBlank(candidateUrl)) {
            return DEFAULT_CALLOUT_URL;
        }
        String trimmed = candidateUrl.trim();
        if (trimmed.endsWith('/')) {
            trimmed = trimmed.removeEnd('/');
        }
        Boolean looksValid = trimmed.startsWithIgnoreCase('https://') && trimmed.length() <= 1200;
        return looksValid ? trimmed : DEFAULT_CALLOUT_URL;
    }

    /*
     * developerName + '_Principal' can exceed 40 chars on its own since
     * developerName alone can already be close to the limit. Truncate the
     * developerName portion, not the '_Principal' suffix, so it stays
     * recognizable as "this is the principal for that credential."
     */
    private static String buildPrincipalName(String developerName) {
        String suffix = '_Principal';
        String base = developerName == null ? '' : developerName;
        Integer allowed = MAX_DEV_NAME_LENGTH - suffix.length();
        if (base.length() > allowed) {
            base = base.substring(0, allowed);
        }
        base = base.replaceAll('_+$', '');
        return base + suffix;
    }

    public class ProvisionResult {
        public String  developerName;
        public Boolean externalCredentialCreated = false;
        public Boolean namedCredentialCreated = false;
    }

    /*
     * Builds CTI_{orgId}_{orgName}, sanitized to fit the 40-char /
     * letters-numbers-underscore / no-leading-digit rules that apply to
     * Named Credential and External Credential developer names. CTI leads
     * so every provisioned credential sorts and searches together in Setup.
     */
    public static String buildDeveloperName(String orgId, String orgName) {
        String cleanOrgId = orgId == null ? '' : orgId.replaceAll('[^a-zA-Z0-9]', '');
        // Trim to the 15-char case-sensitive base so the same org never produces
        // two different names depending on whether the 18-char ID was passed.
        if (cleanOrgId.length() > 15) {
            cleanOrgId = cleanOrgId.substring(0, 15);
        }

        String cleanOrgName = orgName == null ? '' : orgName.trim();
        cleanOrgName = cleanOrgName.replaceAll('[^a-zA-Z0-9]+', '_');
        cleanOrgName = cleanOrgName.replaceAll('_+', '_');
        cleanOrgName = cleanOrgName.replaceAll('^_|_$', '');

        Integer fixedLength = PREFIX.length() + cleanOrgId.length() + 1 + SUFFIX.length(); // +1 for the underscore before orgName
        Integer allowedNameLength = MAX_DEV_NAME_LENGTH - fixedLength;
        if (allowedNameLength < 1) {
            allowedNameLength = 1;
        }
        if (cleanOrgName.length() > allowedNameLength) {
            cleanOrgName = cleanOrgName.substring(0, allowedNameLength);
            cleanOrgName = cleanOrgName.replaceAll('_+$', '');
        }
        if (String.isBlank(cleanOrgName)) {
            cleanOrgName = 'Sub';
        }

        String devName = PREFIX + cleanOrgId + '_' + cleanOrgName + SUFFIX;
        return devName.replaceAll('_+', '_');
    }

    /*
     * Idempotent: safe to call every time a subscriber's post-install job
     * fires (reinstalls, upgrades) without creating duplicates.
     *
     * calloutUrl: the subscriber org's own base URL (e.g. their My Domain),
     * sent up from the subscriber side via URL.getOrgDomainUrl(). Falls back
     * to DEFAULT_CALLOUT_URL if blank or not a valid https URL, so a bad or
     * missing value never breaks credential creation - it just uses the
     * fallback instead of pointing nowhere.
     */
    public static ProvisionResult provision(String developerName, String orgId, String orgName, String calloutUrl) {
        ProvisionResult result = new ProvisionResult();
        result.developerName = developerName;
        System.debug('RAW calloutUrl received by provision(): "' + calloutUrl + '"');

        Boolean externalExists = true;
        try {
            ConnectApi.NamedCredentials.getExternalCredential(developerName);
        } catch (Exception e) {
            externalExists = false;
        }

        if (!externalExists) {
            ConnectApi.ExternalCredentialInput ecInput = new ConnectApi.ExternalCredentialInput();
            ecInput.developerName = developerName;
            ecInput.masterLabel = 'CTI - ' + orgName + ' (' + orgId + ')';
            // Custom protocol: creates the shell without requiring a secret up front.
            // Switch to Password/OAuth here if your CTI auth scheme needs it, but the
            // actual secret still has to be entered manually either way (see class header).
            ecInput.authenticationProtocol = ConnectApi.CredentialAuthenticationProtocol.Custom;

            ConnectApi.ExternalCredentialPrincipalInput principal =
                new ConnectApi.ExternalCredentialPrincipalInput();
            principal.principalName = buildPrincipalName(developerName);
            principal.principalType = ConnectApi.CredentialPrincipalType.NamedPrincipal;
            principal.sequenceNumber = 1;

            ecInput.principals = new List<ConnectApi.ExternalCredentialPrincipalInput>{ principal };

            ConnectApi.NamedCredentials.createExternalCredential(ecInput);
            result.externalCredentialCreated = true;
        }

        Boolean namedExists = true;
        try {
            ConnectApi.NamedCredentials.getNamedCredential(developerName);
        } catch (Exception e) {
            namedExists = false;
        }

        if (!namedExists) {
            ConnectApi.NamedCredentialInput ncInput = new ConnectApi.NamedCredentialInput();
            ncInput.developerName = developerName;
            ncInput.masterLabel = 'CTI - ' + orgName;
            ncInput.type = ConnectApi.NamedCredentialType.SecuredEndpoint;
            ncInput.calloutUrl = resolveCalloutUrl(calloutUrl);

            ConnectApi.ExternalCredentialInput ecRef = new ConnectApi.ExternalCredentialInput();
            ecRef.developerName = developerName;
            ncInput.externalCredentials = new List<ConnectApi.ExternalCredentialInput>{ ecRef };

            ConnectApi.NamedCredentialCalloutOptionsInput calloutOptions =
                new ConnectApi.NamedCredentialCalloutOptionsInput();
            calloutOptions.generateAuthorizationHeader = true;
            calloutOptions.allowMergeFieldsInBody = false;
            calloutOptions.allowMergeFieldsInHeader = false;
            ncInput.calloutOptions = calloutOptions;

            ConnectApi.NamedCredentials.createNamedCredential(ncInput);
            result.namedCredentialCreated = true;
        }

        return result;
    }
}